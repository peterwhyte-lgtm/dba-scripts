<#
.SYNOPSIS
Apply a SQL Server Cumulative Update (CU) patch silently with pre/post version logging.

.DESCRIPTION
Detects all installed SQL Server instances, shows current versions, validates the
supplied CU installer, applies the patch, and verifies the new version.

The CU installer must be downloaded separately from:
  https://support.microsoft.com/en-us/help/321185 (SQL Server update list)
  https://www.microsoft.com/en-us/download/details.aspx?id=<KB>

.PARAMETER PatchPath
Full path to the CU installer exe (e.g. SQLServer2022-KB5046059-x64.exe).
Required — auto-download is intentionally not supported for production safety.

.PARAMETER InstanceName
Instance to patch. Default: patches ALL installed instances (/allinstances).
Specify a named instance to patch only that instance.

.PARAMETER WhatIf
Show patch details without running the installer.

.EXAMPLE
# Patch all instances
.\sql-operations\patches\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe

# Patch a single named instance
.\sql-operations\patches\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe `
    -InstanceName SQL2022
#>
param(
    [Parameter(Mandatory)]
    [string]$PatchPath,

    [string]$InstanceName,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ── Pre-check: admin elevation ────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'ERROR: This script must be run as Administrator.' -ForegroundColor Red; exit 1
}

# ── Logging ───────────────────────────────────────────────────────────────────
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir   = Join-Path $repoRoot 'output-files\patches'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "sql-patch-$ts.log"

function Write-Log {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-Log "SQL Server patch log — $ts" 'Cyan'

# ── Validate patch file ───────────────────────────────────────────────────────
if (-not (Test-Path $PatchPath)) {
    Write-Log "ERROR: Patch file not found: $PatchPath" 'Red'; exit 1
}
$patchFile = Get-Item $PatchPath
Write-Log "Patch file : $($patchFile.Name)"
Write-Log "Size       : $([math]::Round($patchFile.Length / 1MB, 1)) MB"

# ── Detect installed SQL Server instances ─────────────────────────────────────
$regPath   = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
$instances = @()
if (Test-Path $regPath) {
    $instances = Get-ItemProperty $regPath |
        Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name
}

if ($instances.Count -eq 0) {
    Write-Log 'ERROR: No SQL Server instances found on this machine.' 'Red'; exit 1
}

Write-Log ''
Write-Log 'Installed SQL Server instances:' 'Cyan'

$versionsBefore = @{}
foreach ($inst in $instances) {
    $srvConn = if ($inst -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$inst" }
    try {
        $row = Invoke-Sqlcmd -ServerInstance $srvConn `
                   -Query "SELECT @@VERSION AS v, SERVERPROPERTY('ProductVersion') AS pv" `
                   -QueryTimeout 10 -TrustServerCertificate -ErrorAction Stop
        $ver = $row.pv
        $versionsBefore[$inst] = $ver
        Write-Log "  $inst : $ver" 'White'
    } catch {
        Write-Log "  $inst : (could not connect — $($_.Exception.Message))" 'Yellow'
        $versionsBefore[$inst] = 'unknown'
    }
}

# ── Build patch arguments ─────────────────────────────────────────────────────
$patchArgs = @('/quiet', '/IAcceptSQLServerLicenseTerms')
if ($InstanceName) {
    $patchArgs += "/instancename=$InstanceName"
    Write-Log ''
    Write-Log "Target instance: $InstanceName" 'Cyan'
} else {
    $patchArgs += '/allinstances'
    Write-Log ''
    Write-Log 'Target: all instances (/allinstances)' 'Cyan'
}

if ($WhatIf) {
    Write-Log 'WhatIf — patch command:' 'Yellow'
    Write-Log "$PatchPath $($patchArgs -join ' ')" 'DarkGray'
    return
}

# ── Warn about active connections ─────────────────────────────────────────────
Write-Log ''
Write-Log 'WARNING: The patch installer will restart SQL Server services.' 'Yellow'
Write-Log 'Ensure no critical jobs or transactions are active.' 'Yellow'
Write-Log ''
$go = Read-Host 'Apply patch now? (yes to continue)'
if ($go -notmatch '^(yes|y|1)$') {
    Write-Log 'Patch cancelled.' 'Yellow'; exit 0
}

# ── Apply patch ───────────────────────────────────────────────────────────────
Write-Log 'Running patch installer...' 'Cyan'
$proc = Start-Process -FilePath $PatchPath -ArgumentList $patchArgs `
            -Wait -PassThru `
            -RedirectStandardOutput "$logFile.stdout" `
            -RedirectStandardError  "$logFile.stderr"

$exitCode = $proc.ExitCode
Write-Log "Installer exit code: $exitCode"

switch ($exitCode) {
    0    { Write-Log 'Patch applied successfully.' 'Green' }
    3010 { Write-Log 'Patch applied — reboot required.' 'Yellow' }
    default {
        Write-Log "Patch FAILED (exit code $exitCode). Review: $logFile.stderr" 'Red'
        exit $exitCode
    }
}

# ── Verify new versions ───────────────────────────────────────────────────────
Write-Log ''
Write-Log 'Verifying versions after patch:' 'Cyan'
Start-Sleep -Seconds 10

foreach ($inst in $instances) {
    $srvConn = if ($inst -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$inst" }
    $ready   = $false
    for ($i = 1; $i -le 12; $i++) {
        try {
            $row  = Invoke-Sqlcmd -ServerInstance $srvConn `
                        -Query "SELECT SERVERPROPERTY('ProductVersion') AS pv" `
                        -QueryTimeout 5 -TrustServerCertificate -ErrorAction Stop
            $verAfter = $row.pv
            $ready    = $true
            $before   = $versionsBefore[$inst]
            $changed  = $verAfter -ne $before
            $color    = if ($changed) { 'Green' } else { 'Yellow' }
            $note     = if ($changed) { 'updated' } else { 'unchanged' }
            Write-Log "  $inst : $before  →  $verAfter  ($note)" $color
            break
        } catch { Start-Sleep -Seconds 5 }
    }
    if (-not $ready) {
        Write-Log "  $inst : could not reconnect after patch — check manually." 'Yellow'
    }
}

Write-Log ''
Write-Log 'Patch complete.' 'Green'
Write-Log "Log: $logFile"
