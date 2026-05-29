<#
.SYNOPSIS
Short repo launcher for common DBA helper scripts.

.DESCRIPTION
This wrapper makes it easy to run helper scripts from the repo root using
just a script name or relative path, without manually typing long commands.

.EXAMPLES
  .\run.ps1 Get-WaitStatistics
  .\run.ps1 Get-LongRunningQueries
  .\run.ps1 powershell\reporting\Get-WaitStatistics.ps1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$repoRoot = Resolve-Path $PSScriptRoot
$launcher = Join-Path $repoRoot 'helpers\Run-Helper.ps1'

if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Launcher not found: $launcher"
}

& $launcher -ScriptName $ScriptName @Arguments
