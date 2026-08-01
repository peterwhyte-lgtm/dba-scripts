<#
.SYNOPSIS
Shows index usage statistics across all user databases — seeks, scans, lookups, and updates.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Spot unused indexes (write overhead, no reads) and scan-heavy tables (missing index candidates).

.DESCRIPTION
Wrapper for the Get-IndexUsageStats SQL query. Returns per-index usage since the last restart,
with a usage_pattern flag (WRITE_ONLY, SCAN_HEAVY, NORMAL) for quick triage.

WRITE_ONLY indexes update on every INSERT/UPDATE/DELETE but are never read — removal candidates.
SCAN_HEAVY tables may benefit from a more selective index.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-IndexUsageStats.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-IndexUsageStats.ps1 -OutputFormat Csv -OutputPath .\output-files\index-usage.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\indexes\Get-IndexUsageStats.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running index usage stats...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
