<#
.SYNOPSIS
Runs the health check collection across multiple SQL Server instances and surfaces
aggregated CRITICAL/WARNING findings across the estate.

.NOTES
ScriptType   : automation
TargetScope  : multi-server
RiskLevel    : SAFE
Purpose      : Estate-wide health check — one command to flag which servers need
               attention and why. Calls the existing per-server health check scripts
               rather than duplicating their logic.

.DESCRIPTION
For each server: runs Invoke-HealthCheckCollection.ps1 (45 scripts) then
Review-HealthCheckOutput.ps1 (17 rule categories). Aggregates findings across all
servers sorted by severity. Saves a combined findings CSV.

.PARAMETER Servers
Comma-separated SQL Server instances. Takes precedence over -ServerListFile.

.PARAMETER ServerListFile
Path to a text file with one server per line. Lines starting with # are ignored.

.PARAMETER Parallel
Run collection against all servers simultaneously (PS7+). Default: sequential.

.PARAMETER ThrottleLimit
Max concurrent collection jobs when -Parallel is used. Default: 4 (collection
is I/O heavy — more than 4 simultaneous usually doesn't help).

.EXAMPLE
.\powershell\reporting\Invoke-MultiServerHealthCheck.ps1 -Servers "SVR01,SVR02,SVR03"
.\powershell\reporting\Invoke-MultiServerHealthCheck.ps1 -ServerListFile servers.txt -Parallel
#>

[CmdletBinding()]
param(
    [string]$Servers,
    [string]$ServerListFile,
    [switch]$Parallel,
    [int]$ThrottleLimit = 4
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$collectScript = Join-Path $repoRoot 'powershell\reporting\Invoke-HealthCheckCollection.ps1'
$reviewScript  = Join-Path $repoRoot 'powershell\reporting\Review-HealthCheckOutput.ps1'

if (-not (Test-Path $collectScript)) { throw "Invoke-HealthCheckCollection.ps1 not found at $collectScript" }
if (-not (Test-Path $reviewScript))  { throw "Review-HealthCheckOutput.ps1 not found at $reviewScript" }

# ---------------------------------------------------------------------------
# Build server list
# ---------------------------------------------------------------------------

$serverList = @()
if ($Servers) {
    $serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
if ($ServerListFile -and (Test-Path $ServerListFile)) {
    $fileServers = Get-Content $ServerListFile |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
        ForEach-Object { $_.Trim() }
    $serverList = @($serverList) + @($fileServers) | Select-Object -Unique
}
if ($serverList.Count -eq 0) {
    throw "No servers specified. Use -Servers or -ServerListFile."
}

Write-Host ''
Write-Host "  Multi-server health check — $($serverList.Count) server(s)" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 56)) -ForegroundColor DarkCyan
Write-Host ''

# ---------------------------------------------------------------------------
# Run collection per server — captures the output folder path from stdout
# ---------------------------------------------------------------------------

function Invoke-CollectionForServer {
    param([string]$Server)
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
        -File $using:collectScript -ServerInstance $Server -Quiet 2>&1
    $folderLine = $output | Where-Object { $_ -match '^\s+Folder\s+:' } | Select-Object -Last 1
    if ($folderLine -match ':\s+(.+)$') {
        return $Matches[1].Trim()
    }
    return $null
}

$collectionFolders = [System.Collections.Generic.Dictionary[string,string]]::new()

if ($Parallel) {
    Write-Host "  Running parallel collection (ThrottleLimit $ThrottleLimit)..." -ForegroundColor DarkGray
    $results = $serverList | ForEach-Object -Parallel {
        $srv    = $_
        $cs     = $using:collectScript
        $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File $cs -ServerInstance $srv -Quiet 2>&1
        $folderLine = $output | Where-Object { $_ -match '^\s+Folder\s+:' } | Select-Object -Last 1
        $folder = if ($folderLine -match ':\s+(.+)$') { $Matches[1].Trim() } else { $null }
        [PSCustomObject]@{ Server = $srv; Folder = $folder }
    } -ThrottleLimit $ThrottleLimit

    foreach ($r in $results) {
        if ($r.Folder) {
            $collectionFolders[$r.Server] = $r.Folder
            Write-Host "  [OK]  $($r.Server) → $($r.Folder)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($r.Server) — collection failed or folder not found" -ForegroundColor Red
        }
    }
} else {
    foreach ($server in $serverList) {
        Write-Host "  Collecting: $server..." -ForegroundColor DarkGray -NoNewline
        try {
            $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
                -File $collectScript -ServerInstance $server -Quiet 2>&1
            $folderLine = $output | Where-Object { $_ -match '^\s+Folder\s+:' } | Select-Object -Last 1
            if ($folderLine -match ':\s+(.+)$') {
                $folder = $Matches[1].Trim()
                $collectionFolders[$server] = $folder
                Write-Host " OK" -ForegroundColor Green
            } else {
                Write-Host " folder not found in output" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ''

# ---------------------------------------------------------------------------
# Run review per folder and load findings.csv
# ---------------------------------------------------------------------------

$allFindings = [System.Collections.Generic.List[PSObject]]::new()

foreach ($kv in $collectionFolders.GetEnumerator()) {
    $server = $kv.Key
    $folder = $kv.Value
    Write-Host "  Reviewing: $server..." -ForegroundColor DarkGray -NoNewline
    try {
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File $reviewScript -FolderPath $folder -OutputFormat Csv 2>&1 | Out-Null

        $findingsCsv = Join-Path $folder 'findings.csv'
        if (Test-Path $findingsCsv) {
            $rows = @(Import-Csv $findingsCsv -ErrorAction SilentlyContinue)
            foreach ($row in $rows) {
                $allFindings.Add([PSCustomObject]@{
                    Server   = $server
                    Severity = $row.Severity
                    Category = $row.Category
                    Subject  = $row.Subject
                    Detail   = $row.Detail
                })
            }
            $crit = @($rows | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
            $warn = @($rows | Where-Object { $_.Severity -eq 'WARNING'  }).Count
            $info = @($rows | Where-Object { $_.Severity -eq 'INFO'     }).Count
            Write-Host " $($rows.Count) findings (CRIT:$crit WARN:$warn INFO:$info)" -ForegroundColor $(
                if ($crit -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' }
            )
        } else {
            Write-Host " no findings" -ForegroundColor Green
        }
    } catch {
        Write-Host " review failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Aggregate summary
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host ("  " + ("─" * 56)) -ForegroundColor DarkCyan
Write-Host "  Summary by server" -ForegroundColor Cyan

$serverSummary = $allFindings | Group-Object Server | ForEach-Object {
    $grp = $_.Group
    [PSCustomObject]@{
        Server   = $_.Name
        CRITICAL = @($grp | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
        WARNING  = @($grp | Where-Object { $_.Severity -eq 'WARNING'  }).Count
        INFO     = @($grp | Where-Object { $_.Severity -eq 'INFO'     }).Count
        Total    = $grp.Count
    }
}
$serverSummary | Sort-Object CRITICAL -Descending | Format-Table -AutoSize

# Print CRITICAL findings across all servers
$criticals = @($allFindings | Where-Object { $_.Severity -eq 'CRITICAL' })
if ($criticals.Count -gt 0) {
    Write-Host "  CRITICAL findings" -ForegroundColor Red
    $criticals | Sort-Object Server, Category | Format-Table Server, Category, Subject, Detail -AutoSize
}

# ---------------------------------------------------------------------------
# Save aggregated CSV
# ---------------------------------------------------------------------------

if ($allFindings.Count -gt 0) {
    $outDir  = Join-Path $repoRoot 'output-files\healthcheck'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile = Join-Path $outDir "multi-server-$ts.csv"
    $allFindings | Sort-Object {
        @{ CRITICAL=0; WARNING=1; INFO=2 }[$_.Severity]
    }, Server, Category | Export-Csv -LiteralPath $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "  Saved: $outFile" -ForegroundColor Green
}

Write-Host ''