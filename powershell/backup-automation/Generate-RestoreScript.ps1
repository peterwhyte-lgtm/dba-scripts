<#
.SYNOPSIS
Generates restore scripts for all user databases.

.DESCRIPTION
Creates a simple RESTORE DATABASE script that can be reviewed or copied into SSMS.
This is useful during DR testing and migration planning.
#>

param(
    [string]$SqlInstance = '.',
    [string]$BackupFolder = 'C:\\SQLBackups',
    [string]$OutputPath = '.\\restore-script.sql'
)
$ErrorActionPreference = 'Stop'

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlInstance)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('-- Generated restore script for all user databases')
$lines.Add('-- Review and adjust file paths as needed before execution.')
$lines.Add('')

foreach ($db in $server.Databases | Where-Object { $_.IsSystemObject -eq $false }) {
    $lines.Add("RESTORE DATABASE [$($db.Name)] FROM DISK = '$BackupFolder\\$($db.Name)_FULL.bak' WITH REPLACE, STATS = 5;")
    $lines.Add('')
}

Set-Content -Path $OutputPath -Value $lines
Write-Host "Restore script written to $OutputPath" -ForegroundColor Green



