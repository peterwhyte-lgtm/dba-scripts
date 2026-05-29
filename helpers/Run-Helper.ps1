<#
.SYNOPSIS
Simple launcher for the repo PowerShell scripts.

.DESCRIPTION
This helper makes it easier to run scripts from the category-first structure and the top-level helpers area.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$target = if ([System.IO.Path]::IsPathRooted($ScriptPath)) {
    $ScriptPath
}
else {
    Join-Path $repoRoot $ScriptPath
}

if (-not (Test-Path -LiteralPath $target)) {
    throw "Script not found: $target"
}

$cmdArgs = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $target)
if ($Arguments) { $cmdArgs += $Arguments }

Write-Host "Running: pwsh $($cmdArgs -join ' ')" -ForegroundColor Cyan
& pwsh @cmdArgs
