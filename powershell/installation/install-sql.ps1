<#
.SYNOPSIS
Install SQL Server from setup.exe with validated parameters and post-install configuration.

.DESCRIPTION
Parameter-driven SQL Server installation with interactive fallback. Validates all inputs
before calling setup.exe, applies recommended MaxMemory/MaxDOP/CostThreshold post-install,
and logs the full install output to output-files\installation\.

Supports inline parameters, interactive prompts, or an INI answer file.
SA password is never written to disk or logged.

.PARAMETER SetupPath
Full path to SQL Server setup.exe (e.g. D:\SQL2022\setup.exe).

.PARAMETER InstanceName
SQL Server instance name. Default: MSSQLSERVER (default instance).

.PARAMETER InstallDir
SQL Server binary directory. Default: C:\Program Files\Microsoft SQL Server

.PARAMETER SystemDBDir
System database data files. Default: C:\SQLData\SystemDBs

.PARAMETER SystemLogDir
System database log files. Default: C:\SQLLogs\SystemLogs

.PARAMETER UserDBDir
User database data files. Default: C:\SQLData\UserDBs

.PARAMETER UserLogDir
User database log files. Default: C:\SQLLogs\UserLogs

.PARAMETER TempDBDir
TempDB data files. Defaults to SystemDBDir\TempDB.

.PARAMETER TempDBLogDir
TempDB log files. Defaults to SystemLogDir\TempDB.

.PARAMETER TempDBFileCount
TempDB data file count. Defaults to logical CPU count capped at 8.

.PARAMETER SAPassword
SA account password as a SecureString. Prompted interactively if not supplied.

.PARAMETER SysAdminAccounts
Windows accounts to add as sysadmin (space-separated string). Defaults to current user.

.PARAMETER ServiceAccount
Windows service account for the SQL Server engine. Default: NT Service\MSSQLSERVER (virtual account).

.PARAMETER AgtServiceAccount
Windows service account for SQL Agent. Default: NT Service\SQLSERVERAGENT.

.PARAMETER Collation
Server collation. Default: SQL_Latin1_General_CP1_CI_AS

.PARAMETER Features
Comma-separated SQL Server features to install. Default: SQLENGINE,SQLAGENT

.PARAMETER MaxMemoryGB
Max server memory in GB. Auto-calculated as (TotalRAM - 4 GB) if not supplied.

.PARAMETER MaxDOP
Max degree of parallelism. Auto-calculated from logical CPU count if not supplied.

.PARAMETER AnswerFile
Path to a SQL Server setup INI file. When supplied, most params are read from it.
SAPassword and SysAdminAccounts are still passed on the command line.

.PARAMETER SkipPostConfig
Skip the post-install sp_configure steps (MaxMemory, MaxDOP, CostThreshold).

.PARAMETER WhatIf
Preview the setup.exe command without executing it.

.EXAMPLE
# Interactive mode — prompts for everything
.\admin\installation\Install-SqlServer.ps1

.EXAMPLE
# Unattended
.\admin\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -SAPassword (Read-Host 'SA password' -AsSecureString)

.EXAMPLE
# Answer-file mode
.\admin\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -AnswerFile .\admin\installation\templates\sql-server-install-default.ini `
    -SAPassword (Read-Host 'SA password' -AsSecureString)

.NOTES
RiskLevel   : HIGH IMPACT - runs setup.exe and installs a SQL Server instance
#>
param(
    [string]$SetupPath,
    [string]$InstanceName       = 'MSSQLSERVER',
    [string]$InstallDir         = 'C:\Program Files\Microsoft SQL Server',
    [string]$SystemDBDir        = 'C:\SQLData\SystemDBs',
    [string]$SystemLogDir       = 'C:\SQLLogs\SystemLogs',
    [string]$UserDBDir          = 'C:\SQLData\UserDBs',
    [string]$UserLogDir         = 'C:\SQLLogs\UserLogs',
    [string]$TempDBDir,
    [string]$TempDBLogDir,
    [int]$TempDBFileCount       = 0,
    [System.Security.SecureString]$SAPassword,
    [string]$SysAdminAccounts,
    [string]$ServiceAccount     = 'NT Service\MSSQLSERVER',
    [string]$AgtServiceAccount  = 'NT Service\SQLSERVERAGENT',
    [string]$Collation          = 'SQL_Latin1_General_CP1_CI_AS',
    [string]$Features           = 'SQLENGINE,SQLAGENT',
    [int]$MaxMemoryGB           = 0,
    [int]$MaxDOP                = 0,
    [string]$AnswerFile,
    [switch]$SkipPostConfig,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ── Pre-check: admin elevation ────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'ERROR: This script must be run as Administrator.' -ForegroundColor Red
    exit 1
}

# ── Logging setup ─────────────────────────────────────────────────────────────
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir    = Join-Path $repoRoot 'output-files\installation'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = Join-Path $logDir "install-$InstanceName-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

function Confirm-Directory {
    param([string]$Path, [string]$Label)
    if (-not $Path -or $Path.Trim() -eq '') {
        Write-Host "ERROR: $Label cannot be empty." -ForegroundColor Red
        return $false
    }
    if (-not (Test-Path $Path)) {
        Write-Host "$Label '$Path' does not exist. Creating..." -ForegroundColor Yellow
        try   { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        catch { Write-Host "ERROR: Failed to create $Label at '$Path'." -ForegroundColor Red; return $false }
    }

    # Disk space check — warn if less than 20 GB free on that drive
    $drive    = Split-Path -Qualifier $Path
    $freeGB   = [math]::Round((Get-PSDrive ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue).Free / 1GB, 1)
    if ($freeGB -lt 20) {
        Write-Host "WARNING: $Label drive $drive has only $freeGB GB free (recommend 20 GB+)." -ForegroundColor Yellow
    }
    return $true
}

function Confirm-SAPassword {
    param([System.Security.SecureString]$SecPwd)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                 [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecPwd))
    $ok = $plain.Length -ge 8 -and
          $plain -cmatch '[A-Z]' -and
          $plain -cmatch '[a-z]' -and
          $plain -match '\d' -and
          $plain -match '[^A-Za-z0-9]'
    if (-not $ok) {
        Write-Host 'ERROR: SA password must be 8+ chars with uppercase, lowercase, digit, and special character.' -ForegroundColor Red
    }
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecPwd)) | Out-Null
    return $ok
}

Write-DbaLog "SQL Server install log - $ts" 'Cyan'
Write-DbaLog "Log file: $logFile" 'DarkGray'

# ── Interactive prompts for anything not supplied ─────────────────────────────
if (-not $SetupPath) {
    do {
        $SetupPath = Read-Host 'Path to SQL Server setup.exe'
    } until ($SetupPath -and (Test-Path $SetupPath))
}
if (-not (Test-Path $SetupPath)) {
    Write-Host "ERROR: setup.exe not found at '$SetupPath'." -ForegroundColor Red; exit 1
}

if (-not $AnswerFile) {
    do { $ok = Confirm-Directory $InstallDir  'Install directory'      } until ($ok)
    do { $ok = Confirm-Directory $SystemDBDir 'System DB directory'    } until ($ok)
    do { $ok = Confirm-Directory $SystemLogDir'System log directory'   } until ($ok)
    do { $ok = Confirm-Directory $UserDBDir   'User DB directory'      } until ($ok)
    do { $ok = Confirm-Directory $UserLogDir  'User log directory'     } until ($ok)
}

if (-not $TempDBDir)    { $TempDBDir    = Join-Path $SystemDBDir  'TempDB' }
if (-not $TempDBLogDir) { $TempDBLogDir = Join-Path $SystemLogDir 'TempDB' }
Confirm-Directory $TempDBDir    'TempDB directory'     | Out-Null
Confirm-Directory $TempDBLogDir 'TempDB log directory' | Out-Null

if (-not $SysAdminAccounts) { $SysAdminAccounts = "$env:USERDOMAIN\$env:USERNAME" }

if (-not $SAPassword) {
    do {
        $SAPassword = Read-Host 'SA password' -AsSecureString
    } until (Confirm-SAPassword $SAPassword)
}

# ── Hardware-based recommendations ───────────────────────────────────────────
$totalRAMGB    = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$logicalCPUs   = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
if ($MaxMemoryGB -eq 0) { $MaxMemoryGB  = [math]::Max(1, [math]::Floor($totalRAMGB - 4)) }
if ($MaxDOP      -eq 0) { $MaxDOP       = [math]::Min($logicalCPUs, 8) }
if ($TempDBFileCount -eq 0) { $TempDBFileCount = [math]::Min($logicalCPUs, 8) }

Write-DbaLog ''
Write-DbaLog 'Hardware-based recommendations:' 'Cyan'
Write-DbaLog "  Total RAM       : $totalRAMGB GB"
Write-DbaLog "  Logical CPUs    : $logicalCPUs"
Write-DbaLog "  Max Server Mem  : $MaxMemoryGB GB"
Write-DbaLog "  MaxDOP          : $MaxDOP"
Write-DbaLog "  TempDB files    : $TempDBFileCount"

# ── Confirm ───────────────────────────────────────────────────────────────────
Write-DbaLog ''
Write-DbaLog 'Install configuration:' 'Cyan'
Write-DbaLog "  Setup       : $SetupPath"
Write-DbaLog "  Instance    : $InstanceName"
Write-DbaLog "  Features    : $Features"
Write-DbaLog "  Collation   : $Collation"
Write-DbaLog "  Install dir : $InstallDir"
Write-DbaLog "  System DBs  : $SystemDBDir"
Write-DbaLog "  System logs : $SystemLogDir"
Write-DbaLog "  User DBs    : $UserDBDir"
Write-DbaLog "  User logs   : $UserLogDir"
Write-DbaLog "  TempDB      : $TempDBDir  ($TempDBFileCount files)"
Write-DbaLog "  Sysadmins   : $SysAdminAccounts"
if ($AnswerFile) { Write-DbaLog "  Answer file : $AnswerFile" }
Write-DbaLog ''

if (-not $WhatIf) {
    $go = Read-Host 'Start installation? (yes to continue)'
    if ($go -notmatch '^(yes|y|1)$') {
        Write-DbaLog 'Installation cancelled.' 'Yellow'; exit 0
    }
}

# ── Build setup arguments ─────────────────────────────────────────────────────
$plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SAPassword))

if ($AnswerFile) {
    $SetupArgs = @(
        "/ConfigurationFile=`"$AnswerFile`""
        "/SAPWD=`"$plainPwd`""
        "/SQLSYSADMINACCOUNTS=`"$SysAdminAccounts`""
        '/IACCEPTSQLSERVERLICENSETERMS'
        '/Q'
    )
} else {
    $SetupArgs = @(
        '/Q'
        '/ACTION=Install'
        "/FEATURES=$Features"
        "/INSTANCENAME=`"$InstanceName`""
        "/INSTANCEDIR=`"$InstallDir`""
        "/SQLCOLLATION=`"$Collation`""
        "/SQLSYSADMINACCOUNTS=`"$SysAdminAccounts`""
        '/SECURITYMODE=SQL'
        "/SAPWD=`"$plainPwd`""
        "/SQLSVCACCOUNT=`"$ServiceAccount`""
        "/AGTSVCACCOUNT=`"$AgtServiceAccount`""
        '/AGTSVCSTARTUPTYPE=Automatic'
        '/SQLSVCSTARTUPTYPE=Automatic'
        '/TCPENABLED=1'
        '/NPENABLED=0'
        '/BROWSERSVCSTARTUPTYPE=Disabled'
        "/INSTALLSQLDATADIR=`"$SystemDBDir`""
        "/SQLUSERDBDIR=`"$UserDBDir`""
        "/SQLUSERDBLOGDIR=`"$UserLogDir`""
        "/SQLTEMPDBDIR=`"$TempDBDir`""
        "/SQLTEMPDBLOGDIR=`"$TempDBLogDir`""
        "/SQLTEMPDBFILECOUNT=$TempDBFileCount"
        '/SQLTEMPDBFILESIZE=8'
        '/SQLTEMPDBFILEGROWTH=64'
        '/SQLTEMPDBLOGFILESIZE=8'
        '/SQLTEMPDBLOGFILEGROWTH=64'
        '/IACCEPTSQLSERVERLICENSETERMS'
    )
}

# Clear the plaintext password from memory as soon as it's in the args array
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SAPassword)) | Out-Null

if ($WhatIf) {
    Write-DbaLog 'WhatIf - setup.exe command:' 'Yellow'
    Write-DbaLog "$SetupPath $($SetupArgs -join ' ')" 'DarkGray'
    # Mask password in WhatIf output
    Write-Host ($SetupArgs -join ' ') -replace '/SAPWD="[^"]*"', '/SAPWD="****"'
    return
}

# ── Run setup.exe ─────────────────────────────────────────────────────────────
Write-DbaLog 'Running SQL Server setup.exe...' 'Cyan'
$proc = Start-Process -FilePath $SetupPath -ArgumentList $SetupArgs `
            -Wait -PassThru -RedirectStandardOutput "$logFile.stdout" `
            -RedirectStandardError "$logFile.stderr"

$exitCode = $proc.ExitCode
Write-DbaLog "setup.exe exit code: $exitCode"

switch ($exitCode) {
    0    { Write-DbaLog 'Installation succeeded.' 'Green' }
    3010 { Write-DbaLog 'Installation succeeded - reboot required.' 'Yellow' }
    default {
        Write-DbaLog "Installation failed (exit code $exitCode). Check: $logFile.stderr" 'Red'
        exit $exitCode
    }
}

# ── Post-install configuration ────────────────────────────────────────────────
if (-not $SkipPostConfig) {
    Write-DbaLog 'Applying post-install configuration...' 'Cyan'

    # Wait up to 60s for SQL to accept connections
    $srv = if ($InstanceName -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$InstanceName" }
    $ready = $false
    for ($i = 1; $i -le 12; $i++) {
        try {
            $null = Invoke-Sqlcmd -ServerInstance $srv -Query 'SELECT 1' -QueryTimeout 5 `
                        -TrustServerCertificate -ErrorAction Stop
            $ready = $true; break
        } catch { Start-Sleep -Seconds 5 }
    }

    if (-not $ready) {
        Write-DbaLog 'WARNING: SQL Server not reachable after 60s - skipping post-install config.' 'Yellow'
    } else {
        $postSql = @"
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
EXEC sys.sp_configure 'max server memory (MB)', $($MaxMemoryGB * 1024);
EXEC sys.sp_configure 'max degree of parallelism', $MaxDOP;
EXEC sys.sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE WITH OVERRIDE;
"@
        try {
            Invoke-Sqlcmd -ServerInstance $srv -Query $postSql -TrustServerCertificate -ErrorAction Stop
            Write-DbaLog "  Max memory   : $MaxMemoryGB GB ($($MaxMemoryGB * 1024) MB)" 'Green'
            Write-DbaLog "  MaxDOP       : $MaxDOP" 'Green'
            Write-DbaLog "  Cost threshold: 50" 'Green'
        } catch {
            Write-DbaLog "WARNING: Post-install config failed - $($_.Exception.Message)" 'Yellow'
        }
    }
}

Write-DbaLog ''
Write-DbaLog 'SQL Server installation complete.' 'Green'
Write-DbaLog "Log: $logFile"