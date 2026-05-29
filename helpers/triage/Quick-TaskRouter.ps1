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
  'backup' = 'sql/backups';
  'restore' = 'sql/backups';
  'blocking' = 'sql/performance';
  'wait' = 'sql/performance';
  'fragmentation' = 'sql/monitoring';
  'disk' = 'sql/monitoring';
  'memory' = 'sql/monitoring';
  'permission' = 'sql/security';
  'ag' = 'sql/monitoring';
  'lab' = 'sql/monitoring'
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
