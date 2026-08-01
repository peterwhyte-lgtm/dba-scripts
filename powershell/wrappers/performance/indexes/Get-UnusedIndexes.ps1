<#
.SYNOPSIS
Identifies non-clustered indexes with zero reads but non-zero write overhead since the last SQL Server restart.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Surface unused indexes that add write cost to every DML with no query benefit, as candidates for removal.

.DESCRIPTION
A convenience wrapper for the repo's unused index SQL query.
Run against a specific database using -Database. Usage stats reset on SQL Server restart —
allow at least several days of representative workload before trusting results.
Do NOT drop indexes without verifying across all environments.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Target database to analyse. Required — unused index stats are per-database.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-UnusedIndexes.ps1 -Database SalesDemo

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-UnusedIndexes.ps1 -ServerInstance PROD01 -Database MyApp -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\indexes\Get-UnusedIndexes.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host "Running unused index analysis against [$Database]..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
