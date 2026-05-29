<#
.SYNOPSIS
Clears the repo output-files folder while preserving the folder structure.

.DESCRIPTION
Deletes generated CSV, log, and backup-review content from output-files.
Useful before rerunning the DBA review scripts or before archiving a session.

.PARAMETER Path
Optional output directory to clear. Defaults to .\output-files.

.PARAMETER WhatIf
Shows what would be removed without deleting anything.
#>

param(
    [string]$Path = (Join-Path $PSScriptRoot '..\output-files'),
    [switch]$WhatIf
)

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Output path not found: $Path"
}

$items = Get-ChildItem -LiteralPath $Path -Force -Recurse
if (-not $items) {
    Write-Host "No files found under $Path" -ForegroundColor Yellow
    return
}

if ($WhatIf) {
    $items | Select-Object -ExpandProperty FullName | Write-Host
    Write-Host "Would remove $($items.Count) item(s)." -ForegroundColor Cyan
    return
}

$items | Remove-Item -Force -Recurse -ErrorAction Stop
Write-Host "Cleared $($items.Count) item(s) from $Path" -ForegroundColor Green
