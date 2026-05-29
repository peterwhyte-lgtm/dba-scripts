<#
.SYNOPSIS
Reports index fragmentation for a database.
#>

param(
    [string]$SqlInstance = '.',
    [string]$DatabaseName = 'master'
)

$connectionString = "Server=$SqlInstance;Database=$DatabaseName;Integrated Security=True;TrustServerCertificate=True"

$sql = @'
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    ips.fragment_count,
    ips.avg_fragment_size_in_pages
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables t ON i.object_id = t.object_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE i.name IS NOT NULL
  AND ips.avg_fragmentation_in_percent >= 5
ORDER BY ips.avg_fragmentation_in_percent DESC;
'@

Add-Type -AssemblyName System.Data
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$command = New-Object System.Data.SqlClient.SqlCommand($sql, $connection)
$connection.Open()
$reader = $command.ExecuteReader()
$results = New-Object System.Collections.Generic.List[object]

while ($reader.Read()) {
    $results.Add([PSCustomObject]@{
        SchemaName = [string]$reader['SchemaName']
        TableName = [string]$reader['TableName']
        IndexName = [string]$reader['IndexName']
        AvgFragmentationPct = [decimal]$reader['avg_fragmentation_in_percent']
        PageCount = [int]$reader['page_count']
        FragmentCount = [int]$reader['fragment_count']
        AvgFragmentSizeInPages = [int]$reader['avg_fragment_size_in_pages']
    })
}

$connection.Close()

$results | Format-Table -AutoSize



