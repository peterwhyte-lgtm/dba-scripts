<#
.SYNOPSIS
Lists all databases with key properties and allocated file sizes.
Reads from system metadata only — fast, no per-database scan.
Data and log sizes reflect allocated file space, not space used.
Run Get-DatabaseSizesAndFreeSpace for used vs free breakdown.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Quick inventory of all databases on the instance with state, recovery
               model, owner, and file sizes. Complement with Get-DatabaseSizesAndFreeSpace
               for used/free breakdown.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\monitoring\Get-Databases.ps1

.EXAMPLE
.\powershell\wrappers\monitoring\Get-Databases.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\inventory\Get-Databases.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Retrieving database inventory...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
