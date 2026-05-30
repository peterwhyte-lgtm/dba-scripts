<#
.SYNOPSIS
Creates a starter PowerShell helper for a DBA task.

.DESCRIPTION
Scaffolds a simple PowerShell script in the appropriate category folder to accelerate routine development work.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Task,

    [string]$Category = 'performance-troubleshooting'
)
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$targetDir = Join-Path $repoRoot "powershell/$Category"

if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
}

$slug = ($Task -replace '\W+', '-').Trim('-').ToLowerInvariant()
$fileName = "Get-{0}.ps1" -f ((Get-Culture).TextInfo.ToTitleCase($slug) -replace '-', '')
$fullPath = Join-Path $targetDir $fileName

if (Test-Path -LiteralPath $fullPath) {
    Write-Warning "File already exists: $fullPath"
    return
}

$script = @"
<#
.SYNOPSIS
Starter helper for: $Task
#>

Write-Host 'TODO: implement DBA logic for $Task' -ForegroundColor Yellow
"@

Set-Content -LiteralPath $fullPath -Value $script -Encoding UTF8
Write-Host "Created starter PowerShell helper: $fullPath" -ForegroundColor Green
