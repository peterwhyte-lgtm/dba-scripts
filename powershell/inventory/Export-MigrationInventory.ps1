<#
.SYNOPSIS
Exports a simple migration inventory for jobs, linked servers, and logins.

.DESCRIPTION
This helper is intended for pre-migration reviews. Passwords are not included.
#>

param(
    [string]$SqlInstance = '.',
    [string]$OutputPath = '.\\migration-inventory.csv'
)

Add-Type -AssemblyName System.Data

$cs = "Server=$SqlInstance;Database=master;Integrated Security=True;TrustServerCertificate=True"

$sql = @'
SELECT 'LOGIN' AS object_type, name, type_desc, is_disabled
FROM sys.server_principals
WHERE type IN ('S','U','G')
  AND name NOT LIKE '##%'
  AND name NOT LIKE 'NT AUTHORITY%'
  AND name NOT LIKE 'NT SERVICE%'

UNION ALL

SELECT 'LINKED_SERVER', name, product, provider
FROM sys.servers
WHERE is_linked = 1

UNION ALL

SELECT 'JOB', j.name, s.name, CAST(j.enabled AS varchar(10))
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.syslogins s ON j.owner_sid = s.sid;
'@

$conn = New-Object System.Data.SqlClient.SqlConnection($cs)
$cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
$da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
$da.Fill($dt) | Out-Null
$conn.Close()

$dt | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "Migration inventory exported to $OutputPath" -ForegroundColor Green



