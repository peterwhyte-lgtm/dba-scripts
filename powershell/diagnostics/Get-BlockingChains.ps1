<#
.SYNOPSIS
Traces active SQL Server blocking chains with full chain structure, wait details, and optional execution plans.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Deep-dive blocking diagnostic. Shows every session in every active
               chain ordered by chain then depth, including idle head blockers.
               Exits cleanly with a message when the server is not blocked.

.DESCRIPTION
Wrapper around sql\diagnostics\Get-BlockingChains.sql. When -IncludePlan is set,
runs sql\diagnostics\Get-BlockingChainsWithPlan.sql and writes each session's
query_plan XML to a separate plan-<session_id>-<yyyyMMdd-HHmmss>.xml file.

Key output columns:
  chain_id           — head blocker session_id; groups all sessions in a chain
  chain_level        — 0 = head blocker, 1+ = depth in chain
  role               — 'head blocker' or 'blocked'
  downstream_waiters — sessions directly blocked by this node
  sql_text           — current statement (active) or last statement (idle blocker)

An ISO 8601 collection_time column is prepended to every CSV row. Results are
written to output-files\diagnostics\blocking-chains\ by default.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database context. Defaults to 'master'.

.PARAMETER IncludePlan
When set, runs the plan variant of the SQL and writes individual plan XML files
alongside the CSV. Plans are stripped from the CSV itself.

.PARAMETER OutputPath
Full path for the output CSV. Defaults to:
  output-files\diagnostics\blocking-chains\<server>-<yyyyMMdd-HHmmss>.csv

.PARAMETER Append
Append rows to an existing CSV instead of overwriting.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\diagnostics\Get-BlockingChains.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\diagnostics\Get-BlockingChains.ps1 -ServerInstance PROD01\SQL2019 -IncludePlan

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\diagnostics\Get-BlockingChains.ps1 -ServerInstance . -Append -OutputPath .\output-files\diagnostics\blocking-chains\rolling.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [switch]$IncludePlan,
    [string]$OutputPath,
    [switch]$Append
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner    = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'

$sqlName   = if ($IncludePlan) { 'Get-BlockingChainsWithPlan.sql' } else { 'Get-BlockingChains.sql' }
$sqlScript = Join-Path $repoRoot "sql\diagnostics\$sqlName"

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

# ── Output paths
$safeName = ($ServerInstance -replace '[\\/:*?"<>|,]', '-').Trim('-')
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot "output-files\diagnostics\blocking-chains\$safeName-$stamp.csv"
}
$outDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$tmpDir  = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$tmpPath = Join-Path $tmpDir "blocking-chains-$stamp.csv"

# ── Execute via canonical engine
Write-Host "Running blocking-chains$(if ($IncludePlan) { ' (with plan)' })..." -ForegroundColor Cyan
$env:DBASCRIPTS_BATCH = '1'
try {
    & $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database `
              -OutputFormat Csv -OutputPath $tmpPath
} finally {
    Remove-Item Env:DBASCRIPTS_BATCH -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $tmpPath)) {
    Write-Host '[blocking-chains] No output file produced by SQL execution.' -ForegroundColor Yellow
    exit 0
}

$rows = @(Import-Csv -LiteralPath $tmpPath -Encoding UTF8)
Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue

# No blocking is the normal healthy state — exit cleanly without writing a CSV
if ($rows.Count -eq 0) {
    Write-Host '[blocking-chains] No active blocking chains detected.' -ForegroundColor Green
    exit 0
}

# ── Prepend ISO 8601 collection timestamp
$collectionTime = (Get-Date).ToString('o')
$rows = $rows | Select-Object @{N='collection_time'; E={ $collectionTime }}, *

# ── Extract plan XML to individual files then strip from CSV
if ($IncludePlan) {
    $planCount = 0
    foreach ($row in $rows) {
        $planXml = $row.query_plan
        if ($planXml -and $planXml.Trim()) {
            $planFile = Join-Path $outDir "plan-$($row.session_id)-$stamp.xml"
            $planXml | Out-File -FilePath $planFile -Encoding UTF8 -Force
            $planCount++
        }
    }
    $rows = $rows | Select-Object * -ExcludeProperty query_plan
    if ($planCount -gt 0) {
        Write-Host "[blocking-chains] $planCount plan XML file(s) written to: $outDir" -ForegroundColor Green
    }
}

# ── Write CSV
if ($Append) {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -Append
} else {
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
}

$chainCount = ($rows | Select-Object -ExpandProperty chain_id -Unique).Count
Write-Host "[blocking-chains] $chainCount chain(s), $($rows.Count) session(s)" -ForegroundColor DarkGray

if (-not $env:DBASCRIPTS_BATCH) {
    $relPath = $OutputPath.Replace($repoRoot.ToString(), '').TrimStart('\')
    $enc     = [Uri]::EscapeDataString($relPath)
    $url     = "http://localhost:8787/csv?p=$enc"
    $uiUp    = $false
    try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch { $null = $_ }
    Write-Host ''
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
    Write-Host "  Saved   : $relPath" -ForegroundColor Green
    if ($uiUp) {
        Write-Host "  Review  : $url" -ForegroundColor Cyan
    } else {
        Write-Host "  Review  : $url" -ForegroundColor DarkGray
        Write-Host "            (web UI not running — start with: .\tools\Start-WebUi.ps1)" -ForegroundColor DarkGray
    }
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
}
