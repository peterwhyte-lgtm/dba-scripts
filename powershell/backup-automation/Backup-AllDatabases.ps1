<#
.SYNOPSIS
Backs up every user database on the instance to a target folder.

.DESCRIPTION
Production-friendly backup helper for full backups with backup compression enabled.
Use this for routine backup validation or lab environment setup.
#>

param(
    [string]$SqlInstance = '.',
    [string]$BackupPath = 'C:\\SQLBackups',
    [switch]$Compress,
    [switch]$CopyOnly
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlInstance)

foreach ($db in $server.Databases | Where-Object { $_.IsSystemObject -eq $false }) {
    $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
    $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
    $backup.Database = $db.Name
    $backup.BackupSetName = "$($db.Name)-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $backup.BackupSetDescription = "Full backup of $($db.Name)"

    if ($Compress) {
        $backup.CompressionOption = [Microsoft.SqlServer.Management.Smo.BackupCompressionOptions]::On
    }

    if ($CopyOnly) {
        $backup.CopyOnly = $true
    }

    $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem("$BackupPath\\$($db.Name)_FULL.bak", 'File')
    $backup.Devices.Add($device)

    Write-Host "Backing up $($db.Name) to $BackupPath" -ForegroundColor Cyan
    $backup.SqlBackup($server)
}



