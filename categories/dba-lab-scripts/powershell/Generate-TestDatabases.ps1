<#
.SYNOPSIS
Creates a batch of test databases with simple defaults.

.DESCRIPTION
Helpful for lab and simulation work. Uses the existing SQL script for DB creation.
#>

param(
    [string]$SqlInstance = '.',
    [int]$Count = 5,
    [string]$Prefix = 'testdb',
    [int]$DataSizeMB = 25,
    [int]$LogSizeMB = 10
)

$scriptPath = Join-Path $PSScriptRoot '..\\..\\..\\MSSQL\\create-test-databases.sql'
$script = Get-Content -LiteralPath $scriptPath -Raw

$script = $script -replace '@Count\s*=\s*\d+', "@Count = $Count"
$script = $script -replace "@Prefix\s*=\s*'[^']+'", "@Prefix = '$Prefix'"
$script = $script -replace '@DataSizeMB\s*=\s*\d+', "@DataSizeMB = $DataSizeMB"
$script = $script -replace '@LogSizeMB\s*=\s*\d+', "@LogSizeMB = $LogSizeMB"

Invoke-Sqlcmd -ServerInstance $SqlInstance -Database 'master' -Query $script -TrustServerCertificate -ErrorAction Stop
