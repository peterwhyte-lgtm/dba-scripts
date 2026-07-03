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
  CRITICAL  - full backup older than 24 hours
  WARNING   - log backup older than 4 hours for FULL recovery databases
  WARNING   - transaction log > 80% used
  WARNING   - auto_shrink enabled on any database
  WARNING   - SQL Agent job failures in the last 7 days
  WARNING   - percent-based autogrowth configured on any file
  CRITICAL  - DBCC CHECKDB never recorded or not run in over 14 days
  WARNING   - DBCC CHECKDB not run in over 7 days
  WARNING   - read or write I/O latency > 50 ms
  WARNING   - SQL login with password policy or expiration disabled
  WARNING   - max server memory left at SQL Server default (unconfigured)
  WARNING   - data files with less than 10% free space
  WARNING   - specific wait types indicating I/O, log, or memory pressure
  WARNING   - TempDB percent-based autogrowth, unequal file sizing, or low file count
  WARNING   - high ad-hoc single-use plan ratio in plan cache (> 60%)
  WARNING   - HIGH-risk linked server login mapping (stored credentials)
  INFO      - MEDIUM-risk linked server (impersonation mapping)
  CRITICAL  - VLF count > 1000 on any database log file
  WARNING   - VLF count > 200 on any database log file
  INFO      - VLF count > 50 on any database log file
  WARNING   - DBA maintenance job missing, failed, or disabled
  CRITICAL  - login account locked out due to failed login attempts
  CRITICAL  - login with repeated failures flagged as likely brute-force
  WARNING   - login with repeated failures in error log
  WARNING   - Query Store switched to READ_ONLY (storage full or error)
  INFO      - user Extended Events sessions running
  WARNING   - CDC or Change Tracking configuration warnings
  CRITICAL/WARNING - Service Broker queue or transmission issues
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

#>

param(
    [string]$FolderPath
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
        if ($ageH -gt 24) {
            Add-Finding 'CRITICAL' 'Backup' $dbName (
                "Full backup is $([Math]::Round($ageH, 1)) hours old (threshold: 24h)")
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
        Add-Finding 'CRITICAL' 'DBCC CHECKDB' $row.database_name (
            'No CHECKDB ever recorded — integrity of this database is unknown')
    }
    elseif ([int]::TryParse($row.days_since_checkdb, [ref]$null)) {
        $days = [int]$row.days_since_checkdb
        if ($days -gt 14) {
            Add-Finding 'CRITICAL' 'DBCC CHECKDB' $row.database_name (
                "CHECKDB overdue — $days days since last integrity check (run immediately)")
        } elseif ($days -gt 7) {
            Add-Finding 'WARNING' 'DBCC CHECKDB' $row.database_name (
                "CHECKDB stale — $days days since last integrity check (run soon)")
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

# ── tempdb-config ─────────────────────────────────────────────────────────────
$tempdbConfig = Read-Csv-Safe 'tempdb-config'
foreach ($row in $tempdbConfig) {
    if ($row.autogrowth_status -like 'WARN*') {
        Add-Finding 'WARNING' 'TempDB Config' "TempDB / $($row.logical_name)" (
            $row.autogrowth_status)
    }
    if ($row.sizing_status -like 'WARN*') {
        Add-Finding 'WARNING' 'TempDB Config' "TempDB sizing" (
            $row.sizing_status)
    }
    if ($row.file_count_status -like 'WARN*') {
        Add-Finding 'WARNING' 'TempDB Config' "TempDB file count" (
            $row.file_count_status)
    }
}

# ── plan-cache ────────────────────────────────────────────────────────────────
$planCache = Read-Csv-Safe 'plan-cache'
foreach ($row in $planCache) {
    if ($row.recommendation -like 'WARN*') {
        $pct = if ($row.single_use_pct) { "$($row.single_use_pct)% single-use" } else { '' }
        Add-Finding 'WARNING' 'Plan Cache' $row.plan_type (
            "$($row.recommendation) — $pct ($($row.single_use_mb) MB wasted)")
    }
}

# ── linked-server-security ────────────────────────────────────────────────────
$linkedSec = Read-Csv-Safe 'linked-server-security'
$seenLs = @{}
foreach ($row in $linkedSec) {
    $key = "$($row.linked_server)|$($row.local_login)"
    if ($seenLs.ContainsKey($key)) { continue }
    $seenLs[$key] = $true
    if ($row.risk_level -like 'HIGH*') {
        Add-Finding 'WARNING' 'Linked Server' $row.linked_server (
            "Risk: $($row.risk_level) — $($row.security_context)")
    }
    elseif ($row.risk_level -like 'MEDIUM*') {
        Add-Finding 'INFO' 'Linked Server' $row.linked_server (
            "Risk: $($row.risk_level) — $($row.security_context)")
    }
}

# ── vlf-count ─────────────────────────────────────────────────────────────────
$vlfData = Read-Csv-Safe 'vlf-count'
foreach ($row in $vlfData) {
    if ($row.status -eq 'CRITICAL') {
        Add-Finding 'CRITICAL' 'VLF Count' $row.database_name (
            "VLF count $($row.vlf_count) is severe (>1000). Shrink log to near-zero then grow in one fixed-MB step.")
    } elseif ($row.status -eq 'HIGH') {
        Add-Finding 'WARNING' 'VLF Count' $row.database_name (
            "VLF count $($row.vlf_count) is high (>200). Shrink and resize the log file.")
    } elseif ($row.status -eq 'ELEVATED') {
        Add-Finding 'INFO' 'VLF Count' $row.database_name (
            "VLF count $($row.vlf_count) is elevated (>50). Monitor — resize on next maintenance window.")
    }
}

# ── maintenance-jobs ──────────────────────────────────────────────────────────
# Check file existence separately: empty file (0 DBA jobs) vs missing file (collection
# skipped/failed) need different responses. Count-based guard silently swallows the
# most important case — a fresh server with no maintenance framework deployed at all.
$maintJobsFile = Join-Path $FolderPath 'maintenance-jobs.csv'
if (Test-Path -LiteralPath $maintJobsFile) {
    $maintJobs = Read-Csv-Safe 'maintenance-jobs'
    $backupJob = $maintJobs | Where-Object { $_.job_name -like 'DBA - Backup - FULL*' }
    if (-not $backupJob) {
        Add-Finding 'WARNING' 'Maintenance Jobs' 'DBA - Backup - FULL' (
            'Full backup job not found. Run .\\powershell\\wrappers\\maintenance\\Generate-BackupJobs.ps1.')
    }
    foreach ($row in $maintJobs) {
        if ($row.last_run_status -eq 'Failed') {
            Add-Finding 'WARNING' 'Maintenance Job' $row.job_name (
                "Last run FAILED. Check SQL Agent job history for details.")
        }
        if ($row.status -eq 'Disabled') {
            Add-Finding 'WARNING' 'Maintenance Job' $row.job_name "Job is disabled — no scheduled maintenance running."
        }
    }
}

# ── failed-logins ─────────────────────────────────────────────────────────────
$failedLogins = Read-Csv-Safe 'failed-logins'
foreach ($row in $failedLogins) {
    if ($row.is_currently_locked -in @('1','True','true')) {
        Add-Finding 'CRITICAL' 'Failed Logins' $row.login_name 'Login is currently locked out'
    }
    if ($row.status -like 'CRITICAL*') {
        Add-Finding 'CRITICAL' 'Failed Logins' $row.login_name "$($row.failure_count) failures in error log — likely brute-force or app misconfiguration"
    } elseif ($row.status -like 'WARN*') {
        Add-Finding 'WARNING' 'Failed Logins' $row.login_name "$($row.failure_count) repeated failures in error log"
    }
}

# ── query-store-status ────────────────────────────────────────────────────────
$qsStatus = Read-Csv-Safe 'query-store-status'
foreach ($row in $qsStatus) {
    if ($row.qs_state -eq 'READ_ONLY' -and $row.qs_desired_state -in @('READ_WRITE','AUTO')) {
        $fp = if ($row.fill_pct -and $row.fill_pct -ne '') { " ($([Math]::Round([double]$row.fill_pct,1))% full)" } else { '' }
        Add-Finding 'WARNING' 'Query Store' $row.database_name "QS switched to READ_ONLY$fp — storage full or error; plan history is paused"
    }
}

# ── extended-events ───────────────────────────────────────────────────────────
$xeSessions = Read-Csv-Safe 'extended-events'
$sysXeNames = @('system_health','AlwaysOn_health','telemetry_xevents','hkenginexesession')
$userXE     = @($xeSessions | Where-Object { $_.session_name -notin $sysXeNames })
if ($userXE.Count -gt 0) {
    Add-Finding 'INFO' 'Extended Events' "$($userXE.Count) user session(s) running" (
        ($userXE | Select-Object -ExpandProperty session_name) -join ', ')
}

# ── cdc-and-ct ────────────────────────────────────────────────────────────────
$cdcCt = Read-Csv-Safe 'cdc-and-ct'
foreach ($row in $cdcCt) {
    if ($row.status -like 'WARN*') {
        Add-Finding 'WARNING' 'CDC / Change Tracking' $row.database_name $row.status
    }
}

# ── service-broker ────────────────────────────────────────────────────────────
$svcBroker = Read-Csv-Safe 'service-broker'
foreach ($row in $svcBroker) {
    if ($row.status -like 'CRITICAL*') {
        Add-Finding 'CRITICAL' 'Service Broker' $row.database_name $row.status
    } elseif ($row.status -like 'WARN*') {
        Add-Finding 'WARNING' 'Service Broker' $row.database_name $row.status
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
try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch { $null = $_ }
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
    Write-Host "             (web UI not running — start with: .\web-ui\Start-WebUi.ps1)" -ForegroundColor DarkGray
}
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''