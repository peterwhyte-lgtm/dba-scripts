<#
.SYNOPSIS
Shows a friendly local disk space summary for the current machine.

.DESCRIPTION
Displays available drive space for all local fixed drives in a simple terminal-friendly format.
Useful for quick checks before creating large test databases.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Get-DiskSpaceSummary.ps1
#>

$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Sort-Object DeviceID

if (-not $drives) {
    Write-Host "No fixed local drives were found." -ForegroundColor Yellow
    return
}

Write-Host "Local Disk Space Summary" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor DarkCyan

foreach ($d in $drives) {
    $sizeGB = [math]::Round($d.Size / 1GB, 2)
    $freeGB = [math]::Round($d.FreeSpace / 1GB, 2)
    $usedGB = [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
    $pctUsed = if ($d.Size -gt 0) { [math]::Round((($d.Size - $d.FreeSpace) / $d.Size) * 100, 1) } else { 0 }

    Write-Host ("Drive {0}  Total: {1,8} GB  Used: {2,8} GB  Free: {3,8} GB  Used%: {4,5}%" -f $d.DeviceID, $sizeGB, $usedGB, $freeGB, $pctUsed) -ForegroundColor $(if ($pctUsed -ge 90) { 'Red' } elseif ($pctUsed -ge 75) { 'Yellow' } else { 'Green' })

    $barWidth = 30
    $usedBlocks = [int]([math]::Round(($pctUsed / 100) * $barWidth))
    $freeBlocks = $barWidth - $usedBlocks
    $bar = ('#' * $usedBlocks) + ('-' * $freeBlocks)
    Write-Host ("  [{0}]" -f $bar) -ForegroundColor DarkGray
}

Write-Host ("=" * 72) -ForegroundColor DarkCyan
Write-Host "Tip: use this before creating large test databases to confirm free disk space." -ForegroundColor DarkYellow
