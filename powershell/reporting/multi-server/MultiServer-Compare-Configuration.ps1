<#
.SYNOPSIS
Cross-server sp_configure drift detection — finds settings where any server differs from the majority.

.DESCRIPTION
Runs sp_configure across all servers in -ServerList and identifies settings where any server
deviates from the peer majority. Does not require a saved baseline — uses statistical peer
comparison. Useful for fleet-wide consistency audits (50+ instances).

.NOTES
ScriptType  : automation
TargetScope : multi-server
RiskLevel   : SAFE

.EXAMPLE
.\MultiServer-Compare-Configuration.ps1 -ServerList PROD01,PROD02,PROD03,PROD04

.\MultiServer-Compare-Configuration.ps1 -ServerFile .\servers.txt -OutputFormat Csv
#>

param(
    [string[]]$ServerList,
    [string]$ServerFile,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')

# Resolve server list
$servers = if ($ServerList) {
    $ServerList
} elseif ($ServerFile -and (Test-Path $ServerFile)) {
    Get-Content $ServerFile | Where-Object { $_ -and $_.Trim() -notmatch '^#' } | ForEach-Object { $_.Trim() }
} else {
    throw 'Provide -ServerList or -ServerFile.'
}

Write-Host "Collecting sp_configure from $($servers.Count) server(s)..." -ForegroundColor Cyan

$configSql = @"
SELECT
    CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256)) AS server_name,
    name                                                AS setting_name,
    CAST(value_in_use AS NVARCHAR(100))                 AS running_value,
    CAST(value       AS NVARCHAR(100))                  AS configured_value,
    CASE WHEN value <> value_in_use THEN 'PENDING_RESTART' ELSE 'OK' END AS restart_state
FROM sys.configurations
ORDER BY name;
"@

$allRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($srv in $servers) {
    try {
        $useModule = $null -ne (Get-Module -Name SqlServer -ListAvailable | Select-Object -First 1)
        $rows = if ($useModule) {
            Invoke-Sqlcmd -ServerInstance $srv -Query $configSql -TrustServerCertificate -ErrorAction Stop
        } else {
            & sqlcmd -S $srv -Q $configSql -s "~" -W -h -1 2>$null |
                Where-Object { $_ -match '~' } |
                ForEach-Object {
                    $parts = $_ -split '~'
                    [PSCustomObject]@{
                        server_name      = $parts[0].Trim()
                        setting_name     = $parts[1].Trim()
                        running_value    = $parts[2].Trim()
                        configured_value = $parts[3].Trim()
                        restart_state    = $parts[4].Trim()
                    }
                }
        }
        foreach ($r in $rows) { $allRows.Add($r) }
        Write-Host "  OK  $srv ($(@($rows).Count) settings)" -ForegroundColor Green
    }
    catch {
        Write-Warning "  FAIL $srv — $_"
        $allRows.Add([PSCustomObject]@{
            server_name      = $srv
            setting_name     = '(connection failed)'
            running_value    = $_.ToString()
            configured_value = ''
            restart_state    = 'ERROR'
        })
    }
}

if ($allRows.Count -eq 0) {
    Write-Warning 'No data collected.'; return
}

# Find the majority value per setting (most common value across servers)
$grouped = $allRows |
    Where-Object { $_.setting_name -ne '(connection failed)' } |
    Group-Object setting_name

$driftRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($g in $grouped) {
    $settingName = $g.Name
    $values      = $g.Group

    # Majority value
    $majorityVal = $values |
        Group-Object running_value |
        Sort-Object Count -Descending |
        Select-Object -First 1 -ExpandProperty Name

    $majorityCount = ($values | Where-Object { $_.running_value -eq $majorityVal }).Count
    $totalCount    = $values.Count

    # Servers that differ
    $outliers = $values | Where-Object { $_.running_value -ne $majorityVal }
    foreach ($o in $outliers) {
        $driftRows.Add([PSCustomObject]@{
            setting_name    = $settingName
            server          = $o.server_name
            server_value    = $o.running_value
            majority_value  = $majorityVal
            majority_count  = "$majorityCount / $totalCount servers"
            restart_pending = $o.restart_state -eq 'PENDING_RESTART'
        })
    }
}

Write-Host "`nServers compared: $($servers.Count) | Settings checked: $($grouped.Count)" -ForegroundColor Cyan

if ($driftRows.Count -eq 0) {
    Write-Host 'No configuration drift detected across fleet.' -ForegroundColor Green
    return
}

Write-Host "$($driftRows.Count) setting(s) with drift:" -ForegroundColor Yellow

$results = $driftRows | Sort-Object setting_name, server

if ($OutputFormat -eq 'Csv') {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile   = if ($OutputPath) { $OutputPath } else {
        $outDir = Join-Path $repoRoot 'output-files\reviews\reporting'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        Join-Path $outDir "MultiServer-Compare-Configuration-$timestamp.csv"
    }
    $results | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "Output saved: $outFile" -ForegroundColor Green
} else {
    $results | Format-Table setting_name, server, server_value, majority_value, majority_count, restart_pending -AutoSize
}
