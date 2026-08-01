<#
.SYNOPSIS
Generates ALTER INDEX REBUILD / REORGANIZE statements for fragmented indexes
across all online user databases.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Read-only scan of index fragmentation. Returns a maintenance_statement
               column with ready-to-run DDL. Review the output and execute the
               statements in a maintenance window — nothing is executed by this script.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\maintenance\Generate-IndexMaintenanceScript.ps1

.EXAMPLE
.\powershell\wrappers\maintenance\Generate-IndexMaintenanceScript.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\maintenance\Generate-IndexMaintenanceScript.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Scanning index fragmentation and generating maintenance statements...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
