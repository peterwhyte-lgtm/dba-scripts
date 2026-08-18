<#
.SYNOPSIS
Generate a summary report from SQL Server installation and configuration logs.

.DESCRIPTION
Reads install/configure/patch logs from output-files\ and produces a readable
summary showing what was installed, when, against which instances, and the outcome.

.PARAMETER LogRoot
Root folder to scan for logs. Default: output-files\ in the repo root.

.PARAMETER OutputFormat
'Table' (default) — writes to terminal. 'Csv' — also saves a CSV.

.EXAMPLE
.\admin\installation\generate-install-report.ps1
.\admin\installation\generate-install-report.ps1 -OutputFormat Csv

.NOTES
RiskLevel   : SAFE - reads setup logs; writes only a local report file
#>
param(
    [string]$LogRoot      = '',
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat = 'Table'
)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
if (-not $LogRoot) { $LogRoot = Join-Path $repoRoot 'output-files' }

$logDirs = @(
    @{ Dir = Join-Path $LogRoot 'installation'; Type = 'Install'  },
    @{ Dir = Join-Path $LogRoot 'patches';      Type = 'Patch'    }
)

$events = [System.Collections.Generic.List[PSObject]]::new()

foreach ($ld in $logDirs) {
    if (-not (Test-Path $ld.Dir)) { continue }
    $logs = Get-ChildItem -Path $ld.Dir -Filter '*.log' -File |
                Where-Object { $_.Name -notlike '*.stdout' -and $_.Name -notlike '*.stderr' } |
                Sort-Object LastWriteTime -Descending

    foreach ($log in $logs) {
        $lines   = Get-Content $log.FullName -ErrorAction SilentlyContinue
        $outcome = 'Unknown'
        $target  = ''

        foreach ($line in $lines) {
            if ($line -match 'succeeded|complete|Done') { $outcome = 'Success' }
            if ($line -match 'FAILED|failed|ERROR:')    { $outcome = 'Failed'  }
            if ($line -match 'cancelled')               { $outcome = 'Cancelled' }
            if ($line -match 'Server\s*:\s*(.+)')       { $target  = $Matches[1].Trim() }
            if ($line -match 'Instance\s*:\s*(.+)')     { $target  = $Matches[1].Trim() }
        }

        $events.Add([PSCustomObject]@{
            Timestamp  = $log.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            Type       = $ld.Type
            Target     = if ($target) { $target } else { '-' }
            Outcome    = $outcome
            LogFile    = $log.Name
        })
    }
}

Write-Host ""
Write-Host "  SQL Server Installation & Patch Report" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-', 70)) -ForegroundColor DarkCyan
Write-Host ""

if ($events.Count -eq 0) {
    Write-Host "  No install or patch logs found under: $LogRoot" -ForegroundColor Yellow
    Write-Host "  Run install-sql.ps1 or install-cu.ps1 first." -ForegroundColor DarkGray
    Write-Host ""
    return
}

foreach ($e in $events) {
    $outcomeColor = switch ($e.Outcome) {
        'Success'   { 'Green'  }
        'Failed'    { 'Red'    }
        'Cancelled' { 'Yellow' }
        default     { 'Gray'   }
    }
    Write-Host ("  {0}  {1,-10} {2,-24} " -f $e.Timestamp, $e.Type, $e.Target) -NoNewline
    Write-Host $e.Outcome -ForegroundColor $outcomeColor
}

Write-Host ""
Write-Host "  Total events: $($events.Count)" -ForegroundColor DarkGray

if ($OutputFormat -eq 'Csv') {
    $outDir  = Join-Path $LogRoot 'installation'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $csvPath = Join-Path $outDir "install-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $events | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "  CSV: $csvPath" -ForegroundColor DarkGray
}
Write-Host ""