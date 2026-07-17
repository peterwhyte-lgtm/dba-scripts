<#
.SYNOPSIS
Reports why each database's transaction log cannot truncate and reuse space
(log_reuse_wait_desc), with recovery model, log size, and last log backup for context.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : First question to answer when a log file is full or won't shrink. LOG_BACKUP
               means the FULL/BULK_LOGGED log is waiting on a log backup; ACTIVE_TRANSACTION
               points at a long-running or orphaned transaction.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER OutputFormat
Output mode: 'Table' (default) or 'Csv'.

.PARAMETER OutputPath
Optional file path to save the output.

.EXAMPLE
.\powershell\wrappers\monitoring\disk-space\Get-LogReuseWaits.ps1

.EXAMPLE
.\powershell\wrappers\monitoring\disk-space\Get-LogReuseWaits.ps1 -ServerInstance PROD01 -OutputFormat Csv
#>

param(
    [string]$ServerInstance = '.',
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\monitoring\disk-space\Get-LogReuseWaits.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }
if (-not (Test-Path -LiteralPath $runner))    { throw "Runner not found: $runner" }

Write-Host 'Checking transaction log reuse waits...' -ForegroundColor Cyan
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database 'master' `
          -OutputFormat $OutputFormat -OutputPath $OutputPath
