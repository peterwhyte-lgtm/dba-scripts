<#
.SYNOPSIS
Uninstall a SQL Server instance with optional data directory cleanup.

.DESCRIPTION
Detects installed SQL Server instances, confirms the target, and runs setup.exe
/ACTION=Uninstall. Optionally removes data directories after uninstall.
All steps require explicit confirmation.

.PARAMETER SetupPath
Full path to SQL Server setup.exe for the version being removed.

.PARAMETER InstanceName
Instance to remove. If not specified, lists available instances and prompts.

.PARAMETER RemoveDataDirs
Also delete data and log directories after uninstall. Prompts for each path.

.PARAMETER WhatIf
Show what would run without executing.

.EXAMPLE
.\admin\installation\uninstall-sql.ps1 -SetupPath D:\SQL2022\setup.exe
.\admin\installation\uninstall-sql.ps1 -SetupPath D:\SQL2022\setup.exe -InstanceName SQL2022 -RemoveDataDirs
#>
param(
    [string]$SetupPath,
    [string]$InstanceName,
    [switch]$RemoveDataDirs,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'ERROR: This script must be run as Administrator.' -ForegroundColor Red; exit 1
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir   = Join-Path $repoRoot 'output-files\installation'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "uninstall-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-DbaLog "SQL Server uninstall log — $ts" 'Cyan'

# ── Detect installed instances ────────────────────────────────────────────────
$regPath   = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
$instances = @()
if (Test-Path $regPath) {
    $instances = Get-ItemProperty $regPath |
        Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name
}

if ($instances.Count -eq 0) {
    Write-DbaLog 'No SQL Server instances found on this machine.' 'Yellow'; exit 0
}

Write-DbaLog 'Installed instances:' 'Cyan'
$instances | ForEach-Object { Write-DbaLog "  $_" }

if (-not $InstanceName) {
    $InstanceName = Read-Host "Instance to remove ($(($instances -join ', ')))"
}
if ($instances -notcontains $InstanceName) {
    Write-DbaLog "ERROR: Instance '$InstanceName' not found." 'Red'; exit 1
}

# ── Setup path ────────────────────────────────────────────────────────────────
if (-not $SetupPath) {
    do {
        $SetupPath = Read-Host 'Path to SQL Server setup.exe for this version'
    } until ($SetupPath -and (Test-Path $SetupPath))
}
if (-not (Test-Path $SetupPath)) {
    Write-DbaLog "ERROR: setup.exe not found at '$SetupPath'." 'Red'; exit 1
}

# ── Collect data dirs before uninstall ───────────────────────────────────────
$dataDirs = @()
if ($RemoveDataDirs) {
    $regBase = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
    $instKey = Get-ItemProperty "$regBase\Instance Names\SQL" -ErrorAction SilentlyContinue
    $instId  = $instKey.$InstanceName

    if ($instId) {
        $setupKey = Get-ItemProperty "$regBase\$instId\Setup" -ErrorAction SilentlyContinue
        @('SQLDataRoot','SQLBinRoot','SQLUserDBDir','SQLUserDBLogDir','SQLTempDBDir','SQLTempDBLogDir') |
            ForEach-Object {
                $val = $setupKey.$_
                if ($val -and (Test-Path $val)) { $dataDirs += $val }
            }
        $dataDirs = $dataDirs | Sort-Object -Unique
    }
    if ($dataDirs.Count -gt 0) {
        Write-DbaLog 'Data directories that will be deleted:' 'Yellow'
        $dataDirs | ForEach-Object { Write-DbaLog "  $_" 'Yellow' }
    }
}

# ── Confirm ───────────────────────────────────────────────────────────────────
Write-DbaLog ''
Write-DbaLog "TARGET  : $InstanceName" 'Red'
Write-DbaLog "SETUP   : $SetupPath" 'Red'
if ($RemoveDataDirs -and $dataDirs.Count -gt 0) {
    Write-DbaLog "DATA DIRS WILL BE DELETED AFTER UNINSTALL" 'Red'
}
Write-DbaLog ''
Write-DbaLog 'WARNING: This is IRREVERSIBLE. Ensure you have backups of all databases.' 'Red'
Write-DbaLog ''

if ($WhatIf) {
    Write-DbaLog 'WhatIf — no changes made.' 'Yellow'; return
}

$confirm = Read-Host "Type the instance name '$InstanceName' to confirm uninstall"
if ($confirm -ne $InstanceName) {
    Write-DbaLog 'Confirmation did not match. Uninstall cancelled.' 'Yellow'; exit 0
}

# ── Run uninstall ─────────────────────────────────────────────────────────────
$uninstallArgs = @('/Q', '/ACTION=Uninstall', "/INSTANCENAME=$InstanceName", '/IACCEPTSQLSERVERLICENSETERMS')

Write-DbaLog 'Running SQL Server setup.exe /ACTION=Uninstall...' 'Cyan'
$proc = Start-Process -FilePath $SetupPath -ArgumentList $uninstallArgs `
            -Wait -PassThru `
            -RedirectStandardOutput "$logFile.stdout" `
            -RedirectStandardError  "$logFile.stderr"

$exitCode = $proc.ExitCode
Write-DbaLog "Exit code: $exitCode"

switch ($exitCode) {
    0    { Write-DbaLog 'Uninstall succeeded.' 'Green' }
    3010 { Write-DbaLog 'Uninstall succeeded — reboot required.' 'Yellow' }
    default {
        Write-DbaLog "Uninstall may have failed (exit $exitCode). Review: $logFile.stderr" 'Red'
        exit $exitCode
    }
}

# ── Optional data directory cleanup ──────────────────────────────────────────
if ($RemoveDataDirs -and $dataDirs.Count -gt 0) {
    Write-DbaLog ''
    Write-DbaLog 'Removing data directories...' 'Yellow'
    foreach ($dir in $dataDirs) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir -Recurse -Force
                Write-DbaLog "  Removed: $dir" 'Green'
            } catch {
                Write-DbaLog "  Failed to remove $dir — $($_.Exception.Message)" 'Red'
            }
        }
    }
}

Write-DbaLog ''
Write-DbaLog 'Uninstall complete.' 'Green'
Write-DbaLog "Log: $logFile"