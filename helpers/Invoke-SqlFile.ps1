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
powershell -ExecutionPolicy Bypass -File .\powershell\helpers\Invoke-SqlFile.ps1 -ScriptPath .\sql\performance-troubleshooting\Get-LongRunningQueries.sql

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\helpers\Invoke-SqlFile.ps1 -ScriptPath .\sql\configuration-and-environment\Get-InstanceConfigurationSnapshot.sql -Database master

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\helpers\Invoke-SqlFile.ps1 -ScriptPath .\MSSQL\create-test-databases.sql -ServerInstance . -Database master
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [string]$Username,
    [string]$Password,
    [int]$QueryTimeout = 600
)

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "SQL script not found: $ScriptPath"
}

Write-Host "Running SQL script: $ScriptPath" -ForegroundColor Cyan
Write-Host "Server: $ServerInstance | Database: $Database" -ForegroundColor DarkCyan

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue

if ($invokeSqlcmd) {
    $params = @{
        ServerInstance = $ServerInstance
        Database       = $Database
        InputFile      = $ScriptPath
        QueryTimeout   = $QueryTimeout
        ErrorAction    = 'Stop'
    }

    if ($Username -and $Password) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }

    Write-Host "Using Invoke-Sqlcmd" -ForegroundColor Green
    Invoke-Sqlcmd @params
    return
}

if ($sqlcmd) {
    $args = @('-S', $ServerInstance, '-d', $Database, '-i', $ScriptPath, '-b', '-r', '1', '-t', $QueryTimeout)

    if ($Username -and $Password) {
        $args += @('-U', $Username, '-P', $Password)
    }
    else {
        $args += '-E'
    }

    Write-Host "Using sqlcmd.exe" -ForegroundColor Green
    Write-Host "Command: sqlcmd.exe $($args -join ' ')" -ForegroundColor DarkGray

    & $sqlcmd.Source @args
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd.exe failed with exit code $LASTEXITCODE"
    }
    return
}

throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe was found on PATH.'
