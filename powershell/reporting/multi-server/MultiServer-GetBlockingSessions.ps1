﻿<#
Script Name : MultiServer-GetBlockingSessions
Category    : multi-server-scripts/sql
Purpose     : Check for active blocking sessions across multiple SQL Server instances. Zero rows means no blocking.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated SQL Server instances.
              -Database master          Connection database. Default: master.
              -SqlAuth                  Prompt for SQL credentials instead of Windows auth.
              -Parallel                 Run all servers simultaneously (PS7+).
Output      : Server, session_id, blocking_session_id, wait_type, wait_sec,
              database_name, login_name, host_name, current_statement
              Zero rows returned means no active blocking on that server.
Example     : .\MultiServer-GetBlockingSessions.ps1 -Servers "SVR01,SVR02,SVR03"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$Database = 'master',
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

$sql = @'
SELECT
    r.session_id,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time / 1000.0                                    AS wait_sec,
    r.wait_resource,
    r.status,
    DB_NAME(r.database_id)                                  AS database_name,
    s.login_name,
    s.program_name,
    s.host_name,
    s.open_transaction_count,
    SUBSTRING(t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
          ELSE r.statement_end_offset END - r.statement_start_offset) / 2) + 1
    )                                                       AS current_statement
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0
   OR EXISTS (
        SELECT 1 FROM sys.dm_exec_requests r2
        WHERE r2.blocking_session_id = r.session_id
   )
ORDER BY r.blocking_session_id, r.session_id;
'@

function Invoke-BlockingQuery([string]$server) {
    try {
        $p = @{ ServerInstance = $server; Database = $Database; Query = $sql; TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
        if ($credential) { $p.Username = $credential.UserName; $p.Password = $credential.GetNetworkCredential().Password }
        $rows = Invoke-Sqlcmd @p
        if ($rows) { foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $server }} } }
        else { [PSCustomObject]@{ Server = $server; session_id = '—'; blocking_session_id = '—'; wait_type = 'NO BLOCKING'; wait_sec = 0; current_statement = '' } }
    } catch {
        [PSCustomObject]@{ Server = $server; session_id = 'ERROR'; blocking_session_id = ''; wait_type = $_.Exception.Message; wait_sec = 0; current_statement = '' }
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
            if ($rows) { foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $srv }} } }
            else { [PSCustomObject]@{ Server = $srv; session_id = '—'; blocking_session_id = '—'; wait_type = 'NO BLOCKING'; wait_sec = 0; current_statement = '' } }
        } catch {
            [PSCustomObject]@{ Server = $srv; session_id = 'ERROR'; blocking_session_id = ''; wait_type = $_.Message; wait_sec = 0; current_statement = '' }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Invoke-BlockingQuery $server)
        foreach ($r in $rows) { $allResults.Add($r) }
        $rows | Format-Table session_id, blocking_session_id, wait_type, wait_sec, database_name, login_name, current_statement -AutoSize
    }
}

if ($Parallel -and $allResults.Count -gt 0) {
    $allResults | Sort-Object Server, { [double]((@($_.wait_sec, 0) | Where-Object { $null -ne $_ })[0]) } -Descending |
        Format-Table Server, session_id, blocking_session_id, wait_type, wait_sec, login_name, current_statement -AutoSize
}

Write-Host "`nDone." -ForegroundColor Green