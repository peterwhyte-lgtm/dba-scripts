<#
.SYNOPSIS
Simple launcher for the repo PowerShell scripts.

.DESCRIPTION
This helper makes it easier to run scripts from the canonical sql/, powershell/, hybrid/, and helpers/ layout.
#>

param(
    [string]$ScriptPath,
    [string]$ScriptName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

function Resolve-RepoScript {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $candidates = @()
    $searchRoots = @(
        (Join-Path $repoRoot 'helpers'),
        (Join-Path $repoRoot 'sql'),
        (Join-Path $repoRoot 'powershell'),
        (Join-Path $repoRoot 'hybrid'),
        (Join-Path $repoRoot 'tools')
    )

    foreach ($root in $searchRoots) {
        $candidates += Get-ChildItem -Path $root -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*\$Name.ps1" -or $_.FullName -like "*$Name*.ps1" }
    }

    $unique = $candidates | Sort-Object FullName -Unique
    if ($unique.Count -eq 0) {
        return $null
    }
    if ($unique.Count -gt 1) {
        Write-Host 'Multiple matches found:' -ForegroundColor Yellow
        $unique | ForEach-Object { Write-Host "  - $([System.IO.Path]::GetRelativePath($repoRoot, $_.FullName))" -ForegroundColor DarkGray }
        throw "Please pass a more specific script name or full path."
    }

    return [System.IO.Path]::GetRelativePath($repoRoot, $unique[0].FullName)
}

if (-not $ScriptPath -and $ScriptName) {
    $ScriptPath = Resolve-RepoScript -Name $ScriptName
}

if (-not $ScriptPath) {
    throw 'Please provide -ScriptPath or -ScriptName.'
}

$target = if ([System.IO.Path]::IsPathRooted($ScriptPath)) {
    $ScriptPath
}
else {
    Join-Path $repoRoot $ScriptPath
}

if (-not (Test-Path -LiteralPath $target)) {
    throw "Script not found: $ScriptPath"
}

Write-Host "Running: $([System.IO.Path]::GetRelativePath($repoRoot, $target))" -ForegroundColor Cyan

# Array splatting loses named-parameter identity (each element becomes positional).
# Parse back into a hashtable so -OutputFormat Csv etc. survive the hop correctly.
$splat = @{}
$i = 0
while ($i -lt $Arguments.Count) {
    if ($Arguments[$i] -match '^-{1,2}(.+)$') {
        $key = $Matches[1]
        if (($i + 1) -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-') {
            $splat[$key] = $Arguments[$i + 1]
            $i += 2
        } else {
            $splat[$key] = $true   # switch parameter
            $i++
        }
    } else {
        $i++
    }
}

if ($splat.Count -gt 0) { & $target @splat } else { & $target }
