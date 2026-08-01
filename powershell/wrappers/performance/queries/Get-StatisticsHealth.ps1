<#
.SYNOPSIS
Identifies stale, low-sample, and never-updated statistics in a user database.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Identifies stale, low-sample, and never-updated statistics in the current database.

.DESCRIPTION
Wraps sql\performance\queries\Get-StatisticsHealth.sql. Statistics are per-database — pass
-Database with the name of the user database you want to analyse.

Health statuses returned:
  NEVER_UPDATED       — statistics object has never been updated (no histogram)
  STALE_THRESHOLD_MET — modification_counter has exceeded the dynamic threshold
                        (SQRT(1000 * rows)) — auto-update would trigger on next use
  LOW_SAMPLE_RATE     — last update used < 10% sample on a table > 10k rows
                        — cardinality estimates may be inaccurate
  APPROACHING_STALE   — > 10% of rows modified since last update, threshold not yet met
  AGED                — not updated in @stale_days days and has modifications pending
  OK                  — within thresholds

Each row includes the UPDATE STATISTICS ... WITH FULLSCAN command for direct copy-paste.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Target database. Statistics data is per-database. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\performance\Get-StatisticsHealth.ps1 -Database AdventureWorks

.EXAMPLE
.\powershell\wrappers\performance\Get-StatisticsHealth.ps1 -ServerInstance PROD01\SQL2019 -Database MyAppDb -OutputFormat Csv
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
$sqlScript = Join-Path $repoRoot 'sql\performance\queries\Get-StatisticsHealth.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

if ($Database -eq 'master') {
    Write-Warning "Running against 'master' — statistics analysis is most useful against user databases. Pass -Database <dbname> for meaningful results."
}

Write-Host "Running statistics health check against [$Database]..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
