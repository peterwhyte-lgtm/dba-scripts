<#
.SYNOPSIS
Shows a quick inventory of the DBA scripts repo for triage and navigation.

.DESCRIPTION
Enumerates the SQL and PowerShell script folders and prints a practical summary
that helps a DBA find the highest-value scripts quickly.
#>

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$scriptRoots = @(
    @{ Name = 'SQL scripts'; Path = Join-Path $repoRoot 'sql' },
    @{ Name = 'PowerShell scripts'; Path = Join-Path $repoRoot 'powershell' }
)

$categoryOrder = @(
    'performance-troubleshooting',
    'storage-capacity-management',
    'backups-and-recovery',
    'maintenance-and-reliability',
    'configuration-and-environment',
    'security-and-permissions',
    'high-availability-and-disaster-recovery',
    'dba-lab-scripts'
)

$summary = foreach ($root in $scriptRoots) {
    $includePattern = if ($root.Name -eq 'SQL scripts') { '*.sql' } else { '*.ps1' }
    $files = Get-ChildItem -Path $root.Path -Recurse -File -Include $includePattern -ErrorAction SilentlyContinue
    $byCategory = @{}

    foreach ($file in $files) {
        $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $segments = $relative -split '[\\/]'
        $category = $segments[1]
        if (-not $byCategory.ContainsKey($category)) {
            $byCategory[$category] = 0
        }
        $byCategory[$category]++
    }

    [PSCustomObject]@{
        Kind = $root.Name
        TotalScripts = $files.Count
        CategoryBreakdown = ($categoryOrder | ForEach-Object {
            if ($byCategory.ContainsKey($_)) {
                "{0}: {1}" -f $_, $byCategory[$_]
            }
        } | Where-Object { $_ }) -join '; '
    }
}

Write-Host "DBA Script Repo Overview" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor DarkCyan
$summary | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "" 
Write-Host "Fast-start recommendations:" -ForegroundColor Green
Write-Host "  1. sql/monitoring/Get-DatabaseSizesAndFreeSpace.sql" -ForegroundColor DarkGray
Write-Host "  2. sql/performance/Get-BlockingSessions.sql" -ForegroundColor DarkGray
Write-Host "  3. sql/backups/Get-BackupCoverage.sql" -ForegroundColor DarkGray
Write-Host "  4. helpers/local-sql/Invoke-SqlFile.ps1" -ForegroundColor DarkGray
Write-Host "  5. helpers/Run-Helper.ps1" -ForegroundColor DarkGray
