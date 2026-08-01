<#
.SYNOPSIS
Apply sp_configure settings to an existing SQL Server instance.

.DESCRIPTION
Applies recommended or custom SQL Server configuration settings.
Shows a before/after comparison for every setting changed.
All changes use RECONFIGURE WITH OVERRIDE and are logged.

.PARAMETER ServerInstance
Target SQL Server instance. Default: . (local default instance).

.PARAMETER MaxMemoryGB
Max server memory in GB. Auto-calculated as (TotalRAM - 4 GB) if not supplied.

.PARAMETER MaxDOP
Max degree of parallelism. Auto-calculated from logical CPU count if not supplied.

.PARAMETER CostThreshold
Cost threshold for parallelism. Default: 50.

.PARAMETER BackupCompression
Enable backup compression by default. 1=on, 0=off. Default: 1.

.PARAMETER OptimizeAdHoc
Optimize for ad hoc workloads (plan cache). 1=on, 0=off. Default: 1.

.PARAMETER RemoteAdminConnections
Enable Dedicated Admin Connection (DAC). 1=on, 0=off. Default: 1.

.PARAMETER ApplyRecommended
Apply all recommended settings using hardware auto-detection. Ignores individual params.

.EXAMPLE
# Apply all recommended settings to local instance
.\admin\installation\configure-sql.ps1 -ApplyRecommended

# Apply to remote instance with specific values
.\admin\installation\configure-sql.ps1 -ServerInstance PROD01 -MaxMemoryGB 28 -MaxDOP 4

# Review current settings without changing anything (use -WhatIf)
.\admin\installation\configure-sql.ps1 -ApplyRecommended -WhatIf
#>
param(
    [string]$ServerInstance         = '.',
    [int]$MaxMemoryGB               = 0,
    [int]$MaxDOP                    = 0,
    [int]$CostThreshold             = 50,
    [ValidateSet(0,1)][int]$BackupCompression      = 1,
    [ValidateSet(0,1)][int]$OptimizeAdHoc          = 1,
    [ValidateSet(0,1)][int]$RemoteAdminConnections = 1,
    [switch]$ApplyRecommended,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir   = Join-Path $repoRoot 'output-files\installation'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "configure-$($ServerInstance -replace '[\\/:*]','-')-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

# ── Hardware-based recommendations ───────────────────────────────────────────
if ($ApplyRecommended -or $MaxMemoryGB -eq 0 -or $MaxDOP -eq 0) {
    $totalRAMGB  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $logicalCPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    if ($MaxMemoryGB -eq 0) { $MaxMemoryGB = [math]::Max(1, [math]::Floor($totalRAMGB - 4)) }
    if ($MaxDOP -eq 0)      { $MaxDOP      = [math]::Min($logicalCPUs, 8) }
}

# Settings to apply: name → [sp_configure key, desired value, description]
$settings = [ordered]@{
    'max server memory (MB)'        = @{ Value = $MaxMemoryGB * 1024; Label = "Max server memory ($MaxMemoryGB GB)" }
    'max degree of parallelism'     = @{ Value = $MaxDOP;             Label = "MaxDOP ($MaxDOP)" }
    'cost threshold for parallelism'= @{ Value = $CostThreshold;      Label = "Cost threshold for parallelism ($CostThreshold)" }
    'backup compression default'    = @{ Value = $BackupCompression;   Label = "Backup compression ($(if ($BackupCompression) {'on'} else {'off'}))" }
    'optimize for ad hoc workloads' = @{ Value = $OptimizeAdHoc;       Label = "Optimize for ad hoc workloads ($(if ($OptimizeAdHoc) {'on'} else {'off'}))" }
    'remote admin connections'      = @{ Value = $RemoteAdminConnections; Label = "Remote admin connections / DAC ($(if ($RemoteAdminConnections) {'on'} else {'off'}))" }
}

Write-DbaLog "SQL Server configuration — $ServerInstance" 'Cyan'
Write-DbaLog "Log: $logFile" 'DarkGray'

# ── Read current settings ─────────────────────────────────────────────────────
$currentSql = "SELECT name, value_in_use FROM sys.configurations WHERE name IN ($( ($settings.Keys | ForEach-Object {"'$_'"}) -join ',' ))"
try {
    $current = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $currentSql `
                   -TrustServerCertificate -ErrorAction Stop
} catch {
    Write-DbaLog "ERROR: Cannot connect to $ServerInstance — $($_.Exception.Message)" 'Red'; exit 1
}

$currentMap = @{}
foreach ($row in $current) { $currentMap[$row.name] = $row.value_in_use }

# ── Show planned changes ──────────────────────────────────────────────────────
Write-DbaLog ''
Write-DbaLog 'Planned configuration changes:' 'Cyan'
Write-DbaLog ("{0,-42} {1,12}  →  {2}" -f 'Setting', 'Current', 'New') 'DarkGray'
Write-DbaLog ([string]::new('-', 72)) 'DarkGray'

$changed = @{}
foreach ($key in $settings.Keys) {
    $desired = $settings[$key].Value
    $current = if ($currentMap.ContainsKey($key)) { $currentMap[$key] } else { '?' }
    $isSame  = "$current" -eq "$desired"
    $color   = if ($isSame) {'DarkGray'} else {'White'}
    $note    = if ($isSame) {'(no change)'} else {''}
    Write-DbaLog ("{0,-42} {1,12}  →  {2}  {3}" -f $key, $current, $desired, $note) $color
    if (-not $isSame) { $changed[$key] = $settings[$key].Value }
}

if ($changed.Count -eq 0) {
    Write-DbaLog ''
    Write-DbaLog 'All settings already at desired values. Nothing to apply.' 'Green'
    return
}

if ($WhatIf) {
    Write-DbaLog ''
    Write-DbaLog "WhatIf: $($changed.Count) setting(s) would be applied." 'Yellow'
    return
}

# ── Apply ─────────────────────────────────────────────────────────────────────
Write-DbaLog ''
Write-DbaLog "Applying $($changed.Count) setting(s)..." 'Cyan'

$sql = "EXEC sys.sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE;`n"
foreach ($key in $changed.Keys) {
    $sql += "EXEC sys.sp_configure '$key', $($changed[$key]);`n"
}
$sql += "RECONFIGURE WITH OVERRIDE;"

try {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $sql `
        -TrustServerCertificate -QueryTimeout 30 -ErrorAction Stop
    Write-DbaLog 'Settings applied successfully.' 'Green'
} catch {
    Write-DbaLog "ERROR applying settings: $($_.Exception.Message)" 'Red'; exit 1
}

# ── Verify ────────────────────────────────────────────────────────────────────
$verify = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $currentSql `
              -TrustServerCertificate -ErrorAction SilentlyContinue
$verifyMap = @{}
foreach ($row in $verify) { $verifyMap[$row.name] = $row.value_in_use }

Write-DbaLog ''
Write-DbaLog 'Verification:' 'Cyan'
foreach ($key in $changed.Keys) {
    $expected = $changed[$key]
    $actual   = $verifyMap[$key]
    $ok       = "$actual" -eq "$expected"
    $color    = if ($ok) {'Green'} else {'Red'}
    Write-DbaLog ("  {0,-42} {1}  {2}" -f $key, $actual, $(if ($ok) {'OK'} else {"MISMATCH (expected $expected)"})) $color
}

Write-DbaLog ''
Write-DbaLog 'Configuration complete.' 'Green'