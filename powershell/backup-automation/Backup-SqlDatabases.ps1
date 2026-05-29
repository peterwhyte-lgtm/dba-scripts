<#
.SYNOPSIS
Backs up all user databases to a target folder.
#>

param(
    [string]$SqlInstance = '.',
    [string]$BackupPath = 'C:\\SQLBackups',
    [string]$BackupType = 'FULL'
)

if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlInstance)

foreach ($db in $server.Databases | Where-Object { $_.IsSystemObject -eq $false }) {
    $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
    $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
    $backup.Database = $db.Name
    $backup.BackupSetDescription = "Full backup of $($db.Name)"
    $backup.BackupSetName = "$($db.Name)-$(Get-Date -Format 'yyyyMMddHHmmss')"

    $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem("$BackupPath\\$($db.Name)_$($BackupType).bak", 'File')
    $backup.Devices.Add($device)

    Write-Host "Backing up $($db.Name) to $BackupPath" -ForegroundColor Cyan
    $backup.SqlBackup($server)
}



