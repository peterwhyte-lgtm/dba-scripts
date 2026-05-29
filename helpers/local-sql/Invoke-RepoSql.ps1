<#
.SYNOPSIS
Executes a SQL script from this repo against a local SQL Server instance.

.DESCRIPTION
This helper is built for fast local testing of DBA scripts from the canonical sql/ and powershell/ layout, with support for repo helpers and templates.
It supports terminal output and CSV export for later review or automation.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string]$ServerInstance = '.',
    [string]$Database = 'master',
    [string]$Username,
    [string]$Password,
    [int]$QueryTimeout = 600,
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath,
    [int]$TopResults = 25
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$resolvedPath = if ([System.IO.Path]::IsPathRooted($ScriptPath)) { $ScriptPath } else { Join-Path $repoRoot $ScriptPath }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
$category = if ($resolvedPath -match '[\\/]categories[\\/]([^\\/]+)[\\/]') { $Matches[1] } else { 'general' }

if (-not (Test-Path -LiteralPath $resolvedPath)) {
    throw "SQL script not found: $ScriptPath"
}

if (-not $OutputPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $defaultRoot = Join-Path $repoRoot 'output-files\reviews'
    $OutputPath = Join-Path $defaultRoot "$category\$scriptName-$timestamp.csv"
}

$OutputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "[repo-sql] Script: $resolvedPath" -ForegroundColor Cyan
Write-Host "[repo-sql] Server: $ServerInstance" -ForegroundColor Cyan
Write-Host "[repo-sql] Database: $Database" -ForegroundColor Cyan
Write-Host "[repo-sql] Output: $OutputFormat" -ForegroundColor Cyan
Write-Host "[repo-sql] CSV: $OutputPath" -ForegroundColor Cyan

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue

if ($invokeSqlcmd) {
    $params = @{
        ServerInstance = $ServerInstance
        Database       = $Database
        InputFile      = $resolvedPath
        QueryTimeout   = $QueryTimeout
        ErrorAction    = 'Stop'
    }

    if ($Username -and $Password) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }

    Write-Host "[repo-sql] Using Invoke-Sqlcmd" -ForegroundColor Green
    $results = @(Invoke-Sqlcmd @params)

    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[repo-sql] Full CSV written to: $OutputPath" -ForegroundColor Green

    $preview = $results | Select-Object -First $TopResults
    if ($preview.Count -gt 0) {
        $preview | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
    }
    return
}

if ($sqlcmd) {
    $tempOutput = Join-Path $OutputDirectory ("$scriptName-{0}.tmp.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $args = @('-S', $ServerInstance, '-d', $Database, '-i', $resolvedPath, '-b', '-r', '1', '-t', $QueryTimeout, '-C', '-o', $tempOutput, '-W', '-w', '4000', '-s', ',')
    if ($Username -and $Password) {
        $args += @('-U', $Username, '-P', $Password)
    }
    else {
        $args += '-E'
    }

    Write-Host "[repo-sql] Using sqlcmd.exe" -ForegroundColor Green
    & $sqlcmd.Source @args
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd.exe failed with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $tempOutput) {
        $rows = @(Import-Csv -LiteralPath $tempOutput -ErrorAction Stop)
        $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "[repo-sql] Full CSV written to: $OutputPath" -ForegroundColor Green

        $preview = $rows | Select-Object -First $TopResults
        if ($preview.Count -gt 0) {
            $preview | Format-Table -AutoSize | Out-String | Write-Host
        }
        else {
            Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[repo-sql] sqlcmd.exe completed but no CSV file was produced." -ForegroundColor Yellow
    }
    return
}

throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.'
