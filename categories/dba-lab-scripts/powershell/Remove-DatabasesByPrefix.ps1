<#
.SYNOPSIS
Drops local SQL Server databases whose names start with the specified prefix.

.DESCRIPTION
Safe cleanup helper for local test/migration databases.
Uses Windows authentication by default and targets the local default instance.

.PARAMETER Prefix
Database name prefix to match. Defaults to 'migdb'.

.PARAMETER Confirm
Prompts for confirmation before dropping databases.

.PARAMETER Force
Skips the confirmation prompt.

.PARAMETER ServerInstance
Optional server name. Defaults to '.'.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Remove-DatabasesByPrefix.ps1 -Prefix migdb -Confirm

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Remove-DatabasesByPrefix.ps1 -Prefix migdb -Force
#>

param(
    [string]$Prefix = 'migdb',
    [string]$ServerInstance = '.',
    [switch]$Force,
    [switch]$Confirm
)

$useConfirm = $Confirm -and -not $Force

$connectionString = "Server=$ServerInstance;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;"
$conn = New-Object System.Data.SqlClient.SqlConnection $connectionString
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
SELECT name
FROM sys.databases
WHERE name LIKE '$Prefix%'
ORDER BY name;
"@

    $reader = $cmd.ExecuteReader()
    $table = New-Object System.Data.DataTable
    $table.Load($reader)

    if ($table.Rows.Count -eq 0) {
        Write-Host "No databases found with prefix '$Prefix'." -ForegroundColor Yellow
        return
    }

    Write-Host "Databases to drop:" -ForegroundColor Cyan
    foreach ($row in $table.Rows) {
        Write-Host "  - $($row['name'])"
    }

    if ($useConfirm) {
        $answer = Read-Host "Drop these databases? (y/N)"
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    }

    foreach ($row in $table.Rows) {
        $dbName = $row['name']
        Write-Host "Dropping database: $dbName" -ForegroundColor Yellow
        $drop = $conn.CreateCommand()
        $drop.CommandText = "ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbName];"
        [void]$drop.ExecuteNonQuery()
        Write-Host "Dropped: $dbName" -ForegroundColor Green
    }
}
finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}
