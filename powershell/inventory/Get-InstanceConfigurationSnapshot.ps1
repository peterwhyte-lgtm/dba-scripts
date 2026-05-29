<#
.SYNOPSIS
Runs the instance configuration snapshot review query.
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\\..')
$sqlScript = Join-Path $repoRoot 'sql\\monitoring\\Get-InstanceConfigurationSnapshot.sql'
$runner = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

Write-Host 'Running instance configuration snapshot review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath



