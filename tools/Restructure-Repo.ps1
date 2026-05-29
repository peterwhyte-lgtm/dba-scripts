$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'helpers') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'tools') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'categories') | Out-Null

Copy-Item -Recurse -Force (Join-Path $repoRoot 'powershell/helpers/*') (Join-Path $repoRoot 'helpers/')

$cats = @(
  'performance-troubleshooting',
  'storage-capacity-management',
  'backups-and-recovery',
  'maintenance-and-reliability',
  'configuration-and-environment',
  'security-and-permissions',
  'high-availability-and-disaster-recovery',
  'dba-lab-scripts'
)

foreach ($cat in $cats) {
  $targetRoot = Join-Path $repoRoot "categories/$cat"
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot 'sql') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot 'powershell') | Out-Null

  $sqlSource = Join-Path $repoRoot "sql/$cat"
  if (Test-Path $sqlSource) {
    Copy-Item -Recurse -Force (Join-Path $sqlSource '*') (Join-Path $targetRoot 'sql/')
  }

  $psSource = Join-Path $repoRoot "powershell/$cat"
  if (Test-Path $psSource) {
    Copy-Item -Recurse -Force (Join-Path $psSource '*') (Join-Path $targetRoot 'powershell/')
  }
}

Write-Host 'Restructure complete.'
