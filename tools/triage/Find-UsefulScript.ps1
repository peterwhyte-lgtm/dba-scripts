<#
.SYNOPSIS
Finds DBA scripts matching a keyword — searches both file names and script content.

.EXAMPLE
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking
.\tools\triage\Find-UsefulScript.ps1 -Keyword backup
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Keyword
)
$ErrorActionPreference = 'Stop'

$repoRoot     = Resolve-Path (Join-Path $PSScriptRoot '..\..')
# Match file NAMES across all these roots (cheap).
$nameRoots    = @('sql', 'powershell', 'tools', 'blog')
# Search file CONTENT only in the actual script folders. blog/ holds 3000+ post
# drafts and images, so a recursive Select-String there is pathologically slow and
# looks like a hang — we still match blog/ file names above, just not their content.
$contentRoots = @('sql', 'powershell', 'tools')
$escaped      = [regex]::Escape($Keyword)

# Name matches (all roots)
$nameMatches = $nameRoots | ForEach-Object {
    $path = Join-Path $repoRoot $_
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $escaped }
    }
}

# Content matches (script folders only)
$contentMatches = $contentRoots | ForEach-Object {
    $path = Join-Path $repoRoot $_
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { Select-String -Path $_.FullName -Pattern $Keyword -Quiet -ErrorAction SilentlyContinue }
    }
}

$found = @($nameMatches) + @($contentMatches) |
    Sort-Object FullName -Unique

if (-not $found) {
    Write-Warning "No scripts matched '$Keyword'."
    return
}

Write-Host ""
Write-Host "  Scripts matching '$Keyword':" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-', 60)) -ForegroundColor DarkCyan

foreach ($file in $found) {
    $rel = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName)
    Write-Host "  $rel" -ForegroundColor Green

    $purposeLine = Get-Content $file.FullName -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*Purpose\s*:' } |
        Select-Object -First 1
    if ($purposeLine) {
        $purposeText = ($purposeLine -replace '^\s*Purpose\s*:\s*', '').Trim()
        Write-Host "    $purposeText" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  Run any script with:  .\run.ps1 <ScriptName>" -ForegroundColor DarkGray
Write-Host ""
