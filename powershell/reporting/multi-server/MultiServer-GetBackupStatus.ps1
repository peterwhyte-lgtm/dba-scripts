﻿<#
Script Name : MultiServer-GetBackupStatus
Category    : multi-server-scripts/sql
Purpose     : Check backup coverage across multiple SQL Server instances. Shows last full, diff, and log backup age with coverage status.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : SqlServer PowerShell module.
              Install with: Install-Module -Name SqlServer -Scope CurrentUser -Force
Params      : -Servers "SVR01,SVR02"   Required. Comma-separated SQL Server instances.
              -Database master          Connection database. Default: master.
              -WarnFullAgeHours 25     Flag databases whose last full backup exceeds this age. Default: 25.
              -SqlAuth                  Prompt for SQL credentials instead of Windows auth.
              -Parallel                 Run all servers simultaneously (PS7+).
Output      : Server, database_name, recovery_model_desc, coverage_status,
              full_backup_age_hours, last_full_backup, last_diff_backup, last_log_backup
              coverage_status: OK | FULL_STALE | NO_FULL_BACKUP | NO_LOG_BACKUP
Example     : .\MultiServer-GetBackupStatus.ps1 -Servers "SVR01,SVR02,SVR03" -WarnFullAgeHours 12
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$Database = 'master',
    [int]$WarnFullAgeHours = 25,
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
    d.name                                                                          AS database_name,
    d.recovery_model_desc,
    MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END)                      AS last_full_backup,
    MAX(CASE bs.type WHEN 'I' THEN bs.backup_finish_date END)                      AS last_diff_backup,
    MAX(CASE bs.type WHEN 'L' THEN bs.backup_finish_date END)                      AS last_log_backup,
    CAST(DATEDIFF(MINUTE,
        MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END),
        GETDATE()) / 60.0 AS DECIMAL(10,1))                                        AS full_backup_age_hours,
    CASE
        WHEN MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END) IS NULL
            THEN 'NO_FULL_BACKUP'
        WHEN DATEDIFF(HOUR,
                MAX(CASE bs.type WHEN 'D' THEN bs.backup_finish_date END),
                GETDATE()) > $WarnFullAgeHours
            THEN 'FULL_STALE'
        WHEN d.recovery_model_desc IN ('FULL','BULK_LOGGED')
             AND MAX(CASE bs.type WHEN 'L' THEN bs.backup_finish_date END) IS NULL
            THEN 'NO_LOG_BACKUP'
        ELSE 'OK'
    END                                                                             AS coverage_status
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name
   AND bs.backup_finish_date >= DATEADD(DAY, -14, GETDATE())
WHERE d.database_id > 4
  AND d.state_desc  = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY full_backup_age_hours DESC;
"@

function Invoke-BackupQuery([string]$server) {
    try {
        $p = @{ ServerInstance = $server; Database = $Database; Query = $sql; TrustServerCertificate = $true; OutputAs = 'DataTables'; ErrorAction = 'Stop' }
        if ($credential) { $p.Username = $credential.UserName; $p.Password = $credential.GetNetworkCredential().Password }
        $rows = Invoke-Sqlcmd @p
        if ($rows) { foreach ($r in $rows) { $r | Select-Object *, @{n='Server'; e={ $server }} } }
    } catch {
        [PSCustomObject]@{ Server = $server; database_name = 'ERROR'; coverage_status = $_.Exception.Message }
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
            [PSCustomObject]@{ Server = $srv; database_name = 'ERROR'; coverage_status = $_.Message }
        }
    } -ThrottleLimit 10 | ForEach-Object { $allResults.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n=== $server ===" -ForegroundColor Cyan
        $rows = @(Invoke-BackupQuery $server)
        $issues = @($rows | Where-Object { $_.coverage_status -ne 'OK' })
        foreach ($r in $rows) { $allResults.Add($r) }
        if ($issues.Count -gt 0) {
            Write-Host "  $($issues.Count) database(s) with coverage issues:" -ForegroundColor Yellow
            $issues | Format-Table database_name, coverage_status, full_backup_age_hours, last_full_backup -AutoSize
        } else {
            Write-Host "  All $($rows.Count) database(s) OK" -ForegroundColor Green
        }
    }
}

Write-Host "`n── Full results ─────────────────────────────────────────" -ForegroundColor DarkGray
$allResults | Sort-Object Server, { [double]((@($_.full_backup_age_hours, 9999) | Where-Object { $null -ne $_ })[0]) } -Descending |
    Format-Table Server, database_name, recovery_model_desc, coverage_status, full_backup_age_hours, last_full_backup, last_log_backup -AutoSize

Write-Host "`nDone." -ForegroundColor Green