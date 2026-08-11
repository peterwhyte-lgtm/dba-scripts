<#
.SYNOPSIS
Runs a full DBA health-check collection and saves each result as a named CSV in a timestamped folder.

.NOTES
ScriptType   : PowerShell-only
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Collect all key health-check data in one pass for offline review or archiving.

.DESCRIPTION
Orchestrates the core monitoring and inventory SQL scripts against a single SQL Server instance.
Each script's output is saved as a named CSV under output-files\healthcheck\<server>-<timestamp>\.

Run this first, then pass the output folder to Review-HealthCheckOutput.ps1 to surface findings.

Scripts collected:
  server-info           - SQL version, edition, instance name
  os-hardware           - OS release, CPU count, RAM, uptime
  database-health       - database state, recovery model, auto-shrink flags
  database-sizes        - data/log sizes and free space per database
  database-files        - per-file paths, sizes, growth settings
  backup-times          - last full/diff/log backup per database
  backup-coverage       - databases with missing or stale backups (with status flag)
  tlog-usage            - transaction log size and space used
  memory-config         - max server memory, current committed, buffer pool
  wait-stats            - top wait types since last restart (benign waits filtered)
  active-sessions       - currently connected users and requests
  tempdb-usage          - tempdb file usage per file with free space
  job-failures          - SQL Agent job failures from the last 7 days
  recent-errors         - error log entries from the last 24 hours
  dbcc-checkdb          - last successful DBCC CHECKDB per database
  suspect-pages         - any pages in msdb.dbo.suspect_pages
  io-usage              - per-database I/O totals with read/write latency
  disk-space            - volume mount points with total/used/free GB (SQL-hosting drives only)
  growth-risk           - databases flagged OK / NEAR_LIMIT / AT_LIMIT vs configured file limits
  security-surface-area - xp_cmdshell, CLR, Database Mail enabled state
  weak-logins           - SQL logins with policy/expiration off or sa enabled
  missing-indexes       - top missing index candidates ranked by DMV impact score (resets on restart)
  tempdb-config         - TempDB file count, sizing parity, and autogrowth type
  plan-cache            - plan cache composition — single-use plan ratio and ad-hoc bloat
  linked-server-security - linked server login mappings with risk level assessment
  vlf-count             - virtual log file count per database (high counts degrade recovery)
  maintenance-jobs      - DBA maintenance job deployment and last-run status
  failed-logins         - failed login attempts from current error log with lockout status
  query-store-status    - Query Store state (enabled, READ_ONLY, fill %) per database
  extended-events       - active XE sessions — targets and estimated overhead
  cdc-and-ct            - CDC and Change Tracking enabled databases with retention settings
  service-broker        - Service Broker enabled databases with queue/transmission health

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputRoot
Parent folder for healthcheck output folders. Defaults to output-files\healthcheck under the repo root.

.PARAMETER OutputFolder
Exact output folder to write into (created if missing). Overrides OutputRoot and the generated
<server>-<timestamp> name. Used by the web UI so it knows the folder to poll before the run starts.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Invoke-HealthCheckCollection.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance MYSERVER\INST01

.EXAMPLE
# Collect then immediately review
$folder = pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance . 6>&1 | Select-String 'Output folder' | ForEach-Object { $_.Line -replace '.*: ' }
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath $folder
#>

param(
    [string]$ServerInstance = '.',
    [string]$OutputRoot,
    [string]$OutputFolder,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Respect the session default set by Initialize-Environment or Set-SqlConnection
if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner   = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

$env:DBASCRIPTS_BATCH = '1'  # tells Invoke-RepoSql not to open a browser tab per script

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'output-files\healthcheck'
}

if ($OutputFolder) {
    $outFolder = $OutputFolder
} else {
    $safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFolder = Join-Path $OutputRoot "$safeName-$timestamp"
}
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null

# Per-script progress manifest — rewritten after every status change so pollers
# (web UI /api/status) always see a complete, current picture. Temp+move keeps
# each write atomic for concurrent readers.
function Write-HcManifest([object[]]$Rows, [string]$Folder) {
    $tmp = Join-Path $Folder '.manifest.tmp'
    $Rows | Export-Csv -LiteralPath $tmp -NoTypeInformation
    Move-Item -LiteralPath $tmp -Destination (Join-Path $Folder 'manifest.csv') -Force
}

try {

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  DBA Health Check Collection' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Server : $ServerInstance"
Write-Host "  Output : $outFolder"
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'
Write-Host ''

# Each entry: Label (becomes CSV filename) and relative path to the SQL script.
# Paths are tried in order — first match wins, remaining are skipped.
$scripts = @(
    [PSCustomObject]@{
        Label = 'server-info'
        Paths = @('sql\inventory\Get-VersionAndEdition.sql')
    }
    [PSCustomObject]@{
        Label = 'os-hardware'
        Paths = @('sql\inventory\Get-OsAndHardwareInfo.sql')
    }
    [PSCustomObject]@{
        Label = 'database-health'
        Paths = @('sql\monitoring\databases\Get-DatabaseHealth.sql')
    }
    [PSCustomObject]@{
        Label = 'database-sizes'
        Paths = @('sql\monitoring\disk-space\Get-DatabaseSizesAndFreeSpace.sql')
    }
    [PSCustomObject]@{
        Label = 'database-files'
        Paths = @('sql\monitoring\disk-space\Get-DatabaseFilesDetail.sql')
    }
    [PSCustomObject]@{
        Label = 'backup-times'
        Paths = @('sql\backups\Get-LastDatabaseBackupTimes.sql')
    }
    [PSCustomObject]@{
        Label = 'backup-coverage'
        Paths = @('sql\backups\Get-BackupCoverage.sql')
    }
    [PSCustomObject]@{
        Label = 'tlog-usage'
        Paths = @('sql\monitoring\disk-space\Get-TransactionLogSizeAndUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'memory-config'
        Paths = @('sql\monitoring\instance\Get-MemoryConfigurationAndUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'wait-stats'
        Paths = @('sql\performance\Get-WaitStatistics.sql')
    }
    [PSCustomObject]@{
        Label = 'active-sessions'
        Paths = @('sql\performance\active-sessions\Get-ActiveSessions.sql')
    }
    [PSCustomObject]@{
        Label = 'tempdb-usage'
        Paths = @('sql\monitoring\tempdb\Get-TempdbUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'job-failures'
        Paths = @('sql\monitoring\jobs\Get-SqlAgentJobFailureSummary.sql')
    }
    [PSCustomObject]@{
        Label = 'recent-errors'
        Paths = @('sql\monitoring\error-log\Get-RecentErrorLogEntries.sql')
    }
    [PSCustomObject]@{
        Label = 'dbcc-checkdb'
        Paths = @('sql\monitoring\databases\Get-LastDbccCheckdb.sql')
    }
    [PSCustomObject]@{
        Label = 'suspect-pages'
        Paths = @('sql\monitoring\databases\Get-SuspectPages.sql')
    }
    [PSCustomObject]@{
        Label = 'io-usage'
        Paths = @('sql\performance\Get-DatabaseIoUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'disk-space'
        Paths = @('sql\monitoring\disk-space\Get-DiskSpace.sql')
    }
    [PSCustomObject]@{
        Label = 'growth-risk'
        Paths = @('sql\monitoring\disk-space\Get-DatabaseGrowthRisk.sql')
    }
    [PSCustomObject]@{
        Label = 'security-surface-area'
        Paths = @('sql\security\Get-DatabaseMailAndXpCmdShell.sql')
    }
    [PSCustomObject]@{
        Label = 'weak-logins'
        Paths = @('sql\security\access\Get-WeakLoginSettings.sql')
    }
    [PSCustomObject]@{
        Label = 'missing-indexes'
        Paths = @('sql\performance\indexes\Get-MissingIndexes.sql')
    }
    [PSCustomObject]@{
        Label = 'tempdb-config'
        Paths = @('sql\monitoring\tempdb\Get-TempDbConfiguration.sql')
    }
    [PSCustomObject]@{
        Label = 'plan-cache'
        Paths = @('sql\performance\queries\Get-PlanCacheHealth.sql')
    }
    [PSCustomObject]@{
        Label = 'linked-server-security'
        Paths = @('sql\security\Get-LinkedServerSecurity.sql')
    }
    [PSCustomObject]@{
        Label = 'vlf-count'
        Paths = @('sql\monitoring\disk-space\Get-VlfCount.sql')
    }
    [PSCustomObject]@{
        Label    = 'maintenance-jobs'
        Paths    = @('sql\maintenance\Get-MaintenanceJobStatus.sql')
        Database = 'msdb'
    }
    [PSCustomObject]@{
        Label = 'failed-logins'
        Paths = @('sql\security\access\Get-FailedLoginSummary.sql')
    }
    [PSCustomObject]@{
        Label = 'query-store-status'
        Paths = @('sql\monitoring\features\Get-QueryStoreStatus.sql')
    }
    [PSCustomObject]@{
        Label = 'extended-events'
        Paths = @('sql\monitoring\features\Get-ExtendedEventsSessions.sql')
    }
    [PSCustomObject]@{
        Label = 'cdc-and-ct'
        Paths = @('sql\monitoring\features\Get-CdcAndChangeTracking.sql')
    }
    [PSCustomObject]@{
        Label = 'service-broker'
        Paths = @('sql\monitoring\features\Get-ServiceBrokerHealth.sql')
    }
    [PSCustomObject]@{
        Label = 'sysadmin-members'
        Paths = @('sql\security\access\Get-SysadminMembers.sql')
    }
    [PSCustomObject]@{
        Label = 'instance-config'
        Paths = @('sql\monitoring\instance\Get-InstanceConfigurationSnapshot.sql')
    }
    [PSCustomObject]@{
        Label = 'top-cpu-queries'
        Paths = @('sql\performance\queries\Get-TopCpuQueries.sql')
    }
    [PSCustomObject]@{
        Label = 'agent-jobs-overview'
        Paths = @('sql\monitoring\jobs\Get-SqlAgentJobOverview.sql')
    }
    [PSCustomObject]@{
        Label = 'orphaned-users'
        Paths = @('sql\security\access\Get-OrphanedUsers.sql')
    }
    [PSCustomObject]@{
        Label = 'certificate-expiry'
        Paths = @('sql\security\encryption\Get-CertificateExpiryWarnings.sql')
    }
    [PSCustomObject]@{
        Label = 'autogrowth-history'
        Paths = @('sql\monitoring\disk-space\Get-AutogrowthHistory.sql')
    }
    [PSCustomObject]@{
        Label = 'ag-replica-state'
        Paths = @('sql\high-availability\always-on\Get-AvailabilityGroupReplicaState.sql')
    }
    [PSCustomObject]@{
        Label = 'ag-failover-readiness'
        Paths = @('sql\high-availability\always-on\Get-AgFailoverReadiness.sql')
    }
    [PSCustomObject]@{
        Label = 'ag-latency'
        Paths = @('sql\high-availability\always-on\Get-AvailabilityGroupLatency.sql')
    }
    [PSCustomObject]@{
        Label = 'mirroring-endpoint-health'
        Paths = @('sql\high-availability\mirroring\Get-MirroringEndpointHealth.sql')
    }
    [PSCustomObject]@{
        Label = 'replication-status'
        Paths = @('sql\high-availability\replication\Get-ReplicationStatus.sql')
    }
    [PSCustomObject]@{
        Label = 'last-node-blip'
        Paths = @('sql\high-availability\fci\Get-LastNodeBlip.sql')
    }
)

# All planned scripts go into the manifest as PENDING up front, so pollers know
# the total and the full script list from the first write.
$manifest = [System.Collections.Generic.List[PSObject]]::new()
foreach ($s in $scripts) {
    $manifest.Add([PSCustomObject]@{
        Script      = $s.Label
        Status      = 'PENDING'
        Started     = ''
        Finished    = ''
        DurationSec = ''
        Note        = ''
    })
}
Write-HcManifest $manifest $outFolder

foreach ($s in $scripts) {
    $resolvedSql = $null
    foreach ($p in $s.Paths) {
        $candidate = Join-Path $repoRoot $p
        if (Test-Path -LiteralPath $candidate) {
            $resolvedSql = $candidate
            break
        }
    }

    $csvPath = Join-Path $outFolder "$($s.Label).csv"
    $status  = 'OK'
    $note    = ''
    $db      = if ($s.PSObject.Properties['Database'] -and $s.Database) { $s.Database } else { 'master' }

    $mRow = $manifest | Where-Object Script -eq $s.Label | Select-Object -First 1
    $mRow.Status  = 'RUNNING'
    $mRow.Started = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-HcManifest $manifest $outFolder
    $swScript = [System.Diagnostics.Stopwatch]::StartNew()

    if (-not $resolvedSql) {
        $status = 'SKIPPED'
        $note   = 'SQL file not found'
    }
    else {
        try {
            if ($Quiet) {
                & $runner -ScriptPath $resolvedSql `
                          -ServerInstance $ServerInstance `
                          -Database $db `
                          -OutputFormat 'Csv' `
                          -OutputPath $csvPath *>$null
            }
            else {
                & $runner -ScriptPath $resolvedSql `
                          -ServerInstance $ServerInstance `
                          -Database $db `
                          -OutputFormat 'Csv' `
                          -OutputPath $csvPath
            }
        }
        catch {
            $status = 'FAILED'
            $note   = $_.Exception.Message -replace "`r?`n", ' '
        }
    }

    $swScript.Stop()
    $mRow.Status      = $status
    $mRow.Finished    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $mRow.DurationSec = [math]::Round($swScript.Elapsed.TotalSeconds, 1)
    $mRow.Note        = $note
    Write-HcManifest $manifest $outFolder

    $color = switch ($status) {
        'OK'      { 'Green' }
        'SKIPPED' { 'Yellow' }
        default   { 'Red' }
    }
    Write-Host ("  [{0,-8}] {1}" -f $status, $s.Label) -ForegroundColor $color
    if ($status -eq 'FAILED' -and $note) {
        $shortNote = if ($note.Length -gt 140) { $note.Substring(0, 140) + '…' } else { $note }
        Write-Host "             $shortNote" -ForegroundColor DarkRed
    }
}

Write-Host ''
Write-Host '--------------------------------------------'
$ok      = @($manifest | Where-Object Status -eq 'OK').Count
$failed  = @($manifest | Where-Object Status -eq 'FAILED').Count
$skipped = @($manifest | Where-Object Status -eq 'SKIPPED').Count
Write-Host "  OK: $ok  |  Failed: $failed  |  Skipped: $skipped" -ForegroundColor Cyan
Write-Host ''

$uiUp = $false
try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch { $null = $_ }
$folderEnc  = [Uri]::EscapeDataString($outFolder)
$reviewUrl  = "http://localhost:8787/review?folder=$folderEnc"

Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Folder  : $outFolder" -ForegroundColor Green
if ($uiUp) {
    Write-Host "  Dashboard: $reviewUrl" -ForegroundColor Cyan
} else {
    Write-Host "  Dashboard: $reviewUrl" -ForegroundColor DarkGray
    Write-Host "             (web UI not running — start with: .\web-ui\Start-WebUi.ps1)" -ForegroundColor DarkGray
}
Write-Host ''
Write-Host "  CLI review: .\powershell\reporting\Review-HealthCheckOutput.ps1" -ForegroundColor DarkGray
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''

} finally {
    Remove-Item Env:DBASCRIPTS_BATCH -ErrorAction SilentlyContinue
}