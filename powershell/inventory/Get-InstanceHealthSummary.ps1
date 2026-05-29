param(
    [string]$SqlInstance = '.',
    [string]$Database = 'master'
)

$ErrorActionPreference = 'Stop'

try {
    $connectionString = "Server=$SqlInstance;Database=$Database;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()

    $sql = @'
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('InstanceName') AS InstanceName,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel;
'@

    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $reader = $command.ExecuteReader()
    $serverInfo = [ordered]@{}
    while ($reader.Read()) {
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $serverInfo[$reader.GetName($i)] = $reader.GetValue($i)
        }
    }
    $reader.Close()

    $sql = @'
SELECT
    name,
    value_in_use
FROM sys.configurations
WHERE name IN ('max degree of parallelism','max server memory (MB)','min server memory (MB)')
ORDER BY name;
'@
    $command.CommandText = $sql
    $configReader = $command.ExecuteReader()
    $configRows = New-Object System.Collections.Generic.List[object]
    while ($configReader.Read()) {
        $configRows.Add([pscustomobject]@{
            Name = $configReader['name']
            ValueInUse = $configReader['value_in_use']
        })
    }
    $configReader.Close()

    [pscustomobject]@{
        Server = $serverInfo
        Configuration = $configRows
    }
}
finally {
    if ($null -ne $connection -and $connection.State -eq 'Open') {
        $connection.Close()
    }
}



