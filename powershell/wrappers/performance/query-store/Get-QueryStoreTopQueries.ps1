<#
.SYNOPSIS
Top queries from Query Store by CPU, duration, execution count, or plan regressions.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Top queries from Query Store by CPU, duration, execution count, or plan regressions.

.DESCRIPTION
Wraps sql\performance\query-store\Get-QueryStoreTopQueries.sql. Query Store is per-database — pass
-Database with the name of the user database you want to analyse. Returns a status row
if Query Store is not enabled on the target database.

Sort mode is controlled by the @sort_by DECLARE inside the SQL script:
  cpu         — highest average CPU consumers
  duration    — highest average elapsed time
  executions  — most frequently executed queries
  regressions — queries where the current plan is significantly worse than the best
                observed plan for the same query (plan_count > 1, regression_factor > 1.5)

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Target database. Query Store data is per-database — this parameter is required for
meaningful results. Defaults to 'master' (which usually has no QS data).

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\performance\Get-QueryStoreTopQueries.ps1 -Database AdventureWorks

.EXAMPLE
.\powershell\wrappers\performance\Get-QueryStoreTopQueries.ps1 -ServerInstance PROD01\SQL2019 -Database MyAppDb -OutputFormat Csv
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
$sqlScript = Join-Path $repoRoot 'sql\performance\query-store\Get-QueryStoreTopQueries.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

if ($Database -eq 'master') {
    Write-Warning "Running against 'master' — Query Store data lives in user databases. Pass -Database <dbname> for meaningful results."
}

Write-Host "Running Query Store top queries against [$Database]..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
