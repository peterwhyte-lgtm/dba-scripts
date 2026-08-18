<#
.SYNOPSIS
Produces one comparable fingerprint row per login, for diffing a source server against a target after a migration.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Compare login ATTRIBUTES (SID, disabled state, deny connect, default database and
               language, password policy, password hash fingerprint, server roles) between two
               servers, rather than only counting logins.

.DESCRIPTION
A convenience wrapper for the repo's login parity SQL query.

Get-PostMigrationValidation.ps1 compares counts. A count check passes while every login on the
target is enabled, mapped to a default database that does not exist, and carrying a fresh SID,
because the number of logins is still the same. This script compares the attributes themselves.

Run on BOTH the source and target server with -OutputFormat Csv, then diff the two files.
Every row should match. The usual real differences are:
  sid_hex          - a login recreated by name got a new SID; every database user mapped to it
                     is now orphaned
  is_disabled      - CREATE LOGIN always produces an ENABLED login, so a disabled account comes
                     back live with its original password still valid
  default_db_state - reads MISSING when the login's default database does not exist on the target,
                     which presents as an authentication failure
  password_hash_id - differs when the password was re-typed instead of scripted as HASHED. Note
                     the hash is salted, so the same password typed twice hashes differently

It never writes. Nothing in it changes a login.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'. Use 'Csv' on both servers, then diff.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
# Run on source
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\migration\Get-LoginMigrationParity.ps1 -ServerInstance SOURCE -OutputFormat Csv -OutputPath .\output-files\migration\source-logins.csv

.EXAMPLE
# Run on target, then diff the two CSVs
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\migration\Get-LoginMigrationParity.ps1 -ServerInstance TARGET -OutputFormat Csv -OutputPath .\output-files\migration\target-logins.csv
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

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Get-LoginMigrationParity.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "Script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host "Collecting login parity fingerprint from [$ServerInstance]..." -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
