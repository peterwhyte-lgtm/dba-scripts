<#
.SYNOPSIS
Runs the database size and free-space review SQL script through the repo helper.

.DESCRIPTION
Convenience wrapper for validating the storage-capacity script from PowerShell.
Uses the current helper at helpers/local-sql/Invoke-SqlFile.ps1.

.PARAMETER ServerInstance
SQL Server instance to connect to. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER QueryTimeout
Command timeout in seconds. Defaults to 600.
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [int]$QueryTimeout = 600
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..')
$helperPath = Join-Path $repoRoot 'helpers\local-sql\Invoke-SqlFile.ps1'
$sqlScriptPath = Join-Path $repoRoot 'sql\monitoring\Get-DatabaseSizesAndFreeSpace.sql'

if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Helper script not found: $helperPath"
}

if (-not (Test-Path -LiteralPath $sqlScriptPath)) {
    throw "SQL script not found: $sqlScriptPath"
}

Write-Host "Running database size and free-space review..." -ForegroundColor Cyan
Write-Host "Helper: $helperPath" -ForegroundColor DarkCyan
Write-Host "SQL Script: $sqlScriptPath" -ForegroundColor DarkCyan

& $helperPath -ScriptPath $sqlScriptPath -ServerInstance $ServerInstance -Database $Database -QueryTimeout $QueryTimeout
