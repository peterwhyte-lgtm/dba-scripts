<#
.SYNOPSIS
Lists the oldest file in each backup subfolder and flags folders older than a threshold.

.DESCRIPTION
Walks a backup root (local folder or UNC share) and reports the oldest file found
inside each subfolder. This is useful for reviewing backup media where folders are
named by server and backup date, such as:
  \\ServerName\Backups\ServerA\backup01feb2025
  \\ServerName\Backups\ServerB\backup02feb2025

.PARAMETER Path
Root folder to inspect. Accepts a local path (for example, E:\Backups) or UNC path.

.PARAMETER ThresholdDays
Age threshold in days for flagging old backup sets. Defaults to 31.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\inventory\Get-OldestBackupFolderFiles.ps1 -Path E:\Backups

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\powershell\inventory\Get-OldestBackupFolderFiles.ps1 -Path \\BackupMedia\Backups -ThresholdDays 45
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$ThresholdDays = 31
)

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Backup path not found: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$now = Get-Date

Write-Host "Backup age review for: $resolvedPath" -ForegroundColor Cyan
Write-Host "Flagging folders older than $ThresholdDays day(s)." -ForegroundColor DarkCyan
Write-Host "=" * 110 -ForegroundColor DarkCyan

$topFolders = Get-ChildItem -LiteralPath $resolvedPath -Directory -Force -ErrorAction SilentlyContinue

if (-not $topFolders) {
    Write-Host "No subfolders found under $resolvedPath." -ForegroundColor Yellow
    return
}

$scanFolders = foreach ($topFolder in $topFolders) {
    $childFolders = Get-ChildItem -LiteralPath $topFolder.FullName -Directory -Force -ErrorAction SilentlyContinue

    if ($childFolders) {
        $childFolders
    }
    else {
        $topFolder
    }
}

$rows = foreach ($folder in $scanFolders) {
    $files = Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -Force -ErrorAction SilentlyContinue

    if (-not $files) {
        continue
    }

    $oldestFile = $files | Sort-Object -Property LastWriteTimeUtc | Select-Object -First 1
    $ageDays = [math]::Floor(($now - $oldestFile.LastWriteTime).TotalDays)
    $status = if ($ageDays -ge $ThresholdDays) { 'OLD' } else { 'OK' }

    [PSCustomObject]@{
        Folder = $folder.FullName
        OldestFile = $oldestFile.FullName
        OldestFileDate = $oldestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        AgeDays = $ageDays
        FileCount = $files.Count
        Status = $status
    }
}

if (-not $rows) {
    Write-Host "No files found under $resolvedPath." -ForegroundColor Yellow
    return
}

$rows = $rows |
    Sort-Object -Property @{Expression = { $_.Status -eq 'OLD' }; Descending = $true }, @{Expression = 'AgeDays'; Descending = $true }, @{Expression = 'Folder' }

$oldRows = @($rows | Where-Object { $_.Status -eq 'OLD' })

if ($oldRows.Count -gt 0) {
    Write-Host ("Found {0} backup folder(s) older than {1} day(s)." -f $oldRows.Count, $ThresholdDays) -ForegroundColor Yellow
}
else {
    Write-Host "No backup folders exceeded the age threshold." -ForegroundColor Green
}

$rows |
    Format-Table -AutoSize -Property @{Label = 'Folder'; Expression = { $_.Folder } },
        @{Label = 'Oldest File'; Expression = { $_.OldestFile } },
        @{Label = 'Oldest Date'; Expression = { $_.OldestFileDate } },
        @{Label = 'Age (days)'; Expression = { $_.AgeDays } },
        @{Label = 'File Count'; Expression = { $_.FileCount } },
        @{Label = 'Status'; Expression = { if ($_.Status -eq 'OLD') { 'OLD' } else { 'OK' } } } |
    Out-String -Width 300 |
    Write-Host

Write-Host "Tip: use this output to identify backup sets that may be candidates for cleanup or retention review." -ForegroundColor DarkGray



