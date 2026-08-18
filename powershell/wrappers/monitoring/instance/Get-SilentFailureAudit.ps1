<#
.SYNOPSIS
Finds the SQL Server problems that never raise an error, in one pass across the whole instance.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Surface state and drift that produces no error, no failed job and no error-log entry:
               integrity gaps, a broken backup chain, untrusted constraints, disabled indexes,
               orphaned users, Agent steps that continue past failure, and security posture.

.DESCRIPTION
A convenience wrapper for the repo's silent-failure audit SQL query.

Every check in it is picked on one rule: SQL Server does not complain about it. Nothing here fires
an alert, so nothing here is on anyone's dashboard, which is exactly why it is worth running
deliberately when you take over an instance and on a schedule afterwards.

Returns one row per finding: severity, area, database, what is true right now, why nothing told you,
and the next action. Databases it could not read are reported as their own INFO rows rather than
skipped silently, because an unchecked database and a clean one look identical otherwise.

Complements Get-InstanceConfigurationScore.ps1, which scores sp_configure-level settings. This one
is about state rather than configuration.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\monitoring\instance\Get-SilentFailureAudit.ps1 -ServerInstance PROD01

.EXAMPLE
# Keep the result with the handover pack
.\powershell\wrappers\monitoring\instance\Get-SilentFailureAudit.ps1 -ServerInstance PROD01 -OutputFormat Csv -OutputPath .\output-files\reviews\prod01-silent-failures.csv
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
$sqlScript = Join-Path $repoRoot 'sql\monitoring\instance\Get-SilentFailureAudit.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host "Auditing [$ServerInstance] for failures that raise no error..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
