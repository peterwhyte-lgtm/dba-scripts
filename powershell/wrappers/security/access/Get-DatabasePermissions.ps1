<#
.SYNOPSIS
Lists all explicit object- and schema-level permissions in the target database.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Audit who has been explicitly granted or denied access to specific
               objects. Run against each user database to get full coverage.

.DESCRIPTION
Wrapper for Get-DatabasePermissions.sql. Shows GRANT/DENY on objects, schemas, and
database-level permissions. Excludes built-in principals and database roles (roles
are covered by Get-DatabaseRoleMembers).

Must be run against the target database — pass -Database YourDatabase.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER Database
Target database. Defaults to 'master' — set this to a user database for useful results.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
pwsh -File .\powershell\wrappers\security\Get-DatabasePermissions.ps1 -Database Orders -OutputFormat Csv
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
$sqlScript = Join-Path $repoRoot 'sql\security\access\Get-DatabasePermissions.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

if ($Database -eq 'master') {
    Write-Host 'NOTE: Running against master — set -Database YourDatabase to audit a user database.' -ForegroundColor Yellow
}
Write-Host "Running database permissions audit against: $Database" -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
