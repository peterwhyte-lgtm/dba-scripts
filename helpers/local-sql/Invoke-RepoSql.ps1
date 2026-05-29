<#
.SYNOPSIS
Executes a SQL script from this repo against a local SQL Server instance.

.DESCRIPTION
This helper is built for fast local testing of DBA scripts from categories/ and sql-templates/.
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
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$resolvedPath = if ([System.IO.Path]::IsPathRooted($ScriptPath)) { $ScriptPath } else { Join-Path $repoRoot $ScriptPath }

if (-not (Test-Path -LiteralPath $resolvedPath)) {
    throw "SQL script not found: $ScriptPath"
}

Write-Host "[repo-sql] Script: $resolvedPath" -ForegroundColor Cyan
Write-Host "[repo-sql] Server: $ServerInstance" -ForegroundColor Cyan
Write-Host "[repo-sql] Database: $Database" -ForegroundColor Cyan
Write-Host "[repo-sql] Output: $OutputFormat" -ForegroundColor Cyan

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
    $results = Invoke-Sqlcmd @params

    if ($OutputFormat -eq 'Csv') {
        $csv = $results | ConvertTo-Csv -NoTypeInformation
        if ($OutputPath) {
            $csv | Set-Content -LiteralPath $OutputPath -Encoding UTF8
            Write-Host "[repo-sql] CSV written to: $OutputPath" -ForegroundColor Green
        }
        else {
            $csv | Write-Output
        }
        return
    }

    if ($OutputPath) {
        $results | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Host "[repo-sql] Output saved to: $OutputPath" -ForegroundColor Green
    }
    else {
        $results | Format-Table -AutoSize
    }
    return
}

if ($sqlcmd) {
    $args = @('-S', $ServerInstance, '-d', $Database, '-i', $resolvedPath, '-b', '-r', '1', '-t', $QueryTimeout, '-C')
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
    return
}

throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.'
