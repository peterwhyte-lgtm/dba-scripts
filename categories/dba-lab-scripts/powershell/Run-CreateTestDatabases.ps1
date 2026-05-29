<#
.SYNOPSIS
Runs the local SSMS database-creation script for a small test batch.

.DESCRIPTION
Convenience wrapper around Invoke-LocalSql.ps1.
This script calls the SQL script in MSSQL/create-test-databases.sql using
SQLCMD mode through sqlcmd.exe, but keeps the default local instance and
Windows authentication.

.PARAMETER Count
Number of databases to create. Defaults to 10.

.PARAMETER Prefix
Database name prefix. Defaults to 'migdb'.

.PARAMETER StartIndex
Starting index. Defaults to 1.

.PARAMETER DataSizeMB
Initial data file size in MB. Defaults to 25.

.PARAMETER LogSizeMB
Initial log file size in MB. Defaults to 10.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\dba-lab-scripts\Run-CreateTestDatabases.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\dba-lab-scripts\Run-CreateTestDatabases.ps1 -Count 10 -Prefix demo
#>

param(
    [int]$Count = 10,
    [string]$Prefix = 'migdb',
    [int]$StartIndex = 1,
    [int]$DataSizeMB = 25,
    [int]$LogSizeMB = 10
)

$scriptPath = Join-Path $PSScriptRoot '..\..\..\MSSQL\create-test-databases.sql'

if (-not (Test-Path $scriptPath)) {
    throw "Script not found: $scriptPath"
}

$source = Get-Content -Path $scriptPath -Raw
$source = $source -replace "DECLARE @Count INT = 10;", "DECLARE @Count INT = $Count;"
$source = $source -replace "DECLARE @Prefix SYSNAME = N'migdb';", "DECLARE @Prefix SYSNAME = N'$Prefix';"
$source = $source -replace "DECLARE @StartIndex INT = 1;", "DECLARE @StartIndex INT = $StartIndex;"
$source = $source -replace "DECLARE @DataSizeMB INT = 25;", "DECLARE @DataSizeMB INT = $DataSizeMB;"
$source = $source -replace "DECLARE @LogSizeMB INT = 10;", "DECLARE @LogSizeMB INT = $LogSizeMB;"

$tempFile = Join-Path $env:TEMP ("create-test-databases-$([guid]::NewGuid().ToString('N')).sql")
Set-Content -Path $tempFile -Value $source -Encoding UTF8

Write-Host "Running local SQL script for $Count databases with prefix '$Prefix'" -ForegroundColor Cyan
$sqlcmd = @('sqlcmd', '-S', '.', '-C', '-b', '-r', '1', '-i', $tempFile)
Write-Host "Command: $($sqlcmd -join ' ')" -ForegroundColor DarkGray
$rawOutput = & $sqlcmd[0] $sqlcmd[1..($sqlcmd.Count - 1)] 2>&1
$rawOutput | ForEach-Object { Write-Host $_ }

if ($LASTEXITCODE -ne 0) {
    throw "sqlcmd failed with exit code $LASTEXITCODE. See the output above for the detailed SQL error lines."
}

Remove-Item $tempFile -ErrorAction SilentlyContinue
