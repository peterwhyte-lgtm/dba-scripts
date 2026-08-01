<#
.SYNOPSIS
Executes a SQL script from this repo against a local SQL Server instance.

.DESCRIPTION
This helper is built for fast local testing of DBA scripts from the canonical sql/ layout, with support for repo helpers and templates.
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
    [int]$TopResults = 25,
    [switch]$RawOutput
)

$ErrorActionPreference = 'Stop'

function Show-ResultsFooter([string]$csvPath) {
    if ($env:DBASCRIPTS_BATCH) { return }
    $relPath = $csvPath.Replace($repoRoot.ToString(), '').TrimStart('\')
    $enc     = [Uri]::EscapeDataString($relPath)
    $url     = "http://localhost:8787/csv?p=$enc"
    $uiUp    = $false
    try { $tcp = [System.Net.Sockets.TcpClient]::new('localhost', 8787); $tcp.Close(); $uiUp = $true } catch { $null = $_ }
    Write-Host ''
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
    Write-Host "  Saved   : $relPath" -ForegroundColor Green
    if ($uiUp) {
        Write-Host "  Review  : $url" -ForegroundColor Cyan
    } else {
        Write-Host "  Review  : $url" -ForegroundColor DarkGray
        Write-Host "            (web UI not running — start with: .\web-ui\Start-WebUi.ps1)" -ForegroundColor DarkGray
    }
    Write-Host ('─' * 64) -ForegroundColor DarkCyan
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# Session-level connection defaults — set via .\tools\local-sql\Set-SqlConnection.ps1
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
        MaxCharLength         = 2000000
        TrustServerCertificate = $true
        ErrorAction           = 'Stop'
    }

    if ($Username -and $Password) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }

    Write-Host "[repo-sql] Using Invoke-Sqlcmd" -ForegroundColor Green
    try {
        $results = @(Invoke-Sqlcmd @params)
    } catch {
        Write-Host "[repo-sql] Connection failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[repo-sql] Running network check for $ServerInstance ..." -ForegroundColor Yellow
        $netCheck = Join-Path $PSScriptRoot 'Test-ServerNetwork.ps1'
        if (Test-Path $netCheck) { & $netCheck -ServerInstance $ServerInstance }
        throw
    }

    if ($RawOutput -and $results.Count -gt 0) {
        $col     = $results[0].PSObject.Properties.Name | Select-Object -First 1
        $rawText = ($results | ForEach-Object { $_.$col }) -join "`n"
        [PSCustomObject]@{ script = $rawText } |
            Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    } else {
        $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    }

    if ($results.Count -eq 0) {
        Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
    } elseif (-not $RawOutput -and $OutputFormat -ne 'Csv') {
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
    # No -r flag: SQL errors (severity < 17) go to stdout which sqlcmd writes to the -o file,
    # so we can read the actual error text on failure. With -r 1 they go to the console
    # handle (not stderr fd) and cannot be captured by PowerShell redirection.
    $sqlcmdArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $resolvedPath, '-b', '-f', '65001', '-t', $QueryTimeout, '-C', '-o', $tempOutput, '-W', '-w', '4000', '-s', ',')
    if ($Username -and $Password) {
        $sqlcmdArgs += @('-U', $Username, '-P', $Password)
    }
    else {
        $sqlcmdArgs += '-E'
    }

    Write-Host "[repo-sql] Using sqlcmd.exe" -ForegroundColor Green
    & $sqlcmd.Source @sqlcmdArgs
    if ($LASTEXITCODE -ne 0) {
        $errContent = ''
        if (Test-Path -LiteralPath $tempOutput) {
            $rawErr = Get-Content -LiteralPath $tempOutput -Raw -Encoding UTF8 -EA SilentlyContinue
            if ($rawErr) {
                $errContent = $rawErr.Trim() -replace '\r?\n', ' ' -replace '\s+', ' '
            }
        }
        $msg = if ($errContent) { $errContent } else { "sqlcmd.exe failed with exit code $LASTEXITCODE" }
        Write-Host "[repo-sql] Connection failed: $msg" -ForegroundColor Red
        Write-Host "[repo-sql] Running network check for $ServerInstance ..." -ForegroundColor Yellow
        $netCheck = Join-Path $PSScriptRoot 'Test-ServerNetwork.ps1'
        if (Test-Path $netCheck) { & $netCheck -ServerInstance $ServerInstance }
        throw $msg
    }

    if (Test-Path -LiteralPath $tempOutput) {
        # Separator-aware CSV parsing: find the dash row and use the line before it as the
        # header. This handles PRINT output appearing before the SELECT results, which
        # happens because PRINT goes to stdout (same as SELECT) without the -r flag.
        $allLines = @(Get-Content -LiteralPath $tempOutput -Encoding UTF8 -EA SilentlyContinue)
        $sepIdx = -1
        for ($li = 1; $li -lt $allLines.Count; $li++) {
            if ($allLines[$li] -match '^-+(?:,-+)*\s*$') { $sepIdx = $li; break }
        }
        $csvText = if ($sepIdx -gt 0) {
            $dataLines = if ($sepIdx + 1 -lt $allLines.Count) { @($allLines[($sepIdx + 1)..($allLines.Count - 1)]) } else { @() }
            (@($allLines[$sepIdx - 1]) + $dataLines) -join "`n"
        } else {
            $allLines -join "`n"
        }
        $rows = @($csvText | ConvertFrom-Csv -Delimiter ',' -EA SilentlyContinue)

        if ($RawOutput -and $rows.Count -gt 0) {
            $col     = $rows[0].PSObject.Properties.Name | Select-Object -First 1
            $rawText = ($rows | ForEach-Object { $_.$col }) -join "`n"
            [PSCustomObject]@{ script = $rawText } |
                Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        } else {
            $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
        }

        if ($rows.Count -eq 0) {
            Write-Host "[repo-sql] No rows returned." -ForegroundColor Yellow
        } elseif (-not $RawOutput -and $OutputFormat -ne 'Csv') {
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
