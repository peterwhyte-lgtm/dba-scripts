<#
.SYNOPSIS
Shows the largest folders on a drive, sorted by size.

.DESCRIPTION
Scans a drive letter (default: C:) and reports the biggest folders by total size.
Useful for quickly finding where disk space is being used.

.PARAMETER DriveLetter
Drive to inspect. Defaults to 'C'.

.PARAMETER Top
Number of folders to show. Defaults to 10.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Get-LargestFolders.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\PowerShell\Get-LargestFolders.ps1 -DriveLetter D -Top 20
#>

param(
    [string]$DriveLetter = 'C',
    [int]$Top = 10,
    [switch]$IncludeSystemFolders,
    [switch]$IncludeLargestFiles
)

$drive = "$DriveLetter`:\"

if (-not (Test-Path $drive)) {
    throw "Drive not found: $drive"
}

Write-Host "Scanning $drive for likely cleanup targets..." -ForegroundColor Cyan
Write-Host "(This may take a moment while size data is collected.)" -ForegroundColor DarkYellow

$candidateFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($IncludeSystemFolders) {
    Get-ChildItem -Path $drive -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$candidateFolders.Add($_.FullName) }
}
else {
    foreach ($p in @('ProgramData', 'Temp', 'tmp', 'Windows\Temp')) {
        $full = Join-Path $drive $p
        if (Test-Path -LiteralPath $full -ErrorAction SilentlyContinue) {
            [void]$candidateFolders.Add($full)
        }
    }
}

if (Test-Path (Join-Path $drive 'Users')) {
    Get-ChildItem -Path (Join-Path $drive 'Users') -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            foreach ($sub in @('Downloads', 'AppData', 'OneDrive')) {
                $p = Join-Path $_.FullName $sub
                try {
                    if (Test-Path -LiteralPath $p -ErrorAction Stop) {
                        [void]$candidateFolders.Add($p)
                    }
                }
                catch { }
            }
        }
}

function Get-FolderSizeGB([string]$Path) {
    try {
        $sum = 0
        $items = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) }

        if ($items) {
            $sum = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }

        return [math]::Round(($sum / 1GB), 2)
    }
    catch {
        return 0
    }
}

$allCandidates = $candidateFolders | Sort-Object -Unique
$total = $allCandidates.Count
$processed = 0

$folders = foreach ($path in $allCandidates) {
    $processed++
    $pct = [math]::Round(($processed / $total) * 100, 0)
    Write-Progress -Activity "Scanning folders" -Status "Processing $processed of $total" -PercentComplete $pct

    try {
        $sizeGB = Get-FolderSizeGB -Path $path
        [PSCustomObject]@{
            Folder = $path
            SizeGB = $sizeGB
            Priority = if ($path -match '\\Users\\.*\\(Downloads|AppData|OneDrive)$' -or $path -match '\\(Temp|tmp)\\?$' -or $path -match '\\Users\\[^\\]+$') { 'Yes' } else { 'No' }
        }
    }
    catch {
        [PSCustomObject]@{
            Folder = $path
            SizeGB = 0
            Priority = 'No'
        }
    }
}

$folders = $folders |
    Where-Object { ($_.Priority -eq 'Yes' -and $_.SizeGB -ge 0.05) -or $_.SizeGB -ge 1 } |
    Sort-Object -Property Priority, SizeGB -Descending |
    Select-Object -First $Top

Write-Progress -Activity "Scanning folders" -Completed

if (-not $folders) {
    Write-Host "No folders found to measure on $drive." -ForegroundColor Yellow
    return
}

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'"
$freeGB = [math]::Round(($disk.FreeSpace / 1GB), 2)
$totalGB = [math]::Round(($disk.Size / 1GB), 2)
$usedPct = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }

$topTotalGB = ($folders | Measure-Object -Property SizeGB -Sum).Sum
$topPctOfDrive = if ($totalGB -gt 0) { [math]::Round(($topTotalGB / $totalGB) * 100, 1) } else { 0 }

Write-Host "Top $Top likely cleanup targets on $drive" -ForegroundColor Green
Write-Host ("Drive usage: {0} GB used of {1} GB total ({2}% used)" -f ([math]::Round(($totalGB - $freeGB), 2)), $totalGB, $usedPct) -ForegroundColor Yellow
Write-Host ("Top candidates account for {0:N2} GB ({1}% of the drive)" -f $topTotalGB, $topPctOfDrive) -ForegroundColor Yellow
Write-Host ("=" * 100) -ForegroundColor DarkCyan
$folders | Format-Table -AutoSize -Property @{Label='Folder';Expression={$_.Folder}}, @{Label='Size GB';Expression={'{0:N2}' -f $_.SizeGB}}, @{Label='Share %';Expression={if ($topTotalGB -gt 0) { [math]::Round(($_.SizeGB / $topTotalGB) * 100, 1) } else { 0 }}} | Out-String | Write-Host

$subfolderSummary = @()
foreach ($item in $folders | Where-Object { $_.SizeGB -ge 5 } | Select-Object -First 3) {
    $subs = Get-ChildItem -LiteralPath $item.Folder -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            $sizeGB = Get-FolderSizeGB -Path $_.FullName
            [PSCustomObject]@{
                Parent = $item.Folder
                SubFolder = $_.FullName
                SizeGB = $sizeGB
            }
        } |
        Where-Object { $_.SizeGB -ge 0.1 } |
        Sort-Object -Property SizeGB -Descending |
        Select-Object -First 5

    if ($subs) { $subfolderSummary += $subs }
}

if ($subfolderSummary.Count -gt 0) {
    Write-Host "`nTop subfolders driving the largest candidates:" -ForegroundColor Yellow
    $subfolderSummary |
        Format-Table -AutoSize -Property Parent, SubFolder, @{Label='Size GB';Expression={'{0:N2}' -f $_.SizeGB}} | Out-String | Write-Host
}

if ($IncludeLargestFiles) {
    Write-Host "Largest files on the same drive:" -ForegroundColor Yellow
    Get-ChildItem -Path $drive -File -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property Length -Descending |
        Select-Object -First 5 |
        Format-Table -AutoSize -Property FullName, @{Label='Size GB';Expression={'{0:N2}' -f ($_.Length / 1GB)}} | Out-String | Write-Host
}

Write-Host ("=" * 100) -ForegroundColor DarkCyan
