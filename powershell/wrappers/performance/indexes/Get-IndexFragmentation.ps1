<#
.SYNOPSIS
Reports top fragmented indexes across all user databases on the instance.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Identify indexes needing REBUILD or REORGANIZE across every user database.

.DESCRIPTION
Wrapper for sql\performance\indexes\Get-IndexFragmentation.sql. Scans all online user databases
in one pass using LIMITED mode and returns a single ranked result set.

Runtime is proportional to instance size — expect 30 seconds to several minutes on
larger servers. The QueryTimeout is set to 30 minutes to allow for this. Run off-peak
where possible.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the CSV output.

.EXAMPLE
.\run.ps1 Get-IndexFragmentation

.EXAMPLE
.\run.ps1 Get-IndexFragmentation -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\indexes\Get-IndexFragmentation.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Scanning index fragmentation across all user databases (this may take a few minutes)...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database master `
          -OutputFormat $OutputFormat -OutputPath $OutputPath -QueryTimeout 1800
