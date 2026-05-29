<#
.SYNOPSIS
Quickly run a SQL query against your local default SQL Server instance.

.DESCRIPTION
A small reusable helper for local SQL work.
- Uses Windows Authentication by default.
- Supports optional SQL Authentication.
- Accepts a simple query string or a predefined alias.
- Prints useful connection info (server name, edition, version, current database).

.PARAMETER Query
The SQL query to execute.

.PARAMETER ServerInstance
Optional server name. Defaults to the local default instance: '.'.

.PARAMETER Database
Optional database name. Defaults to the current default database for the login.

.PARAMETER Username
Optional SQL login for SQL authentication.

.PARAMETER Password
Optional password for SQL authentication. If provided, Username is required.

.PARAMETER Alias
Optional friendly alias to show in output (examples: 'local', 'test', 'migration').

.PARAMETER ShowDatabases
Optional switch to list databases after connection.

.PARAMETER AsCsv
Optional switch to output results as CSV text.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Invoke-LocalSql.ps1 -Query "SELECT @@SERVERNAME, @@VERSION;"

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Invoke-LocalSql.ps1 -Alias local -Query "SELECT name FROM sys.databases ORDER BY name;" -ShowDatabases

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Invoke-LocalSql.ps1 -Query "SELECT DB_NAME();" -Database master
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Query,

    [string]$ServerInstance = '.',
    [string]$Database,
    [string]$Username,
    [string]$Password,
    [string]$Alias = 'local',
    [switch]$ShowDatabases,
    [switch]$AsCsv
)

function Get-DbConnectionInfo {
    param(
        [string]$Server,
        [string]$DatabaseName,
        [string]$UserName,
        [string]$Password
    )

    $conn = New-Object System.Data.SqlClient.SqlConnection
    if ($UserName -and $Password) {
        $conn.ConnectionString = "Server=$Server;Database=$DatabaseName;User Id=$UserName;Password=$Password;Encrypt=False;TrustServerCertificate=True;"
    }
    else {
        $conn.ConnectionString = "Server=$Server;Database=$DatabaseName;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
    }

    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    DB_NAME() AS CurrentDatabase;
"@
        $info = $cmd.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($info)
        return [pscustomobject]@{
            ServerName = $table.Rows[0]['ServerName']
            MachineName = $table.Rows[0]['MachineName']
            InstanceName = $table.Rows[0]['InstanceName']
            Edition = $table.Rows[0]['Edition']
            ProductVersion = $table.Rows[0]['ProductVersion']
            CurrentDatabase = $table.Rows[0]['CurrentDatabase']
        }
    }
    finally {
        if ($conn.State -eq 'Open') { $conn.Close() }
    }
}

$authMode = if ($Username -and $Password) { 'SQL Authentication' } else { 'Windows Authentication' }

Write-Host "[local-sql] Alias: $Alias" -ForegroundColor Cyan
Write-Host "[local-sql] Server: $ServerInstance" -ForegroundColor Cyan
Write-Host "[local-sql] Auth: $authMode" -ForegroundColor Cyan

$info = Get-DbConnectionInfo -Server $ServerInstance -Database $Database -UserName $Username -Password $Password
Write-Host "[local-sql] ServerName: $($info.ServerName)" -ForegroundColor Green
Write-Host "[local-sql] Edition: $($info.Edition)" -ForegroundColor Green
Write-Host "[local-sql] Version: $($info.ProductVersion)" -ForegroundColor Green
Write-Host "[local-sql] CurrentDB: $($info.CurrentDatabase)" -ForegroundColor Green

if ($ShowDatabases) {
    Write-Host "`n[local-sql] Databases:" -ForegroundColor Yellow
    $dbQuery = "SELECT name, database_id FROM sys.databases ORDER BY name;"
}

$connectionString = if ($Username -and $Password) {
    "Server=$ServerInstance;Database=$Database;User Id=$Username;Password=$Password;Encrypt=False;TrustServerCertificate=True;"
} else {
    "Server=$ServerInstance;Database=$Database;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
}

$conn = New-Object System.Data.SqlClient.SqlConnection $connectionString
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = if ($ShowDatabases) { $dbQuery } else { $Query }
    $reader = $cmd.ExecuteReader()

    $table = New-Object System.Data.DataTable
    $table.Load($reader)

    if ($AsCsv) {
        $table | ConvertTo-Csv -NoTypeInformation
    }
    else {
        $table | Format-Table -AutoSize
    }
}
finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}
