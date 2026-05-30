<#
.SYNOPSIS
Reads a health-check output folder and surfaces flagged findings with severity ratings.

.NOTES
ScriptType   : PowerShell-only
TargetScope  : output-files (offline review)
RiskLevel    : SAFE
Purpose      : Turn raw CSV collection output into an actionable findings list.

.DESCRIPTION
Reads the CSV files produced by Invoke-HealthCheckCollection.ps1 and applies threshold rules
to surface issues. Each finding is rated CRITICAL, WARNING, or INFO.

Rules applied:
  CRITICAL  - database not ONLINE
  CRITICAL  - database with no full backup ever
  CRITICAL  - suspect pages recorded in msdb.dbo.suspect_pages
  CRITICAL  - sa login is enabled
  WARNING   - full backup older than 25 hours
  WARNING   - log backup older than 4 hours for FULL recovery databases
  WARNING   - transaction log > 80% used
  WARNING   - auto_shrink enabled on any database
  WARNING   - SQL Agent job failures in the last 7 days
  WARNING   - percent-based autogrowth configured on any file
  WARNING   - DBCC CHECKDB not run in over 7 days
  WARNING   - DBCC CHECKDB never recorded for a database
  WARNING   - read or write I/O latency > 50 ms
  WARNING   - SQL login with password policy or expiration disabled
  WARNING   - max server memory left at SQL Server default (unconfigured)
  WARNING   - data files with less than 10% free space
  WARNING   - specific wait types indicating I/O, log, or memory pressure
  INFO      - sessions with active blocking
  INFO      - sessions with open transactions
  INFO      - error log entries present (requires manual review)

.PARAMETER FolderPath
Path to the healthcheck output folder. If omitted, the most recent folder under
output-files\healthcheck is used.

.PARAMETER OutputFormat
'Table' (default) prints to console. 'Csv' writes findings to a CSV in the same folder.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath ".\output-files\healthcheck\.-20260529-185000"

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1 -OutputFormat Csv
#>

param(
    [string]$FolderPath,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

if (-not $FolderPath) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    if (-not (Test-Path -LiteralPath $hcRoot)) {
        throw "No FolderPath specified and no output-files\healthcheck directory found. Run Invoke-HealthCheckCollection.ps1 first."
    }
    $latest = Get-ChildItem -LiteralPath $hcRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) {
        throw "No healthcheck folders found under $hcRoot. Run Invoke-HealthCheckCollection.ps1 first."
    }
    $FolderPath = $latest.FullName
    Write-Host "No FolderPath specified — using most recent: $FolderPath" -ForegroundColor Yellow
}

if (-not (Test-Path -LiteralPath $FolderPath)) {
    throw "Folder not found: $FolderPath"
}

$findings = [System.Collections.Generic.List[PSObject]]::new()

function Add-Finding {
    param(
        [string]$Severity,
        [string]$Category,
        [string]$Subject,
        [string]$Detail
    )
    $findings.Add([PSCustomObject]@{
        Severity = $Severity
        Category = $Category
        Subject  = $Subject
        Detail   = $Detail
    })
}

function Read-Csv-Safe {
    param([string]$Name)
    $path = Join-Path $FolderPath "$Name.csv"
    if (Test-Path -LiteralPath $path) {
        return @(Import-Csv -LiteralPath $path -ErrorAction SilentlyContinue)
    }
    return @()
}

# ── database-health ──────────────────────────────────────────────────────────
$dbHealth = Read-Csv-Safe 'database-health'
foreach ($row in $dbHealth) {
    if ($row.state_desc -and $row.state_desc -ne 'ONLINE') {
        Add-Finding 'CRITICAL' 'Database State' $row.database_name (
            "Database is $($row.state_desc)")
    }
    if ($row.is_auto_shrink_on -in @('True', '1', 'YES')) {
        Add-Finding 'WARNING' 'Auto-Shrink' $row.database_name (
            'AUTO_SHRINK is enabled — causes fragmentation and random I/O spikes')
    }
    if ($row.is_auto_close_on -in @('True', '1', 'YES')) {
        Add-Finding 'WARNING' 'Auto-Close' $row.database_name (
            'AUTO_CLOSE is enabled — causes overhead on every new connection')
    }
}

# ── backup-times ─────────────────────────────────────────────────────────────
$backups = Read-Csv-Safe 'backup-times'
foreach ($row in $backups) {
    $dbName = $row.database_name

    if (-not $row.last_full_backup -or $row.last_full_backup -eq '') {
        Add-Finding 'CRITICAL' 'Backup' $dbName 'No full backup on record'
    }
    elseif ([double]::TryParse($row.full_backup_age_hours, [ref]$null)) {
        $ageH = [double]$row.full_backup_age_hours
        if ($ageH -gt 25) {
            Add-Finding 'WARNING' 'Backup' $dbName (
                "Full backup is $([Math]::Round($ageH, 1)) hours old (threshold: 25h)")
        }
    }

    $recovery = $row.recovery_model_desc
    if ($recovery -eq 'FULL' -or $recovery -eq 'BULK_LOGGED') {
        if (-not $row.last_log_backup -or $row.last_log_backup -eq '') {
            Add-Finding 'WARNING' 'Backup' $dbName (
                "$recovery recovery model but no log backup on record — log will grow unbounded")
        }
        elseif ([double]::TryParse($row.log_backup_age_hours, [ref]$null)) {
            $logAgeH = [double]$row.log_backup_age_hours
            if ($logAgeH -gt 4) {
                Add-Finding 'WARNING' 'Backup' $dbName (
                    "Log backup is $([Math]::Round($logAgeH, 1)) hours old (threshold: 4h, $recovery recovery)")
            }
        }
    }
}

# ── tlog-usage ───────────────────────────────────────────────────────────────
$tlogs = Read-Csv-Safe 'tlog-usage'
foreach ($row in $tlogs) {
    $pct = 0.0
    # Column is log_used_pct in updated script; fall back to log_used_percent for older CSVs
    $pctCol = if ($row.PSObject.Properties['log_used_pct']) { $row.log_used_pct } else { $row.log_used_percent }
    if ([double]::TryParse($pctCol, [ref]$pct) -and $pct -gt 80) {
        Add-Finding 'WARNING' 'Transaction Log' $row.database_name (
            "Log is $pct% used ($($row.log_used_mb) MB of $($row.log_size_mb) MB) — risk of log-full")
    }
}

# ── database-files (autogrowth) ───────────────────────────────────────────────
$dbFiles = Read-Csv-Safe 'database-files'
foreach ($row in $dbFiles) {
    if ($row.growth_is_percent -in @('True', '1', 'YES', 'true')) {
        Add-Finding 'WARNING' 'Autogrowth' "$($row.database_name) / $($row.logical_name)" (
            "Percent-based autogrowth ($($row.auto_growth)) on $($row.file_type) file — can cause large unpredictable growths on large databases")
    }
}

# ── job-failures ─────────────────────────────────────────────────────────────
$jobs = Read-Csv-Safe 'job-failures'
$failedJobs = $jobs | Select-Object -ExpandProperty job_name -Unique
foreach ($jName in $failedJobs) {
    $count = @($jobs | Where-Object job_name -eq $jName).Count
    Add-Finding 'WARNING' 'SQL Agent' $jName (
        "$count failure(s) in the last 7 days")
}

# ── active-sessions (blocking) ────────────────────────────────────────────────
$sessions = Read-Csv-Safe 'active-sessions'
$blocked  = @($sessions | Where-Object {
    $v = $_.blocking_session_id
    $n = 0
    $v -and $v -ne '' -and [int]::TryParse($v, [ref]$n) -and $n -gt 0
})
if ($blocked.Count -gt 0) {
    $blockedList = ($blocked | Select-Object -ExpandProperty session_id) -join ', '
    Add-Finding 'INFO' 'Blocking' 'Active sessions' (
        "$($blocked.Count) session(s) currently blocked: session_id(s) $blockedList")
}

$openTx = @($sessions | Where-Object {
    $n = 0
    [int]::TryParse($_.open_transaction_count, [ref]$n) -and $n -gt 0
})
if ($openTx.Count -gt 0) {
    Add-Finding 'INFO' 'Open Transactions' 'Active sessions' (
        "$($openTx.Count) session(s) with open transactions")
}

# ── recent-errors ─────────────────────────────────────────────────────────────
$errors = Read-Csv-Safe 'recent-errors'
if ($errors.Count -gt 0) {
    Add-Finding 'INFO' 'Error Log' 'SQL Server error log' (
        "$($errors.Count) non-routine entry/entries in last 24h — review recent-errors.csv")
}

# ── dbcc-checkdb ──────────────────────────────────────────────────────────────
$checkdb = Read-Csv-Safe 'dbcc-checkdb'
foreach ($row in $checkdb) {
    if (-not $row.last_good_checkdb -or $row.last_good_checkdb -eq '') {
        Add-Finding 'WARNING' 'DBCC CHECKDB' $row.database_name (
            'No CHECKDB on record for this database on this instance')
    }
    elseif ([int]::TryParse($row.days_since_checkdb, [ref]$null)) {
        $days = [int]$row.days_since_checkdb
        if ($days -gt 7) {
            Add-Finding 'WARNING' 'DBCC CHECKDB' $row.database_name (
                "Last good CHECKDB was $days days ago (threshold: 7 days)")
        }
    }
}

# ── suspect-pages ─────────────────────────────────────────────────────────────
$suspects = Read-Csv-Safe 'suspect-pages'
$activeSuspects = @($suspects | Where-Object {
    $_.event_type -notmatch 'Restored|Repaired|Deallocated'
})
if ($activeSuspects.Count -gt 0) {
    $dbNames = ($activeSuspects | Select-Object -ExpandProperty database_name -Unique) -join ', '
    Add-Finding 'CRITICAL' 'Suspect Pages' 'msdb.dbo.suspect_pages' (
        "$($activeSuspects.Count) active suspect page(s) — run DBCC CHECKDB immediately. Databases: $dbNames")
}

# ── io-usage (latency) ────────────────────────────────────────────────────────
$ioStats = Read-Csv-Safe 'io-usage'
foreach ($row in $ioStats) {
    $readLat  = 0.0
    $writeLat = 0.0
    [double]::TryParse($row.read_latency_ms,  [ref]$readLat)  | Out-Null
    [double]::TryParse($row.write_latency_ms, [ref]$writeLat) | Out-Null
    if ($readLat -gt 50) {
        Add-Finding 'WARNING' 'I/O Latency' $row.database_name (
            "Read latency is $([Math]::Round($readLat, 1)) ms (threshold: 50ms) — check disk subsystem")
    }
    if ($writeLat -gt 50) {
        Add-Finding 'WARNING' 'I/O Latency' $row.database_name (
            "Write latency is $([Math]::Round($writeLat, 1)) ms (threshold: 50ms) — check disk subsystem")
    }
}

# ── weak-logins (security) ────────────────────────────────────────────────────
$logins = Read-Csv-Safe 'weak-logins'
foreach ($login in $logins) {
    if (-not $login.risk_flag -or $login.risk_flag -eq 'OK') { continue }
    $sev = if ($login.risk_flag -eq 'SA_ENABLED') { 'CRITICAL' } else { 'WARNING' }
    Add-Finding $sev 'Security' $login.login_name (
        "Login risk flag: $($login.risk_flag)")
}

# ── wait-stats (pressure patterns) ───────────────────────────────────────────
$waits = Read-Csv-Safe 'wait-stats'
$concernWaits = @{
    'PAGEIOLATCH_SH'     = 'Data file read I/O bottleneck — disk reads are slow'
    'PAGEIOLATCH_EX'     = 'Data file write I/O bottleneck — disk writes are slow'
    'WRITELOG'           = 'Transaction log write bottleneck — check log disk or sync-commit AG'
    'RESOURCE_SEMAPHORE' = 'Memory grant pressure — queries queuing for execution memory'
    'CXPACKET'           = 'Parallelism waits — review MAXDOP and cost threshold for parallelism'
    'CXCONSUMER'         = 'Parallelism waits — review MAXDOP and cost threshold for parallelism'
    'LCK_M_X'            = 'Exclusive lock waits — blocking or high write concurrency'
    'ASYNC_NETWORK_IO'   = 'Client network waits — application not consuming results fast enough'
}
foreach ($row in $waits) {
    if ($concernWaits.ContainsKey($row.wait_type)) {
        $pct = 0.0
        if ([double]::TryParse($row.pct_total_wait, [ref]$pct) -and $pct -gt 10) {
            Add-Finding 'WARNING' 'Wait Statistics' $row.wait_type (
                "$([Math]::Round($pct,1))% of total wait time — $($concernWaits[$row.wait_type])")
        }
    }
}

# ── memory-config (unconfigured max server memory) ───────────────────────────
$memConfig = Read-Csv-Safe 'memory-config'
foreach ($row in $memConfig) {
    $maxMem = 0L
    if ([long]::TryParse($row.max_server_memory_mb, [ref]$maxMem) -and $maxMem -ge 2147483647) {
        Add-Finding 'WARNING' 'Memory Config' 'max server memory' (
            'max server memory is at the SQL Server default (2,147,483,647 MB = uncapped) — SQL Server may consume all available RAM')
    }
}

# ── database-sizes (low free space) ──────────────────────────────────────────
$dbSizes = Read-Csv-Safe 'database-sizes'
foreach ($row in $dbSizes) {
    $freePct = 0.0
    if ([double]::TryParse($row.data_free_pct, [ref]$freePct) -and $freePct -lt 10) {
        Add-Finding 'WARNING' 'Disk Space' $row.database_name (
            "Data files $freePct% free ($($row.data_free_mb) MB free of $($row.data_size_mb) MB) — autogrowth risk")
    }
}

# ── Output ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  DBA Health Check Review' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Folder    : $FolderPath"
$folderLeaf = Split-Path -Leaf $FolderPath
if ($folderLeaf -match '(\d{8}-\d{6})$') {
    $collectedAt = [DateTime]::ParseExact($Matches[1], 'yyyyMMdd-HHmmss', $null)
    Write-Host "  Collected : $($collectedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
}
Write-Host "  Reviewed  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'

if ($findings.Count -eq 0) {
    Write-Host ''
    Write-Host '  No findings. All checked thresholds look healthy.' -ForegroundColor Green
    Write-Host ''
}
else {
    $order = @{ CRITICAL = 0; WARNING = 1; INFO = 2 }
    $sorted = $findings | Sort-Object { $order[$_.Severity] }, Category, Subject

    Write-Host ''
    foreach ($f in $sorted) {
        $color = switch ($f.Severity) {
            'CRITICAL' { 'Red' }
            'WARNING'  { 'Yellow' }
            default    { 'Cyan' }
        }
        Write-Host ("  [{0,-8}] {1,-22} {2}" -f $f.Severity, $f.Category, $f.Subject) -ForegroundColor $color
        Write-Host ("             {0}" -f $f.Detail) -ForegroundColor DarkGray
        Write-Host ''
    }

    $critCount = @($findings | Where-Object Severity -eq 'CRITICAL').Count
    $warnCount = @($findings | Where-Object Severity -eq 'WARNING').Count
    $infoCount = @($findings | Where-Object Severity -eq 'INFO').Count
    Write-Host '--------------------------------------------'
    Write-Host ("  CRITICAL: {0}  |  WARNING: {1}  |  INFO: {2}" -f $critCount, $warnCount, $infoCount) -ForegroundColor Cyan
    Write-Host ''

    $csvOut = Join-Path $FolderPath 'findings.csv'
    $sorted | Export-Csv -LiteralPath $csvOut -NoTypeInformation -Encoding UTF8
}

$uiUp = $false
try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch {}
$folderEnc   = [Uri]::EscapeDataString($FolderPath)
$dashboardUrl = "http://localhost:8787/review?folder=$folderEnc"

Write-Host ('─' * 64) -ForegroundColor DarkCyan
if ($findings.Count -gt 0) {
    Write-Host "  Findings : $(Join-Path $FolderPath 'findings.csv')" -ForegroundColor Green
}
if ($uiUp) {
    Write-Host "  Dashboard: $dashboardUrl" -ForegroundColor Cyan
} else {
    Write-Host "  Dashboard: $dashboardUrl" -ForegroundColor DarkGray
    Write-Host "             (web UI not running — start with: .\tools\Start-WebUi.ps1)" -ForegroundColor DarkGray
}
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''
