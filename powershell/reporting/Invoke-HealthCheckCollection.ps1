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
  security-surface-area - xp_cmdshell, CLR, Database Mail enabled state
  weak-logins           - SQL logins with policy/expiration off or sa enabled

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputRoot
Parent folder for healthcheck output folders. Defaults to output-files\healthcheck under the repo root.

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
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$env:DBASCRIPTS_BATCH = '1'  # tells Invoke-RepoSql not to open 19 browser tabs

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner   = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'output-files\healthcheck'
}

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFolder = Join-Path $OutputRoot "$safeName-$timestamp"
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null

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
        Paths = @('sql\monitoring\Get-VersionAndEdition.sql')
    }
    [PSCustomObject]@{
        Label = 'os-hardware'
        Paths = @('sql\monitoring\Get-OsAndHardwareInfo.sql')
    }
    [PSCustomObject]@{
        Label = 'database-health'
        Paths = @('sql\monitoring\Get-DatabaseHealth.sql')
    }
    [PSCustomObject]@{
        Label = 'database-sizes'
        Paths = @('sql\monitoring\Get-DatabaseSizesAndFreeSpace.sql')
    }
    [PSCustomObject]@{
        Label = 'database-files'
        Paths = @('sql\monitoring\Get-DatabaseFilesDetail.sql')
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
        Paths = @('sql\monitoring\Get-TransactionLogSizeAndUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'memory-config'
        Paths = @('sql\monitoring\Get-MemoryConfigurationAndUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'wait-stats'
        Paths = @('sql\performance\Get-WaitStatistics.sql')
    }
    [PSCustomObject]@{
        Label = 'active-sessions'
        Paths = @('sql\performance\Get-ActiveSessions.sql')
    }
    [PSCustomObject]@{
        Label = 'tempdb-usage'
        Paths = @('sql\monitoring\Get-TempdbUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'job-failures'
        Paths = @('sql\monitoring\Get-SqlAgentJobFailureSummary.sql')
    }
    [PSCustomObject]@{
        Label = 'recent-errors'
        Paths = @('sql\monitoring\Get-RecentErrorLogEntries.sql')
    }
    [PSCustomObject]@{
        Label = 'dbcc-checkdb'
        Paths = @('sql\monitoring\Get-LastDbccCheckdb.sql')
    }
    [PSCustomObject]@{
        Label = 'suspect-pages'
        Paths = @('sql\monitoring\Get-SuspectPages.sql')
    }
    [PSCustomObject]@{
        Label = 'io-usage'
        Paths = @('sql\performance\Get-DatabaseIoUsage.sql')
    }
    [PSCustomObject]@{
        Label = 'security-surface-area'
        Paths = @('sql\security\Get-DatabaseMailAndXpCmdShell.sql')
    }
    [PSCustomObject]@{
        Label = 'weak-logins'
        Paths = @('sql\security\Get-WeakLoginSettings.sql')
    }
)

$summary = [System.Collections.Generic.List[PSObject]]::new()

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

    if (-not $resolvedSql) {
        $status = 'SKIPPED'
        $note   = 'SQL file not found'
    }
    else {
        try {
            if ($Quiet) {
                & $runner -ScriptPath $resolvedSql `
                          -ServerInstance $ServerInstance `
                          -Database 'master' `
                          -OutputFormat 'Csv' `
                          -OutputPath $csvPath *>$null
            }
            else {
                & $runner -ScriptPath $resolvedSql `
                          -ServerInstance $ServerInstance `
                          -Database 'master' `
                          -OutputFormat 'Csv' `
                          -OutputPath $csvPath
            }
        }
        catch {
            $status = 'FAILED'
            $note   = $_.Exception.Message -replace "`r?`n", ' '
        }
    }

    $color = switch ($status) {
        'OK'      { 'Green' }
        'SKIPPED' { 'Yellow' }
        default   { 'Red' }
    }
    Write-Host ("  [{0,-8}] {1}" -f $status, $s.Label) -ForegroundColor $color

    $summary.Add([PSCustomObject]@{
        Script  = $s.Label
        Status  = $status
        CsvFile = if ($status -eq 'OK') { Split-Path -Leaf $csvPath } else { '' }
        Note    = $note
    })
}

Write-Host ''
Write-Host '--------------------------------------------'
$ok      = @($summary | Where-Object Status -eq 'OK').Count
$failed  = @($summary | Where-Object Status -eq 'FAILED').Count
$skipped = @($summary | Where-Object Status -eq 'SKIPPED').Count
Write-Host "  OK: $ok  |  Failed: $failed  |  Skipped: $skipped" -ForegroundColor Cyan
Write-Host ''
Write-Host "Output folder: $outFolder" -ForegroundColor Green
Write-Host ''
Write-Host 'Next step: review findings with'
Write-Host "  .\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath '$outFolder'" -ForegroundColor Yellow
Write-Host ''
$env:DBASCRIPTS_BATCH = $null
