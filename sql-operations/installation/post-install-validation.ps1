<#
.SYNOPSIS
Validate a SQL Server installation is configured correctly.

.DESCRIPTION
Connects to a SQL Server instance and checks services, connectivity, version,
configuration settings, TempDB layout, and security posture.
Outputs PASS / WARN / FAIL per check with a summary.

.PARAMETER ServerInstance
Instance to validate. Default: . (local default instance).

.PARAMETER InstanceName
Windows service name suffix (e.g. MSSQLSERVER or SQL2022). Default: MSSQLSERVER.

.PARAMETER ExpectedMaxMemoryGB
Expected max server memory setting. If 0, validates it is not at the unlimited default.

.PARAMETER ExpectedMaxDOP
Expected MaxDOP. If 0, validates it is not at default (0).

.EXAMPLE
.\sql-operations\installation\post-install-validation.ps1
.\sql-operations\installation\post-install-validation.ps1 -ServerInstance PROD01\SQL2022 -InstanceName SQL2022
#>
param(
    [string]$ServerInstance      = '.',
    [string]$InstanceName        = 'MSSQLSERVER',
    [int]$ExpectedMaxMemoryGB    = 0,
    [int]$ExpectedMaxDOP         = 0
)

$ErrorActionPreference = 'SilentlyContinue'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }

$pass = 0; $warn = 0; $fail = 0

function Add-Check {
    param([string]$Category, [string]$Check, [string]$Status, [string]$Detail)
    $color = switch ($Status) { 'PASS'{'Green'} 'WARN'{'Yellow'} 'FAIL'{'Red'} default{'White'} }
    Write-Host ("  [{0,-4}] {1,-40} {2}" -f $Status, $Check, $Detail) -ForegroundColor $color
    switch ($Status) { 'PASS'{$script:pass++} 'WARN'{$script:warn++} 'FAIL'{$script:fail++} }
}

Write-Host ""
Write-Host "  Post-Install Validation — $ServerInstance" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-', 62)) -ForegroundColor DarkCyan
Write-Host ""

# ── Services ──────────────────────────────────────────────────────────────────
$svcName    = if ($InstanceName -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$InstanceName" }
$agtName    = if ($InstanceName -eq 'MSSQLSERVER') { 'SQLSERVERAGENT' } else { "SQLAgent`$$InstanceName" }

$sqlSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
$agtSvc = Get-Service -Name $agtName -ErrorAction SilentlyContinue

Add-Check 'Services' 'SQL Server service running' `
    $(if ($sqlSvc -and $sqlSvc.Status -eq 'Running') {'PASS'} else {'FAIL'}) `
    $(if ($sqlSvc) { $sqlSvc.Status } else { "Service '$svcName' not found" })

Add-Check 'Services' 'SQL Agent service running' `
    $(if ($agtSvc -and $agtSvc.Status -eq 'Running') {'PASS'} elseif ($agtSvc) {'WARN'} else {'WARN'}) `
    $(if ($agtSvc) { $agtSvc.Status } else { "Service '$agtName' not found" })

Add-Check 'Services' 'SQL Agent startup type' `
    $(if ($agtSvc -and $agtSvc.StartType -eq 'Automatic') {'PASS'} else {'WARN'}) `
    $(if ($agtSvc) { $agtSvc.StartType } else { 'unknown' })

# ── Connectivity ──────────────────────────────────────────────────────────────
$connected = $false
try {
    $versionRow = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                      -Query "SELECT @@VERSION AS v, SERVERPROPERTY('ProductVersion') AS pv, SERVERPROPERTY('ProductLevel') AS pl" `
                      -QueryTimeout 15 -TrustServerCertificate -ErrorAction Stop
    $connected = $true
    Add-Check 'Connectivity' 'SQL Server connection' 'PASS' "v$($versionRow.pv) $($versionRow.pl)"
} catch {
    Add-Check 'Connectivity' 'SQL Server connection' 'FAIL' $_.Exception.Message
}

if ($connected) {

# ── Configuration ─────────────────────────────────────────────────────────────
$configs = Invoke-Sqlcmd -ServerInstance $ServerInstance `
               -Query "SELECT name, value_in_use FROM sys.configurations WHERE name IN ('max server memory (MB)','max degree of parallelism','cost threshold for parallelism','backup compression default','optimize for ad hoc workloads','remote admin connections')" `
               -TrustServerCertificate -ErrorAction SilentlyContinue
$cfg = @{}
foreach ($row in $configs) { $cfg[$row.name] = [int]$row.value_in_use }

$maxMemMB = $cfg['max server memory (MB)']
if ($ExpectedMaxMemoryGB -gt 0) {
    $expectedMB = $ExpectedMaxMemoryGB * 1024
    Add-Check 'Config' 'Max server memory' `
        $(if ($maxMemMB -eq $expectedMB) {'PASS'} else {'WARN'}) `
        "$($maxMemMB)MB $(if ($maxMemMB -eq $expectedMB) {'matches expected'} else {"(expected $($expectedMB)MB)"})"
} else {
    Add-Check 'Config' 'Max server memory' `
        $(if ($maxMemMB -lt 2147483647) {'PASS'} else {'WARN'}) `
        "$($maxMemMB)MB $(if ($maxMemMB -ge 2147483647) {'— not configured (SQL default = unlimited)'})"
}

$maxdop = $cfg['max degree of parallelism']
if ($ExpectedMaxDOP -gt 0) {
    Add-Check 'Config' 'MaxDOP' `
        $(if ($maxdop -eq $ExpectedMaxDOP) {'PASS'} else {'WARN'}) `
        "$maxdop $(if ($maxdop -ne $ExpectedMaxDOP) {"(expected $ExpectedMaxDOP)"})"
} else {
    Add-Check 'Config' 'MaxDOP' `
        $(if ($maxdop -gt 0) {'PASS'} else {'WARN'}) `
        $(if ($maxdop -eq 0) {'0 — not configured (unlimited parallelism)'} else { $maxdop })
}

$ctp = $cfg['cost threshold for parallelism']
Add-Check 'Config' 'Cost threshold for parallelism' `
    $(if ($ctp -ge 25) {'PASS'} elseif ($ctp -ge 5) {'WARN'} else {'WARN'}) `
    "$ctp $(if ($ctp -le 5) {'— SQL default; 25-50 recommended'})"

Add-Check 'Config' 'Backup compression' `
    $(if ($cfg['backup compression default'] -eq 1) {'PASS'} else {'WARN'}) `
    $(if ($cfg['backup compression default'] -eq 1) {'Enabled'} else {'Disabled — enable for smaller backups'})

Add-Check 'Config' 'Optimize for ad hoc workloads' `
    $(if ($cfg['optimize for ad hoc workloads'] -eq 1) {'PASS'} else {'WARN'}) `
    $(if ($cfg['optimize for ad hoc workloads'] -eq 1) {'Enabled'} else {'Disabled — enable to reduce plan cache bloat'})

# ── TempDB ────────────────────────────────────────────────────────────────────
$tempdbFiles = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                   -Query "SELECT COUNT(*) AS n FROM tempdb.sys.database_files WHERE type = 0" `
                   -TrustServerCertificate -ErrorAction SilentlyContinue
$fileCount = [int]$tempdbFiles.n
$logicalCPUs = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).NumberOfLogicalProcessors
$recommendedFiles = [math]::Min($logicalCPUs, 8)
Add-Check 'TempDB' 'TempDB data file count' `
    $(if ($fileCount -ge $recommendedFiles) {'PASS'} elseif ($fileCount -ge 2) {'WARN'} else {'WARN'}) `
    "$fileCount files (recommended: $recommendedFiles for this CPU count)"

# ── Network ───────────────────────────────────────────────────────────────────
$tcpCheck = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Query "SELECT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID" `
                -TrustServerCertificate -ErrorAction SilentlyContinue
$tcpPort = $tcpCheck.local_tcp_port
Add-Check 'Network' 'TCP/IP connection' `
    $(if ($tcpPort) {'PASS'} else {'WARN'}) `
    $(if ($tcpPort) {"Port $tcpPort"} else {'Could not confirm TCP port'})

# ── Security ──────────────────────────────────────────────────────────────────
$saRow = Invoke-Sqlcmd -ServerInstance $ServerInstance `
             -Query "SELECT is_disabled FROM sys.server_principals WHERE name = 'sa'" `
             -TrustServerCertificate -ErrorAction SilentlyContinue
if ($saRow) {
    Add-Check 'Security' 'SA account disabled' `
        $(if ($saRow.is_disabled -eq 1) {'PASS'} else {'WARN'}) `
        $(if ($saRow.is_disabled -eq 1) {'SA is disabled'} else {'SA is ENABLED — disable if not needed'})
}

$authMode = Invoke-Sqlcmd -ServerInstance $ServerInstance `
                -Query "SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WinOnly" `
                -TrustServerCertificate -ErrorAction SilentlyContinue
Add-Check 'Security' 'Authentication mode' 'PASS' `
    $(if ($authMode.WinOnly -eq 1) {'Windows auth only'} else {'Mixed mode (Windows + SQL)'})

} else {
    Write-Host "  Cannot connect — skipping configuration, TempDB, network, and security checks." -ForegroundColor Yellow
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("  " + [string]::new('=', 62)) -ForegroundColor DarkCyan
$summaryColor = if ($fail -gt 0) {'Red'} elseif ($warn -gt 0) {'Yellow'} else {'Green'}
$verdict = if ($fail -gt 0) {'ISSUES FOUND — review FAIL items'} `
           elseif ($warn -gt 0) {'PASSED WITH WARNINGS — review WARN items'} `
           else {'ALL CHECKS PASSED'}
Write-Host "  $verdict" -ForegroundColor $summaryColor
Write-Host "  PASS: $pass   WARN: $warn   FAIL: $fail" -ForegroundColor $summaryColor
Write-Host ""
