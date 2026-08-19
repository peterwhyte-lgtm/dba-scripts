<#
.SYNOPSIS
Projects days-to-full for databases and drives from collector historical data.

.DESCRIPTION
Reads database-growth and disk-space collector CSVs and computes a linear growth rate
over the last 30/60/90 days per database and per drive. Projects how many days until
the drive fills at the current rate. Flags anything projected to fill within 30 days.

Requires the database-growth and storage-io collectors to have been running for at
least 14 days to produce a meaningful projection.

.NOTES
ScriptType  : hybrid
TargetScope : single server
RiskLevel   : SAFE

.EXAMPLE
.\Get-CapacityProjection.ps1

.\Get-CapacityProjection.ps1 -LookbackDays 60 -OutputFormat Csv
#>

param(
    [int]$LookbackDays    = 30,
    [int]$WarnDaysToFull  = 30,
    [int]$CritDaysToFull  = 14,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$collectDir = Join-Path $repoRoot 'output-files\collectors'

function Get-LinearGrowthRate {
    param([double[]]$Sizes, [int[]]$DayOffsets)
    # Simple linear regression: slope = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
    $n   = $Sizes.Count
    if ($n -lt 2) { return 0 }
    $sumX   = ($DayOffsets | Measure-Object -Sum).Sum
    $sumY   = ($Sizes      | Measure-Object -Sum).Sum
    $sumXY  = 0; $sumX2 = 0
    for ($i = 0; $i -lt $n; $i++) {
        $sumXY += $DayOffsets[$i] * $Sizes[$i]
        $sumX2 += $DayOffsets[$i] * $DayOffsets[$i]
    }
    $denom = $n * $sumX2 - $sumX * $sumX
    if ($denom -eq 0) { return 0 }
    return ($n * $sumXY - $sumX * $sumY) / $denom
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$cutoff  = (Get-Date).AddDays(-$LookbackDays)

# ── Database growth projection ─────────────────────────────────────────────────
$dbGrowthDir = Join-Path $collectDir 'database-growth'
if (Test-Path $dbGrowthDir) {
    $csvFiles = Get-ChildItem $dbGrowthDir -Filter '*.csv' | Sort-Object LastWriteTime

    if ($csvFiles) {
        $allRows = $csvFiles | ForEach-Object { Import-Csv $_.FullName } |
                   Where-Object {
                       $_.collected_at -and
                       [datetime]::TryParse($_.collected_at, [ref]$null) -and
                       [datetime]$_.collected_at -ge $cutoff
                   }

        $dbGroups = $allRows | Group-Object database_name

        foreach ($grp in $dbGroups) {
            $pts = $grp.Group |
                   Sort-Object { [datetime]$_.collected_at } |
                   Select-Object collected_at,
                       @{n='size_mb'; e={ [double]((@($_.data_size_mb, $_.total_size_mb, 0) | Where-Object { $null -ne $_ })[0]) }}

            if ($pts.Count -lt 3) { continue }

            $refDate    = [datetime]$pts[0].collected_at
            $dayOffsets = $pts | ForEach-Object { ([datetime]$_.collected_at - $refDate).TotalDays }
            $sizes      = $pts | ForEach-Object { $_.size_mb }

            $ratePerDay  = Get-LinearGrowthRate -Sizes $sizes -DayOffsets $dayOffsets
            $latestSize  = $sizes[-1]
            $daysToFull  = $null
            $status      = 'OK'

            if ($ratePerDay -le 0) {
                $status = 'OK - stable or shrinking'
            } else {
                # Days until some threshold — use disk free if available, else just show rate
                $status = 'INFO - growing at ' + [math]::Round($ratePerDay, 1) + ' MB/day'
                if ($ratePerDay -gt 0) {
                    $daysToFull = $null  # set per-drive below
                }
            }

            $results.Add([PSCustomObject]@{
                type             = 'DATABASE'
                name             = $grp.Name
                drive            = $null
                current_size_mb  = [math]::Round($latestSize, 1)
                free_mb          = $null
                growth_mb_per_day = [math]::Round($ratePerDay, 2)
                data_points      = $pts.Count
                lookback_days    = $LookbackDays
                days_to_full     = $null
                status           = $status
            })
        }
    }
    else {
        Write-Warning "No database-growth collector CSVs found in $dbGrowthDir"
    }
}
else {
    Write-Warning "Collector directory not found: $dbGrowthDir - install the DatabaseGrowth collector job first (sql\collectors\Generate-CollectorJob-DatabaseGrowth.sql)."
}

# ── Disk space projection ──────────────────────────────────────────────────────
$diskDir = Join-Path $collectDir 'storage-io'
if (Test-Path $diskDir) {
    $csvFiles = Get-ChildItem $diskDir -Filter '*.csv' | Sort-Object LastWriteTime

    if ($csvFiles) {
        $allRows = $csvFiles | ForEach-Object { Import-Csv $_.FullName } |
                   Where-Object {
                       $_.collected_at -and
                       [datetime]::TryParse($_.collected_at, [ref]$null) -and
                       [datetime]$_.collected_at -ge $cutoff
                   }

        # Group by drive letter or volume name
        $driveCol = if ($allRows | Select-Object -First 1 | Get-Member -Name 'drive_letter') { 'drive_letter' }
                    elseif ($allRows | Select-Object -First 1 | Get-Member -Name 'volume')    { 'volume' }
                    else { 'logical_disk' }

        $driveGroups = $allRows | Where-Object { $_.$driveCol } | Group-Object $driveCol

        foreach ($grp in $driveGroups) {
            $pts = $grp.Group |
                   Sort-Object { [datetime]$_.collected_at } |
                   Select-Object collected_at,
                       @{n='free_mb'; e={ [double]((@($_.free_space_mb, $_.free_mb, 0) | Where-Object { $null -ne $_ })[0]) }},
                       @{n='total_mb'; e={ [double]((@($_.total_size_mb, $_.total_mb, 0) | Where-Object { $null -ne $_ })[0]) }}

            if ($pts.Count -lt 3) { continue }

            $refDate    = [datetime]$pts[0].collected_at
            $dayOffsets = $pts | ForEach-Object { ([datetime]$_.collected_at - $refDate).TotalDays }
            $freeSizes  = $pts | ForEach-Object { $_.free_mb }

            # Negative rate means free space is shrinking (disk filling)
            $ratePerDay  = Get-LinearGrowthRate -Sizes $freeSizes -DayOffsets $dayOffsets
            $latestFree  = $freeSizes[-1]
            $latestTotal = ($pts[-1]).total_mb

            $daysToFull = $null
            $status     = 'OK'

            if ($ratePerDay -lt 0 -and $latestFree -gt 0) {
                $daysToFull = [math]::Round($latestFree / [math]::Abs($ratePerDay), 0)
                $status = if ($daysToFull -le $CritDaysToFull) {
                    "CRITICAL - drive fills in ~$daysToFull days at current rate"
                } elseif ($daysToFull -le $WarnDaysToFull) {
                    "WARN - drive fills in ~$daysToFull days"
                } else {
                    "OK - ~$daysToFull days of capacity remaining"
                }
            } elseif ($ratePerDay -ge 0) {
                $status = 'OK - free space stable or increasing'
            }

            $results.Add([PSCustomObject]@{
                type              = 'DRIVE'
                name              = $grp.Name
                drive             = $grp.Name
                current_size_mb   = [math]::Round($latestTotal, 1)
                free_mb           = [math]::Round($latestFree, 1)
                growth_mb_per_day = [math]::Round($ratePerDay, 2)  # negative = filling
                data_points       = $pts.Count
                lookback_days     = $LookbackDays
                days_to_full      = $daysToFull
                status            = $status
            })
        }
    }
}
else {
    Write-Warning "Collector directory not found: $diskDir - install the StorageIO collector job first (sql\collectors\Generate-CollectorJob-StorageIO.sql)."
}

if ($results.Count -eq 0) {
    Write-Warning "No projection data available. Ensure collectors have been running for at least 14 days."
    return
}

Write-Host "Capacity Projection - $LookbackDays-day lookback ($($results.Count) items)" -ForegroundColor Cyan

$sorted = $results | Sort-Object {
    switch -Wildcard ($_.status) {
        'CRITICAL*' { 1 }
        'WARN*'     { 2 }
        default     { 3 }
    }
}, { (@($_.days_to_full, 9999) | Where-Object { $null -ne $_ })[0] }

if ($OutputFormat -eq 'Csv') {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile   = if ($OutputPath) { $OutputPath } else {
        $outDir = Join-Path $repoRoot 'output-files\reviews\reporting'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        Join-Path $outDir "Get-CapacityProjection-$timestamp.csv"
    }
    $sorted | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "Output saved: $outFile" -ForegroundColor Green
} else {
    $sorted | Format-Table type, name, current_size_mb, free_mb, growth_mb_per_day,
                            data_points, days_to_full, status -AutoSize
}
