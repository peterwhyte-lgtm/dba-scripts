<#
.SYNOPSIS
Runs a full instance assessment and generates a structured markdown report.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE

.DESCRIPTION
Orchestrates the healthcheck collection, configuration scoring, and findings review,
then generates a formatted markdown report suitable for a client handover or ownership review.

Reuses all existing monitoring scripts — adds a configuration score and report document.

Output: output-files\assessment\<server>-<timestamp>.md

Workflow:
  1. Runs Invoke-HealthCheckCollection.ps1 (or reads an existing folder via -FolderPath)
  2. Runs Get-InstanceConfigurationScore.sql — scores ~16 key configuration checks
  3. Runs Review-HealthCheckOutput.ps1 — generates findings.csv from thresholds
  4. Reads CSVs and writes a structured markdown report

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER FolderPath
Path to an existing healthcheck CSV folder. If omitted, a fresh collection is run.

.PARAMETER AssessedBy
Name to include in the report header. Defaults to the current Windows user.

.PARAMETER OutputRoot
Parent folder for the report file. Defaults to output-files\assessment under the repo root.

.EXAMPLE
.\powershell\reporting\Invoke-AssessmentReport.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
# Reuse an existing collection folder
.\powershell\reporting\Invoke-AssessmentReport.ps1 -FolderPath ".\output-files\healthcheck\PROD01-20260531-140000" -AssessedBy "Peter Whyte"
#>

param(
    [string]$ServerInstance = '.',
    [string]$FolderPath,
    [string]$AssessedBy,
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner   = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not $AssessedBy) { $AssessedBy = $env:USERNAME }
if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\assessment' }

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  SQL Server Assessment Report' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

# ── Step 1: Collect data ────────────────────────────────────────────────────
if ($FolderPath) {
    if (-not (Test-Path -LiteralPath $FolderPath)) { throw "Folder not found: $FolderPath" }
    Write-Host "  Using existing folder: $FolderPath" -ForegroundColor Yellow
}
else {
    Write-Host "  Server     : $ServerInstance"
    Write-Host "  Step 1/3   : Running healthcheck collection..." -ForegroundColor DarkGray
    $hcScript = Join-Path $repoRoot 'powershell\reporting\Invoke-HealthCheckCollection.ps1'
    & $hcScript -ServerInstance $ServerInstance -Quiet
    $hcRoot   = Join-Path $repoRoot 'output-files\healthcheck'
    $FolderPath = (Get-ChildItem -LiteralPath $hcRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    Write-Host "  Collection : $FolderPath" -ForegroundColor Green
}

# ── Step 2: Configuration score ─────────────────────────────────────────────
Write-Host "  Step 2/3   : Running configuration score..." -ForegroundColor DarkGray
$scoreSql = Join-Path $repoRoot 'sql\monitoring\instance\Get-InstanceConfigurationScore.sql'
$scoreCsv = Join-Path $FolderPath 'score.csv'
if (Test-Path -LiteralPath $scoreSql) {
    try {
        & $runner -ScriptPath $scoreSql -ServerInstance $ServerInstance -Database 'master' `
                  -OutputFormat 'Csv' -OutputPath $scoreCsv *>$null
    }
    catch { Write-Warning "Config score failed: $_" }
}

# ── Step 3: Findings ─────────────────────────────────────────────────────────
Write-Host "  Step 3/3   : Generating findings..." -ForegroundColor DarkGray
$findingsCsv = Join-Path $FolderPath 'findings.csv'
if (-not (Test-Path -LiteralPath $findingsCsv)) {
    $reviewScript = Join-Path $repoRoot 'powershell\reporting\Review-HealthCheckOutput.ps1'
    & $reviewScript -FolderPath $FolderPath *>$null
}

# ── Read CSVs ────────────────────────────────────────────────────────────────
function Read-Safe { param([string]$Name)
    $p = Join-Path $FolderPath "$Name.csv"
    if (Test-Path -LiteralPath $p) { return @(Import-Csv -LiteralPath $p -ErrorAction SilentlyContinue) }
    return @()
}

$serverInfo  = Read-Safe 'server-info'
$osHardware  = Read-Safe 'os-hardware'
$dbHealth    = Read-Safe 'database-health'
$dbSizes     = Read-Safe 'database-sizes'
$backupTimes = Read-Safe 'backup-times'
$diskSpace   = Read-Safe 'disk-space'
$findings    = Read-Safe 'findings'
$score       = Read-Safe 'score'

# ── Derive headline values ────────────────────────────────────────────────────
$sv          = if ($serverInfo.Count) { $serverInfo[0] } else { $null }
$hw          = if ($osHardware.Count)  { $osHardware[0]  } else { $null }

$serverName   = if ($sv) { $sv.server_name }          else { $ServerInstance }
$edition      = if ($hw) { $hw.sql_edition }           else { if ($sv) { $sv.edition } else { 'Unknown' } }
$sqlVersion   = if ($hw) { $hw.sql_version }           else { if ($sv) { $sv.product_version } else { 'Unknown' } }
$sqlLevel     = if ($hw) { "$($hw.sql_product_level) $($hw.sql_cu_level)".Trim() } else { '' }
$osRelease    = if ($hw) { $hw.os_release }            else { 'Unknown' }
$cpuCount     = if ($hw) { $hw.logical_cpu_count }     else { 'Unknown' }
$ramGb        = if ($hw) { $hw.physical_memory_gb }    else { 'Unknown' }
$uptimeDays   = if ($hw) { $hw.uptime_days }           else { 'Unknown' }
$isClustered  = if ($hw) { if ($hw.is_clustered -eq '1') { 'Yes (FCI)' } else { 'No' } } else { 'Unknown' }

$critCount    = @($findings | Where-Object Severity -eq 'CRITICAL').Count
$warnCount    = @($findings | Where-Object Severity -eq 'WARNING').Count
$infoCount    = @($findings | Where-Object Severity -eq 'INFO').Count
$userDbCount  = @($dbHealth | Where-Object { $_.database_name -notin @('master','model','msdb','tempdb') }).Count

# Score calculation: PASS = full, WARN = half, FAIL = none; INFO is neutral
$scoreItems   = @($score | Where-Object { $_.status -in @('PASS','WARN','FAIL') })
$passCount    = @($score | Where-Object status -eq 'PASS').Count
$warnSCount   = @($score | Where-Object status -eq 'WARN').Count
$failCount    = @($score | Where-Object status -eq 'FAIL').Count
$totalItems   = $scoreItems.Count
$instanceScore = if ($totalItems -gt 0) {
    [int](($passCount + ($warnSCount * 0.5)) / $totalItems * 100)
} else { 0 }

$scoreLabel = switch ($true) {
    ($instanceScore -ge 90) { 'Good' }
    ($instanceScore -ge 70) { 'Fair' }
    ($instanceScore -ge 50) { 'Needs Attention' }
    default                 { 'Critical' }
}

# Folder timestamp for collection date
$folderLeaf    = Split-Path -Leaf $FolderPath
$collectedDate = if ($folderLeaf -match '(\d{8}-\d{6})$') {
    [DateTime]::ParseExact($Matches[1], 'yyyyMMdd-HHmmss', $null).ToString('yyyy-MM-dd HH:mm')
} else { (Get-Date).ToString('yyyy-MM-dd HH:mm') }

# ── Build markdown report ─────────────────────────────────────────────────────
$lines = [System.Collections.Generic.List[string]]::new()

$lines.Add("# SQL Server Instance Assessment")
$lines.Add("")
$lines.Add("| | |")
$lines.Add("|-|-|")
$lines.Add("| **Server** | $serverName |")
$lines.Add("| **SQL Version** | $sqlVersion $sqlLevel |")
$lines.Add("| **Edition** | $edition |")
$lines.Add("| **OS** | $osRelease |")
$lines.Add("| **CPU** | $cpuCount logical processors |")
$lines.Add("| **RAM** | $ramGb GB |")
$lines.Add("| **Clustered** | $isClustered |")
$lines.Add("| **Uptime** | $uptimeDays days |")
$lines.Add("| **User databases** | $userDbCount |")
$lines.Add("| **Data collected** | $collectedDate |")
$lines.Add("| **Assessed by** | $AssessedBy |")
$lines.Add("")
$lines.Add("---")
$lines.Add("")
$lines.Add("## Executive Summary")
$lines.Add("")
$lines.Add("### Instance Score: $instanceScore / 100 - $scoreLabel")
$lines.Add("")
$lines.Add("| Severity | Count |")
$lines.Add("|----------|-------|")
if ($totalItems -gt 0) {
    $lines.Add("| FAIL (config) | $failCount |")
    $lines.Add("| WARN (config) | $warnSCount |")
    $lines.Add("| PASS (config) | $passCount |")
}
$lines.Add("| CRITICAL (findings) | $critCount |")
$lines.Add("| WARNING (findings) | $warnCount |")
$lines.Add("| INFO (findings) | $infoCount |")
$lines.Add("")

# Critical findings summary
$criticalFindings = @($findings | Where-Object Severity -eq 'CRITICAL')
if ($criticalFindings.Count -gt 0) {
    $lines.Add("### Critical Issues - Resolve Before Handover")
    $lines.Add("")
    foreach ($f in $criticalFindings) {
        $lines.Add("- **[$($f.Category)]** $($f.Subject) - $($f.Detail)")
    }
    $lines.Add("")
}

# FAIL config items summary
$failItems = @($score | Where-Object status -eq 'FAIL')
if ($failItems.Count -gt 0) {
    $lines.Add("### Configuration Failures")
    $lines.Add("")
    foreach ($f in $failItems) {
        $lines.Add("- **[$($f.weight)]** $($f.check_name) - $($f.finding)")
    }
    $lines.Add("")
}

$lines.Add("---")
$lines.Add("")

# ── Configuration score table ─────────────────────────────────────────────────
if ($score.Count -gt 0) {
    $lines.Add("## Configuration Score")
    $lines.Add("")
    $lines.Add("| Check | Weight | Status | Finding |")
    $lines.Add("|-------|--------|--------|---------|")
    foreach ($row in $score) {
        $statusIcon = switch ($row.status) {
            'PASS' { 'PASS' }
            'WARN' { 'WARN' }
            'FAIL' { 'FAIL' }
            'INFO' { 'INFO' }
            default { $row.status }
        }
        $finding = $row.finding -replace '\|', '/' -replace "`r?`n", ' '
        $lines.Add("| $($row.check_name) | $($row.weight) | $statusIcon | $finding |")
    }
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
}

# ── All findings ────────────────────────────────────────────────────────────
if ($findings.Count -gt 0) {
    $lines.Add("## Findings")
    $lines.Add("")
    foreach ($sev in @('CRITICAL','WARNING','INFO')) {
        $group = @($findings | Where-Object Severity -eq $sev)
        if ($group.Count -eq 0) { continue }
        $lines.Add("### $sev")
        $lines.Add("")
        $lines.Add("| Category | Subject | Detail |")
        $lines.Add("|----------|---------|--------|")
        foreach ($f in $group) {
            $detail = $f.Detail -replace '\|', '/' -replace "`r?`n", ' '
            $lines.Add("| $($f.Category) | $($f.Subject) | $detail |")
        }
        $lines.Add("")
    }
    $lines.Add("---")
    $lines.Add("")
}

# ── Database inventory ────────────────────────────────────────────────────────
if ($dbHealth.Count -gt 0) {
    $lines.Add("## Database Inventory")
    $lines.Add("")
    $lines.Add("| Database | State | Recovery | Auto-Shrink | Last Full Backup |")
    $lines.Add("|----------|-------|----------|-------------|-----------------|")
    foreach ($db in ($dbHealth | Where-Object { $_.database_name -notin @('master','model','msdb','tempdb') } | Sort-Object database_name)) {
        $lastFull = ($backupTimes | Where-Object database_name -eq $db.database_name | Select-Object -First 1).last_full_backup
        if (-not $lastFull) { $lastFull = 'None' }
        $shrink = if ($db.is_auto_shrink_on -in @('True','1','YES')) { 'YES' } else { 'No' }
        $lines.Add("| $($db.database_name) | $($db.state_desc) | $($db.recovery_model_desc) | $shrink | $lastFull |")
    }
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
}

# ── Storage ───────────────────────────────────────────────────────────────────
if ($diskSpace.Count -gt 0) {
    $lines.Add("## Storage")
    $lines.Add("")
    $lines.Add("| Volume | Total (GB) | Free (GB) | Free % |")
    $lines.Add("|--------|-----------|-----------|---------|")
    foreach ($vol in $diskSpace) {
        $freePct = if ($vol.free_gb -and $vol.total_gb -and [double]$vol.total_gb -gt 0) {
            "$([Math]::Round([double]$vol.free_gb / [double]$vol.total_gb * 100, 1))%"
        } else { 'N/A' }
        $volName = if ($vol.PSObject.Properties['volume_mount_point']) { $vol.volume_mount_point }
                   elseif ($vol.PSObject.Properties['mount_point']) { $vol.mount_point }
                   else { 'Unknown' }
        $lines.Add("| $volName | $($vol.total_gb) | $($vol.free_gb) | $freePct |")
    }
    $lines.Add("")
    $lines.Add("---")
    $lines.Add("")
}

# ── Recommendations ──────────────────────────────────────────────────────────
$recLines = [System.Collections.Generic.List[string]]::new()
$critRecs  = @($score | Where-Object { $_.status -eq 'FAIL' -and $_.weight -in @('CRITICAL','HIGH') } | Sort-Object { @('CRITICAL','HIGH','MEDIUM','LOW').IndexOf($_.weight) })
$warnRecs  = @($score | Where-Object { $_.status -in @('FAIL','WARN') -and $_.weight -eq 'MEDIUM' })
$lowRecs   = @($score | Where-Object { $_.status -in @('FAIL','WARN') -and $_.weight -eq 'LOW' })

$lines.Add("## Recommendations")
$lines.Add("")
if ($critRecs.Count -gt 0) {
    $lines.Add("### Immediate")
    $lines.Add("")
    $n = 1
    foreach ($r in $critRecs) {
        $rec = $r.recommendation -replace '\|', '/' -replace "`r?`n", ' '
        $lines.Add("$n. **$($r.check_name)** - $rec")
        $n++
    }
    $lines.Add("")
}
if ($warnRecs.Count -gt 0) {
    $lines.Add("### Short-Term")
    $lines.Add("")
    $n = 1
    foreach ($r in $warnRecs) {
        $rec = $r.recommendation -replace '\|', '/' -replace "`r?`n", ' '
        $lines.Add("$n. **$($r.check_name)** - $rec")
        $n++
    }
    $lines.Add("")
}
if ($lowRecs.Count -gt 0) {
    $lines.Add("### Best Practice")
    $lines.Add("")
    $n = 1
    foreach ($r in $lowRecs) {
        $rec = $r.recommendation -replace '\|', '/' -replace "`r?`n", ' '
        $lines.Add("$n. **$($r.check_name)** - $rec")
        $n++
    }
    $lines.Add("")
}

$lines.Add("---")
$lines.Add("")
$lines.Add("*Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Data collected: $collectedDate | Source: $FolderPath*")

# ── Write report ──────────────────────────────────────────────────────────────
$safeName   = ($serverName -replace '[\\/:*?"<>|]', '-').Trim('-')
$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $OutputRoot "$safeName-$timestamp.md"

$lines -join "`n" | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Score   : $instanceScore/100 - $scoreLabel" -ForegroundColor $(if ($instanceScore -ge 80) { 'Green' } elseif ($instanceScore -ge 60) { 'Yellow' } else { 'Red' })
Write-Host "  CRITICAL: $critCount  |  WARNING: $warnCount  |  FAIL config: $failCount"
Write-Host ''
Write-Host "  Report  : $reportPath" -ForegroundColor Green
Write-Host "  Data    : $FolderPath" -ForegroundColor DarkGray
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''