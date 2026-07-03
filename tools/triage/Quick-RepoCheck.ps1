<#
.SYNOPSIS
Performs a fast repo sanity check for the DBA scripts workspace.

.DESCRIPTION
Checks for the main folder layout and key helper scripts so you can quickly verify the repo is ready for DBA work.
#>
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$required = @(
  'sql',
  'powershell',
  'powershell\wrappers',
  'sql\collectors',
  'tools',
  'output-files'
)

$missing = foreach ($item in $required) {
  $path = Join-Path $repoRoot $item
  if (-not (Test-Path -LiteralPath $path)) { $path }
}

Write-Host "Repo sanity check" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor DarkCyan

if ($missing) {
  Write-Warning "Missing required paths:"
  $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
else {
  Write-Host "All core folders are present." -ForegroundColor Green
}

$helperChecks = @(
  'tools/triage/Show-RepoOverview.ps1',
  'tools/maintenance/Clear-OutputFiles.ps1',
  'tools/Run-Helper.ps1',
  'tools/local-sql/Invoke-RepoSql.ps1',
  'tools/local-sql/Invoke-LocalSql.ps1',
  'tools/local-sql/Test-SqlConnectivity.ps1',
  'tools/local-sql/Set-SqlConnection.ps1'
)

foreach ($entry in $helperChecks) {
  $path = Join-Path $repoRoot $entry
  if (Test-Path -LiteralPath $path) {
    Write-Host "OK  $entry" -ForegroundColor Green
  }
  else {
    Write-Host "MISSING $entry" -ForegroundColor Red
  }
}
