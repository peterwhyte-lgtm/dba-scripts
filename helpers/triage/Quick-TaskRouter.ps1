<#
.SYNOPSIS
Routes a DBA task to the best existing script path.

.DESCRIPTION
A small triage helper for common DBA tasks so the repo is easier to use during AI-assisted work.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Task
)

$routes = @{
  'backup' = 'categories/backups-and-recovery';
  'restore' = 'categories/backups-and-recovery';
  'blocking' = 'categories/performance-troubleshooting';
  'wait' = 'categories/performance-troubleshooting';
  'fragmentation' = 'categories/maintenance-and-reliability';
  'disk' = 'categories/storage-capacity-management';
  'memory' = 'categories/configuration-and-environment';
  'permission' = 'categories/security-and-permissions';
  'ag' = 'categories/high-availability-and-disaster-recovery';
  'lab' = 'categories/dba-lab-scripts'
}

$taskLower = $Task.ToLowerInvariant()

$match = $routes.GetEnumerator() | Where-Object { $taskLower -match $_.Key } | Select-Object -First 1

if (-not $match) {
  Write-Warning "No routing rule found for task '$Task'. Try a broader keyword such as backup, blocking, disk, memory, or permission."
  return
}

Write-Host "Best starting area for '$Task':" -ForegroundColor Cyan
Write-Host "  $($match.Value)" -ForegroundColor Green
Write-Host "Use helpers/Find-UsefulScript.ps1 with a more specific keyword to locate the exact script." -ForegroundColor DarkGray
