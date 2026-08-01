<#
.SYNOPSIS
Reports last run outcome, duration, last message, and next scheduled run for all
DBA maintenance jobs (names starting with 'DBA - ').

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Quick health check on the maintenance job framework — confirm jobs are
               enabled, running on schedule, and not failing silently.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\maintenance\Get-MaintenanceJobStatus.ps1

.EXAMPLE
.\powershell\wrappers\maintenance\Get-MaintenanceJobStatus.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\maintenance\Get-MaintenanceJobStatus.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Checking DBA maintenance job status...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'msdb' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
