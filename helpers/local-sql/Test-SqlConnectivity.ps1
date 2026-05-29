<#
.SYNOPSIS
Tests local SQL connectivity and prints the server details that matter for DBA work.

.DESCRIPTION
This helper verifies that the configured SQL Server instance is reachable and reports the
server name, edition, product version, and current database context.
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [string]$Username,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

function Get-ConnectionString {
    param([string]$Server,[string]$DatabaseName,[string]$User,[string]$Pass)

    if ($User -and $Pass) {
        return "Server=$Server;Database=$DatabaseName;User Id=$User;Password=$Pass;Encrypt=False;TrustServerCertificate=True;"
    }

    return "Server=$Server;Database=$DatabaseName;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
}

$connectionString = Get-ConnectionString -Server $ServerInstance -DatabaseName $Database -User $Username -Pass $Password
$authMode = if ($Username -and $Password) { 'SQL Authentication' } else { 'Windows Authentication' }

Write-Host "[sql-connect] ServerInstance: $ServerInstance" -ForegroundColor Cyan
Write-Host "[sql-connect] Database: $Database" -ForegroundColor Cyan
Write-Host "[sql-connect] Auth: $authMode" -ForegroundColor Cyan

$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
try {
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @'
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    DB_NAME() AS CurrentDatabase;
'@

    $reader = $cmd.ExecuteReader()
    $table = New-Object System.Data.DataTable
    $table.Load($reader)
    $row = $table.Rows[0]

    Write-Host "[sql-connect] ServerName: $($row['ServerName'])" -ForegroundColor Green
    Write-Host "[sql-connect] MachineName: $($row['MachineName'])" -ForegroundColor Green
    Write-Host "[sql-connect] Edition: $($row['Edition'])" -ForegroundColor Green
    Write-Host "[sql-connect] ProductVersion: $($row['ProductVersion'])" -ForegroundColor Green
    Write-Host "[sql-connect] CurrentDatabase: $($row['CurrentDatabase'])" -ForegroundColor Green
    Write-Host "[sql-connect] Status: OK" -ForegroundColor Green
}
catch {
    Write-Error "Connection failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}
