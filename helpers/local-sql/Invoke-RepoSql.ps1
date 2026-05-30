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

function Show-ResultsFooter([string]$csvPath) {
    if ($env:DBASCRIPTS_BATCH) { return }
    $relPath = $csvPath.Replace($repoRoot.ToString(), '').TrimStart('\')
    $enc     = [Uri]::EscapeDataString($relPath)
    $url     = "http://localhost:8787/csv?p=$enc"
    $uiUp    = $false
    try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch {}
    Write-Host ''
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
    Write-Host "  Saved   : $relPath" -ForegroundColor Green
    if ($uiUp) {
        Write-Host "  Review  : $url" -ForegroundColor Cyan
    } else {
        Write-Host "  Review  : $url" -ForegroundColor DarkGray
        Write-Host "            (web UI not running — start with: .\tools\Start-WebUi.ps1)" -ForegroundColor DarkGray
    }
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# Session-level connection defaults — set via .\helpers\local-sql\Set-SqlConnection.ps1
# Explicit params win; env vars fill in only when the param is still at its default value.
if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username   -and $env:DBASCRIPTS_USER)          { $Username = $env:DBASCRIPTS_USER }
if (-not $Password   -and $env:DBASCRIPTS_PASS)          { $Password = $env:DBASCRIPTS_PASS }

$resolvedPath = if ([System.IO.Path]::IsPathRooted($ScriptPath)) { $ScriptPath } else { Join-Path $repoRoot $ScriptPath }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
$category = if    ($resolvedPath -match '[\\/]categories[\\/]([^\\/]+)[\\/]') { $Matches[1] }
            elseif ($resolvedPath -match '[\\/]sql[\\/]([^\\/]+)[\\/]')        { $Matches[1] }
            elseif ($resolvedPath -match '[\\/]powershell[\\/]([^\\/]+)[\\/]') { $Matches[1] }
            else                                                                 { 'general' }

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

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }
Write-Host "[repo-sql] Script  : $resolvedPath" -ForegroundColor Cyan
Write-Host "[repo-sql] Server  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[repo-sql] Auth    : $authLabel" -ForegroundColor Cyan
Write-Host "[repo-sql] Database: $Database" -ForegroundColor Cyan
Write-Host "[repo-sql] Output  : $OutputFormat" -ForegroundColor Cyan
Write-Host "[repo-sql] CSV     : $OutputPath" -ForegroundColor Cyan

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue

if ($invokeSqlcmd) {
    $params = @{
        ServerInstance        = $ServerInstance
        Database              = $Database
        InputFile             = $resolvedPath
        QueryTimeout          = $QueryTimeout
        TrustServerCertificate = $true
        ErrorAction           = 'Stop'
    }

    if ($Username -and $Password) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }

    Write-Host "[repo-sql] Using Invoke-Sqlcmd" -ForegroundColor Green
    $results = @(Invoke-Sqlcmd @params)
    $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

    if ($results.Count -eq 0) {
        Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
    } elseif ($OutputFormat -ne 'Csv') {
        $results | Select-Object -First $TopResults | Format-Table -AutoSize | Out-String | Write-Host
        if ($results.Count -gt $TopResults) {
            Write-Host "[repo-sql] $($results.Count) rows — showing first $TopResults. Full results in CSV." -ForegroundColor DarkGray
        } else {
            Write-Host "[repo-sql] $($results.Count) row(s)" -ForegroundColor DarkGray
        }
    }
    Show-ResultsFooter $OutputPath
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
        $rawRows = @(Import-Csv -LiteralPath $tempOutput -ErrorAction Stop)
        # sqlcmd.exe inserts a separator row (all dashes) as the second row — strip it
        $rows = @($rawRows | Where-Object {
            $row = $_; $cols = $row.PSObject.Properties.Name
            -not ($cols | Where-Object { $row.$_ -match '^-+$' })
        })
        $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

        if ($rows.Count -eq 0) {
            Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
        } elseif ($OutputFormat -ne 'Csv') {
            $rows | Select-Object -First $TopResults | Format-Table -AutoSize | Out-String | Write-Host
            if ($rows.Count -gt $TopResults) {
                Write-Host "[repo-sql] $($rows.Count) rows — showing first $TopResults. Full results in CSV." -ForegroundColor DarkGray
            } else {
                Write-Host "[repo-sql] $($rows.Count) row(s)" -ForegroundColor DarkGray
            }
        }
        Show-ResultsFooter $OutputPath
    }
    else {
        Write-Host "[repo-sql] sqlcmd.exe completed but no CSV file was produced." -ForegroundColor Yellow
    }
    return
}

throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.'
