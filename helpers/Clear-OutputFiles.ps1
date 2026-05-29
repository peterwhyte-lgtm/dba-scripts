<#
.SYNOPSIS
Clears the repo output-files folder while preserving the folder structure.

.DESCRIPTION
Deletes generated CSV, log, and backup-review content from output-files.
Useful before rerunning the DBA review scripts or before archiving a session.

.PARAMETER Path
Optional output directory to clear. Defaults to .\output-files.

.PARAMETER Mode
Controls the cleanup strategy:
  - all: removes all files and folders under the output root
  - age: removes only old backup-style files older than -BackupAgeDays

.PARAMETER BackupAgeDays
Age threshold in days for backup-style file cleanup when -Mode age is used. Defaults to 30.

.PARAMETER WhatIf
Shows what would be removed without deleting anything.
#>

param(
    [string]$Path = (Join-Path $PSScriptRoot '..\output-files'),
    [ValidateSet('all', 'age')]
    [string]$Mode = 'all',
    [int]$BackupAgeDays = 30,
    [switch]$WhatIf
)

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Output path not found: $Path"
}

if ($Mode -eq 'age') {
    $cutoff = (Get-Date).AddDays(-$BackupAgeDays)
    $items = Get-ChildItem -LiteralPath $Path -File -Recurse -Force |
        Where-Object {
            $_.Extension -in '.bak', '.bakup', '.trn' -and $_.LastWriteTime -lt $cutoff
        }

    if (-not $items) {
        Write-Host "No backup files older than $BackupAgeDays day(s) were found under $Path" -ForegroundColor Yellow
        return
    }

    if ($WhatIf) {
        $items | Select-Object -ExpandProperty FullName | Write-Host
        Write-Host "Would remove $($items.Count) backup file(s) older than $BackupAgeDays day(s)." -ForegroundColor Cyan
        return
    }

    $items | Remove-Item -Force -ErrorAction Stop
    Write-Host "Removed $($items.Count) backup file(s) older than $BackupAgeDays day(s) from $Path" -ForegroundColor Green
    return
}

$items = Get-ChildItem -LiteralPath $Path -Force -Recurse
if (-not $items) {
    Write-Host "No files found under $Path" -ForegroundColor Yellow
    return
}

if ($WhatIf) {
    $items | Select-Object -ExpandProperty FullName | Write-Host
    Write-Host "Would remove $($items.Count) item(s) from $Path." -ForegroundColor Cyan
    return
}

$items | Remove-Item -Force -Recurse -ErrorAction Stop
Write-Host "Cleared $($items.Count) item(s) from $Path" -ForegroundColor Green
