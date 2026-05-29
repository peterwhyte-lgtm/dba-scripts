<#
.SYNOPSIS
Finds the most relevant existing DBA script for a quick task.

.DESCRIPTION
Uses simple keywords to surface likely script paths from the category-first layout.
This reduces AI/assistant token usage by pointing directly to the existing script you need.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Keyword
)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$matches = Get-ChildItem -Path (Join-Path $repoRoot 'categories') -Recurse -File |
    Where-Object {
        $_.FullName -match [regex]::Escape($Keyword)
    }

if (-not $matches) {
    Write-Warning "No script paths matched '$Keyword'."
    return
}

Write-Host "Likely scripts for '$Keyword':" -ForegroundColor Cyan
$matches |
    Select-Object -ExpandProperty FullName |
    ForEach-Object { $_.Replace((Join-Path $repoRoot ''), '') } |
    Sort-Object |
    ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
