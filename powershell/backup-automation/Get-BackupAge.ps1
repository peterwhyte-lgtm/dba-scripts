<#
.SYNOPSIS
Reports the age of the latest backup for each user database.

.DESCRIPTION
Uses msdb backup history to show how old the most recent backup is for each user database.
This is useful for backup coverage checks, DR readiness, and weekly operational reviews.
#>

param(
    [string]$SqlInstance = '.',
    [string]$Database = 'master'
)

$ErrorActionPreference = 'Stop'

$connectionString = "Server=$SqlInstance;Database=$Database;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"

$sql = @'
SELECT
    d.name AS DatabaseName,
    MAX(bs.backup_finish_date) AS LastBackupTime,
    DATEDIFF(HOUR, MAX(bs.backup_finish_date), GETDATE()) AS HoursSinceBackup,
    DATEDIFF(DAY, MAX(bs.backup_finish_date), GETDATE()) AS DaysSinceBackup,
    MAX(CASE WHEN bs.type = 'D' THEN 'FULL' ELSE bs.type END) AS LastBackupType
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON bs.database_name = d.name
   AND bs.type IN ('D','I','L')
WHERE d.database_id > 4
GROUP BY d.name
ORDER BY DaysSinceBackup DESC, DatabaseName;
'@

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $connection.Open()

    $reader = $command.ExecuteReader()
    $rows = New-Object System.Collections.Generic.List[object]

    while ($reader.Read()) {
        $hours = if ($reader.IsDBNull($reader.GetOrdinal('HoursSinceBackup'))) { $null } else { [int]$reader['HoursSinceBackup'] }
        $days = if ($reader.IsDBNull($reader.GetOrdinal('DaysSinceBackup'))) { $null } else { [int]$reader['DaysSinceBackup'] }

        $rows.Add([pscustomobject]@{
            DatabaseName = $reader['DatabaseName']
            LastBackupTime = if ($reader.IsDBNull($reader.GetOrdinal('LastBackupTime'))) { $null } else { $reader['LastBackupTime'] }
            HoursSinceBackup = $hours
            DaysSinceBackup = $days
            LastBackupType = if ($reader.IsDBNull($reader.GetOrdinal('LastBackupType'))) { 'NONE' } else { $reader['LastBackupType'] }
        })
    }

    $rows | Format-Table -AutoSize
}
finally {
    if ($null -ne $connection -and $connection.State -eq 'Open') {
        $connection.Close()
    }
}



