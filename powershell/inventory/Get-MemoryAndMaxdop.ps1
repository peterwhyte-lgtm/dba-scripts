<#
.SYNOPSIS
Shows memory and MAXDOP related configuration for a server.
#>

param(
    [string]$SqlInstance = '.'
)
$ErrorActionPreference = 'Stop'

$connectionString = "Server=$SqlInstance;Database=master;Integrated Security=True;TrustServerCertificate=True"

$sql = @'
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN ('max degree of parallelism', 'max server memory (MB)', 'min server memory (MB)');
'@

Add-Type -AssemblyName System.Data
$conn = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
$da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$da.Fill($dt) | Out-Null
$conn.Close()

$dt | Format-Table -AutoSize



