<#
.SYNOPSIS
Pre-upgrade readiness summary for SQL Server version upgrades — version info, compat level matrix,
configuration review, and database sizing for window planning.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Assess upgrade readiness across version, compat levels, and sizing. Complements
               Get-DeprecatedFeaturesInUse.ps1 (deprecated feature detail) and
               Invoke-PreMigrationAssessment.ps1 (full assessment suite).

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\migration\Get-VersionUpgradeReadiness.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\migration\Get-VersionUpgradeReadiness.ps1 -OutputFormat Csv -OutputPath .\output-files\upgrade-readiness.csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Get-VersionUpgradeReadiness.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Running version upgrade readiness assessment...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' -OutputFormat $OutputFormat -OutputPath $OutputPath
