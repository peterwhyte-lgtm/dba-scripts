<#
.SYNOPSIS
Runs a SQL script file against the local SQL Server instance.

.DESCRIPTION
A practical helper for testing and validating DBA scripts from the repo.
It uses Invoke-Sqlcmd when available and falls back to sqlcmd.exe.

.PARAMETER ScriptPath
Path to the .sql file to run.

.PARAMETER ServerInstance
SQL Server instance to connect to. Defaults to '.'.

.PARAMETER Database
Initial database for the session. Defaults to 'master'.

.PARAMETER Username
Optional SQL login for SQL authentication.

.PARAMETER Password
Optional password for SQL authentication.

.PARAMETER QueryTimeout
Command timeout in seconds. Defaults to 600.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\helpers\Invoke-SqlFile.ps1 -ScriptPath .\categories\performance-troubleshooting\sql\Get-BlockingSessions.sql

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\helpers\Invoke-SqlFile.ps1 -ScriptPath .\categories\configuration-and-environment\sql\Get-InstanceConfigurationSnapshot.sql -Database master

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\helpers\Invoke-SqlFile.ps1 -ScriptPath .\categories\dba-lab-scripts\sql\New-TestDatabases.sql -ServerInstance . -Database master
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [string]$Username,
    [string]$Password,
    [int]$QueryTimeout = 600,
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "SQL script not found: $ScriptPath"
}

Write-Host "Running SQL script: $ScriptPath" -ForegroundColor Cyan
Write-Host "Server: $ServerInstance | Database: $Database" -ForegroundColor DarkCyan

& (Join-Path $PSScriptRoot 'local-sql\Invoke-RepoSql.ps1') `
    -ScriptPath $ScriptPath `
    -ServerInstance $ServerInstance `
    -Database $Database `
    -Username $Username `
    -Password $Password `
    -QueryTimeout $QueryTimeout `
    -OutputFormat $OutputFormat `
    -OutputPath $OutputPath
