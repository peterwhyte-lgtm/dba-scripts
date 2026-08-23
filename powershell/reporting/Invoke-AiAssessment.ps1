<#
.SYNOPSIS
Sends a healthcheck collection to the Claude API and writes an AI-generated assessment report.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE (read-only locally — but sends healthcheck CSV contents to the Anthropic API;
               use -DryRun to review exactly what would be sent before it leaves the machine)

.DESCRIPTION
The AI layer of the healthcheck workflow:

  1. Invoke-HealthCheckCollection.ps1  — collect 39 CSVs        (deterministic)
  2. Review-HealthCheckOutput.ps1      — threshold findings.csv (deterministic)
  3. Invoke-AiAssessment.ps1           — THIS: correlation, root cause, prioritized
                                         written assessment across security, performance,
                                         backups, and operational hygiene

Reads every CSV in the healthcheck folder (running the findings review first if
findings.csv is missing), builds a prompt from powershell\reporting\ai-assessment-rubric.md,
calls the Claude API, and writes a markdown report to output-files\assessments\.

Requires the ANTHROPIC_API_KEY environment variable (not needed for -DryRun).

Data privacy: CSV contents (server names, database names, login names, file paths) are
sent to the Anthropic API. Run -DryRun first on any environment where that needs sign-off.

.PARAMETER FolderPath
Path to a healthcheck CSV folder. Defaults to the most recent folder under
output-files\healthcheck\.

.PARAMETER Model
Claude model ID. Defaults to claude-opus-5.

.PARAMETER MaxTokens
Maximum output tokens for the report. Defaults to 16000.

.PARAMETER MaxRowsPerCsv
Row cap per CSV included in the prompt (keeps token cost bounded on large outputs like
missing-indexes). Truncation is noted in the prompt so the model knows. Defaults to 100.

.PARAMETER OutputRoot
Parent folder for the report. Defaults to output-files\assessments under the repo root.

.PARAMETER ApiBaseUrl
Base URL for the Claude API. Defaults to the ANTHROPIC_BASE_URL environment variable if
set, otherwise https://api.anthropic.com. Corporate users behind an AI gateway/proxy set
this (or the env var) to their company endpoint — no other change needed.

.PARAMETER DryRun
Builds the full prompt and writes it to a preview file without calling the API.
Use this to review the data before it leaves the machine, or when no API key is set.

.EXAMPLE
.\powershell\reporting\Invoke-AiAssessment.ps1

.EXAMPLE
.\powershell\reporting\Invoke-AiAssessment.ps1 -FolderPath ".\output-files\healthcheck\PROD01-20260702-120000" -DryRun
#>

param(
    [string]$FolderPath,
    [string]$Model = 'claude-opus-5',
    [int]$MaxTokens = 16000,
    [int]$MaxRowsPerCsv = 100,
    [string]$OutputRoot,
    [string]$ApiBaseUrl,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$rubricPath = Join-Path $PSScriptRoot 'ai-assessment-rubric.md'

if (-not $OutputRoot) { $OutputRoot = Join-Path $repoRoot 'output-files\assessments' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  AI Health Assessment' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

# ── Step 1: Resolve the collection folder ───────────────────────────────────
if (-not $FolderPath) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    if (-not (Test-Path -LiteralPath $hcRoot)) { throw "No healthcheck output found. Run Invoke-HealthCheckCollection.ps1 first." }
    $latest = Get-ChildItem -LiteralPath $hcRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No healthcheck folders under $hcRoot. Run Invoke-HealthCheckCollection.ps1 first." }
    $FolderPath = $latest.FullName
}
if (-not (Test-Path -LiteralPath $FolderPath)) { throw "Folder not found: $FolderPath" }
Write-Host "  Collection : $FolderPath"

# ── Step 2: Ensure findings.csv exists (run the rules review if not) ────────
$findingsCsv = Join-Path $FolderPath 'findings.csv'
if (-not (Test-Path -LiteralPath $findingsCsv)) {
    Write-Host '  Findings   : missing - running Review-HealthCheckOutput...' -ForegroundColor DarkGray
    $reviewScript = Join-Path $PSScriptRoot 'Review-HealthCheckOutput.ps1'
    & $reviewScript -FolderPath $FolderPath -OutputFormat Csv | Out-Null
}

# ── Step 3: Build the prompt ────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $rubricPath)) { throw "Rubric not found: $rubricPath" }
$rubric = Get-Content -LiteralPath $rubricPath -Raw -Encoding UTF8

$csvFiles = Get-ChildItem -LiteralPath $FolderPath -Filter '*.csv' | Sort-Object Name
if (-not $csvFiles) { throw "No CSV files in $FolderPath" }

# Server label from server-info.csv when available, else the folder name prefix
$serverLabel = (Split-Path $FolderPath -Leaf) -replace '-\d{8}-\d{6}$', ''
$serverInfoCsv = Join-Path $FolderPath 'server-info.csv'
if (Test-Path -LiteralPath $serverInfoCsv) {
    $row  = Import-Csv -LiteralPath $serverInfoCsv | Select-Object -First 1
    $prop = $row.PSObject.Properties | Where-Object { $_.Name -match 'server' } | Select-Object -First 1
    if ($prop -and $prop.Value) { $serverLabel = $prop.Value }
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("Healthcheck collection for server: $serverLabel")
[void]$sb.AppendLine("Collection folder: $(Split-Path $FolderPath -Leaf)")
[void]$sb.AppendLine("Collected files follow. Rows per file are capped at $MaxRowsPerCsv; truncation is noted.")
[void]$sb.AppendLine('')

foreach ($file in $csvFiles) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
    $dataRows = [Math]::Max($lines.Count - 1, 0)
    [void]$sb.AppendLine("### $($file.Name) ($dataRows rows)")
    if ($lines.Count -le 1) {
        [void]$sb.AppendLine('(empty)')
    }
    else {
        $take = [Math]::Min($lines.Count, $MaxRowsPerCsv + 1)  # +1 for the header line
        [void]$sb.AppendLine('```csv')
        $lines[0..($take - 1)] | ForEach-Object { [void]$sb.AppendLine($_) }
        [void]$sb.AppendLine('```')
        if ($lines.Count -gt $take) { [void]$sb.AppendLine("(truncated: $($lines.Count - $take) more rows not shown)") }
    }
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('Write the assessment report now, following the rubric structure exactly.')

$userContent = $sb.ToString()
$approxTokens = [Math]::Round(($rubric.Length + $userContent.Length) / 4)
Write-Host ("  Prompt     : {0} CSVs, ~{1:N0} tokens (rough estimate)" -f $csvFiles.Count, $approxTokens)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safeLabel = $serverLabel -replace '[\\/:*?"<>|]', '_'

# ── Step 4: Dry run — write the prompt preview and stop ─────────────────────
if ($DryRun) {
    $previewPath = Join-Path $OutputRoot "prompt-preview-$safeLabel-$timestamp.txt"
    @("=== SYSTEM (rubric) ===", $rubric, "=== USER (healthcheck data) ===", $userContent) |
        Set-Content -LiteralPath $previewPath -Encoding UTF8
    Write-Host "  DryRun     : prompt written to $previewPath" -ForegroundColor Yellow
    Write-Host '               Review it, then re-run without -DryRun to call the API.' -ForegroundColor DarkGray
    return
}

# ── Step 5: Call the Claude API ─────────────────────────────────────────────
if (-not $env:ANTHROPIC_API_KEY) {
    throw "ANTHROPIC_API_KEY is not set. Set it, or use -DryRun to preview the prompt. Get a key at https://platform.claude.com/"
}
if (-not $ApiBaseUrl) { $ApiBaseUrl = if ($env:ANTHROPIC_BASE_URL) { $env:ANTHROPIC_BASE_URL } else { 'https://api.anthropic.com' } }
$apiUri = "$($ApiBaseUrl.TrimEnd('/'))/v1/messages"

$body = @{
    model      = $Model
    max_tokens = $MaxTokens
    system     = @(
        @{
            type          = 'text'
            text          = $rubric
            cache_control = @{ type = 'ephemeral' }
        }
    )
    messages   = @(
        @{ role = 'user'; content = $userContent }
    )
} | ConvertTo-Json -Depth 8

Write-Host "  Model      : $Model"
Write-Host '  Calling Claude API (this can take a few minutes)...' -ForegroundColor DarkGray

$response = Invoke-RestMethod -Method Post -Uri $apiUri `
    -Headers @{
        'x-api-key'         = $env:ANTHROPIC_API_KEY
        'anthropic-version' = '2023-06-01'
    } `
    -ContentType 'application/json; charset=utf-8' `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
    -TimeoutSec 600

if ($response.stop_reason -eq 'refusal') {
    throw "The model declined the request (stop_reason: refusal). Check stop_details: $($response.stop_details | ConvertTo-Json -Compress)"
}

$report = ($response.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
if (-not $report) { throw "API returned no text content (stop_reason: $($response.stop_reason))." }
if ($response.stop_reason -eq 'max_tokens') {
    Write-Host '  WARNING    : report hit the max_tokens cap and may be truncated - re-run with a higher -MaxTokens.' -ForegroundColor Yellow
}

# ── Step 6: Write the report ────────────────────────────────────────────────
$reportPath = Join-Path $OutputRoot "$safeLabel-$timestamp.md"
Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8

$u = $response.usage
$inputTok  = [long]$u.input_tokens + [long]$u.cache_creation_input_tokens + [long]$u.cache_read_input_tokens
$costUsd   = ([long]$u.input_tokens * 5 + [long]$u.cache_creation_input_tokens * 6.25 +
              [long]$u.cache_read_input_tokens * 0.5 + [long]$u.output_tokens * 25) / 1e6

Write-Host ''
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Report     : $reportPath" -ForegroundColor Green
Write-Host ("  Tokens     : {0:N0} in / {1:N0} out" -f $inputTok, [long]$u.output_tokens)
Write-Host ("  Est. cost  : `${0:N2} (at claude-opus-5 rates)" -f $costUsd)
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''
