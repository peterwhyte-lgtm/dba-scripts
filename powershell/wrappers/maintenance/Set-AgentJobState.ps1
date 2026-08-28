<#
.SYNOPSIS
Save, disable and restore SQL Agent job state as one operation, so a maintenance window can
quiet an instance and put it back exactly as it was.

.NOTES
ScriptType   : hybrid
TargetScope  : single server
RiskLevel    : HIGH
Purpose      : Disabling every Agent job is easy. Putting them back the way they were is the part
               people get wrong, because "they were mostly on" is not a rollback. This snapshots
               the enabled flag for every job first, and refuses to disable anything until it has.

Parameters are substituted into the SQL script's DECLARE block before execution, so the .sql file
stays runnable on its own in SSMS. The substitution is asserted: if a parameter line is not found
exactly once, this throws rather than silently running with defaults. That matters here, because
the default action is Report and a silent fall-through would look like a successful no-op.

.PARAMETER Action
Report (default), Save, Disable or Restore.

.PARAMETER StateDatabase
Utility database holding the snapshot table. Must exist. Must not be tempdb.

.PARAMETER ExcludeJobs
Comma separated exact job names to leave alone.

.PARAMETER ExcludeCategories
Comma separated job categories to leave alone. Defaults to log shipping and replication.

.PARAMETER StopRunning
Disable only: also stop jobs that are mid-run. A stopped job leaves its work half done.

.PARAMETER Force
Required for Disable. Without it, Disable refuses and tells you to run Report first.

.EXAMPLE
.\run.ps1 Set-AgentJobState -Action Report

.EXAMPLE
.\run.ps1 Set-AgentJobState -Action Save -StateDatabase DBA_Admin

.EXAMPLE
.\run.ps1 Set-AgentJobState -Action Disable -StateDatabase DBA_Admin -Force

.EXAMPLE
.\run.ps1 Set-AgentJobState -Action Restore -StateDatabase DBA_Admin
#>
param(
    [ValidateSet('Report', 'Save', 'Disable', 'Restore')]
    [string]$Action            = 'Report',
    [string]$ServerInstance    = '.',
    [string]$StateDatabase     = 'DBA_Admin',
    [string]$ExcludeJobs       = '',
    [string]$ExcludeCategories = 'Log Shipping,REPL-Distribution,REPL-LogReader,REPL-Merge,REPL-Snapshot',
    [switch]$StopRunning,
    [switch]$Force,
    [string]$Username,
    [string]$Password,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat      = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

if ($Action -eq 'Disable' -and -not $Force) {
    throw "Disable turns off every Agent job that is not excluded. Run -Action Report first to see exactly what would change, then re-run with -Force."
}

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\maintenance\Set-AgentJobState.sql'
if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

$sql = Get-Content -LiteralPath $sqlScript -Raw

# Substitute the DECLARE block. Each pattern must match exactly once or we stop: a missed
# substitution would run the script with its defaults and report a clean Report run.
$subs = @(
    @{ Name = 'Action';            Pattern = "(?m)^(DECLARE\s+\@Action\s+nvarchar\(10\)\s+=\s+)N'[^']*';";                Value = "N'$Action';" },
    @{ Name = 'StateDatabase';     Pattern = "(?m)^(DECLARE\s+\@StateDatabase\s+sysname\s+=\s+)N'[^']*';";                Value = "N'$StateDatabase';" },
    @{ Name = 'ExcludeCategories'; Pattern = "(?m)^(DECLARE\s+\@ExcludeCategories\s+nvarchar\(max\)\s+=\s+)N'[^']*';";    Value = "N'$ExcludeCategories';" },
    @{ Name = 'ExcludeJobs';       Pattern = "(?m)^(DECLARE\s+\@ExcludeJobs\s+nvarchar\(max\)\s+=\s+)N'[^']*';";          Value = "N'$ExcludeJobs';" },
    @{ Name = 'StopRunning';       Pattern = "(?m)^(DECLARE\s+\@StopRunning\s+bit\s+=\s+)[01];";                          Value = "$([int]$StopRunning.IsPresent);" }
)
foreach ($s in $subs) {
    $hits = ([regex]$s.Pattern).Matches($sql).Count
    if ($hits -ne 1) { throw "Parameter '$($s.Name)' matched $hits times in the SQL script, expected exactly 1. Refusing to run." }
    $sql = [regex]::Replace($sql, $s.Pattern, "`${1}$($s.Value)")
}

Write-Host ''
Write-Host "[agent-jobs] Action  : $Action" -ForegroundColor Cyan
Write-Host "[agent-jobs] Server  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[agent-jobs] State DB: $StateDatabase" -ForegroundColor Cyan
if ($Action -eq 'Disable') {
    Write-Host "[agent-jobs] Excluding categories: $ExcludeCategories" -ForegroundColor Yellow
    if ($ExcludeJobs) { Write-Host "[agent-jobs] Excluding jobs: $ExcludeJobs" -ForegroundColor Yellow }
}
Write-Host ''

$params = @{
    ServerInstance         = $ServerInstance
    Database               = 'master'
    Query                  = $sql
    QueryTimeout           = 300
    TrustServerCertificate = $true
    ErrorAction            = 'Stop'
    Verbose                = $true
}
if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }

$result = Invoke-Sqlcmd @params

if ($OutputFormat -eq 'Csv') {
    if ($OutputPath) { $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8; Write-Host "[agent-jobs] Written: $OutputPath" }
    else             { $result | ConvertTo-Csv -NoTypeInformation }
} else {
    $result | Format-Table -AutoSize
    if ($OutputPath) { $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8; Write-Host "[agent-jobs] Written: $OutputPath" }
}
