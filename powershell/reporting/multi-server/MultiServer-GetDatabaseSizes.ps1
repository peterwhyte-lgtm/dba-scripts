﻿<#
Script Name : MultiServer-GetDatabaseSizes
Category    : multi-server-scripts/sql
Purpose     : Report data and log file sizes across multiple SQL Server instances. Free space is approximate from sys.master_files.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated SQL Server instances.
              -Database master          Connection database. Default: master.
              -MinSizeMb 0             Only return databases above this size. Default: 0 (all).
              -SqlAuth                  Prompt for SQL credentials instead of Windows auth.
              -Parallel                 Run all servers simultaneously (PS7+).
Output      : Server, database_name, state_desc, recovery_model_desc,
              data_size_mb, log_size_mb, total_size_mb, data_file_count, log_file_count
              Note: no free space — run Get-DatabaseSizesAndFreeSpace for per-file detail.
Example     : .\MultiServer-GetDatabaseSizes.ps1 -Servers "SVR01,SVR02" -MinSizeMb 1000
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$Database = 'master',
    [int]$MinSizeMb = 0,
    [switch]$SqlAuth,
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -Name SqlServer -ListAvailable)) {
    Write-Host '  SqlServer module required: Install-Module -Name SqlServer -Scope CurrentUser -Force' -ForegroundColor Yellow
    exit 1
}
Import-Module SqlServer -ErrorAction Stop

$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$credential = if ($SqlAuth) { Get-Credential -Message "SQL credentials for: $($serverList -join ', ')" } else { $null }

$sql = @"
SELECT
    d.name                                                              AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    CAST(SUM(CASE mf.type WHEN 0 THEN mf.size ELSE 0 END) * 8.0 / 1024
         AS DECIMAL(12,2))                                             AS data_size_mb,
    CAST(SUM(CASE mf.type WHEN 1 THEN mf.size ELSE 0 END) * 8.0 / 1024
         AS DECIMAL(12,2))                                             AS log_size_mb,
    CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(12,2))                 AS total_size_mb,
    COUNT(DISTINCT CASE mf.type WHEN 0 THEN mf.file_id END)           AS data_file_count,
    COUNT(DISTINCT CASE mf.type WHEN 1 THEN mf.file_id END)           AS log_file_count
FROM sys.databases d
JOIN sys.master_files mf ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.state_desc, d.recovery_model_desc
HAVING SUM(mf.size) * 8.0 / 1024 >= $MinSizeMb
ORDER BY total_size_mb DESC;
"@

function Invoke-SizeQuery([string]$server) {
    try {
        $p = @{ ServerInstance = $server; Database = $Database; Query = $sql; TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
        if ($credential) { $p.Username = $credential.UserName; $p.Password = $credential.GetNetworkCredential().Password }
        $rows = Invoke-Sqlcmd @p
        if ($rows) { foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $server }} } }
    } catch {
        [PSCustomObject]@{ Server = $server; database_name = 'ERROR'; total_size_mb = 0; Error = $_.Exception.Message }
    }
}

$allResults = [System.Collections.Generic.List[object]]::new()

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        Import-Module SqlServer -ErrorAction SilentlyContinue
        $srv = $_; $q = $using:sql; $db = $using:Database; $cr = $using:credential
        try {
            $p = @{ ServerInstance = $srv; Database = $db; Query = $q; TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
            if ($cr) { $p.Username = $cr.UserName; $p.Password = $cr.GetNetworkCredential().Password }
            $rows = Invoke-Sqlcmd @p
            foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $srv }} }
        } catch {
            [PSCustomObject]@{ Server = $srv; database_name = 'ERROR'; total_size_mb = 0; Error = $_.Exception.Message }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Invoke-SizeQuery $server)
        foreach ($r in $rows) { $allResults.Add($r) }
        $rows | Format-Table database_name, state_desc, recovery_model_desc, data_size_mb, log_size_mb, total_size_mb -AutoSize
    }
}

if ($Parallel -and $allResults.Count -gt 0) {
    $allResults | Sort-Object { [double]((@($_.total_size_mb, 0) | Where-Object { $null -ne $_ })[0]) } -Descending |
        Format-Table Server, database_name, state_desc, data_size_mb, log_size_mb, total_size_mb -AutoSize
}

$grandTotal = [Math]::Round(($allResults | Measure-Object { [double]((@($_.total_size_mb, 0) | Where-Object { $null -ne $_ })[0]) } -Sum).Sum / 1024, 2)
Write-Host "`nGrand total across all servers: $grandTotal GB" -ForegroundColor Cyan
Write-Host "Done." -ForegroundColor Green