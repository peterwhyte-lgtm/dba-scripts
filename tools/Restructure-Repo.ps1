<#
.SYNOPSIS
Ensures the current category-first repo layout is present.

.DESCRIPTION
This maintenance helper is intentionally conservative: it only creates the
standard folders used by the current repo layout and does not move or rewrite
existing scripts.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$folders = @(
    'categories',
    'docs',
    'helpers',
    'helpers/local-sql',
    'output-files',
    'sql-templates',
    'tools'
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot $folder) | Out-Null
}

Write-Host 'Repo structure verified.' -ForegroundColor Green
Write-Host 'Current layout uses categories/<topic>/{sql,powershell} plus helpers/ and tools/.' -ForegroundColor DarkCyan
