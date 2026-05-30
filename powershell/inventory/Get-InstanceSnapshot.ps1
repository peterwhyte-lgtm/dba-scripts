<#
.SYNOPSIS
Captures a quick SQL Server instance configuration snapshot.

.DESCRIPTION
Useful for baseline reviews, migration planning, and incident prep.
#>

param(
    [string]$SqlInstance = '.'
)
$ErrorActionPreference = 'Stop'

$connectionString = "Server=$SqlInstance;Database=master;Integrated Security=True;TrustServerCertificate=True"

$sql = @'
SELECT name, value, value_in_use
FROM sys.configurations
ORDER BY name;
'@

Add-Type -AssemblyName System.Data
$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
$da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$da.Fill($dt) | Out-Null
$conn.Close()

$dt | Format-Table -AutoSize



