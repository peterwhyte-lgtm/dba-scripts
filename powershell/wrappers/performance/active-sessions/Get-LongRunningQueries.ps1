<#
.SYNOPSIS
Runs the long-running query review script for the current SQL Server instance.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Run the long-running query SQL query from the repo and export results.

.DESCRIPTION
A convenience wrapper for the repo’s long-running query review SQL.
It delegates to the local SQL helper so you can run the same script from
this repo against your local or remote SQL Server instance.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-LongRunningQueries.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-LongRunningQueries.ps1 -ServerInstance . -Database master -OutputFormat Csv -OutputPath .\output-files\long-running-queries.csv
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\performance\active-sessions\Get-LongRunningQueries.sql'
$runner = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) {
    throw "Long-running query SQL script not found: $sqlScript"
}

if (-not (Test-Path -LiteralPath $runner)) {
    throw "Local SQL runner not found: $runner"
}

Write-Host 'Running long-running query review...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath



