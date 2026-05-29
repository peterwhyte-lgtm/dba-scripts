<#
.SYNOPSIS
Restores all user databases from backup files in a folder.

.DESCRIPTION
Simple DR and migration helper for restoring databases from a known backup path.
Review the generated restore script first when possible.
#>

param(
    [string]$SqlInstance = '.',
    [string]$BackupFolder = 'C:\\SQLBackups',
    [switch]$Replace
)

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlInstance)

foreach ($db in $server.Databases | Where-Object { $_.IsSystemObject -eq $false }) {
    $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
    $restore.Database = $db.Name
    $restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Database
    $restore.Devices.AddDevice("$BackupFolder\\$($db.Name)_FULL.bak", 'File')

    if ($Replace) {
        $restore.ReplaceDatabase = $true
    }

    Write-Host "Restoring $($db.Name) from $BackupFolder" -ForegroundColor Cyan
    $restore.SqlRestore($server)
}



