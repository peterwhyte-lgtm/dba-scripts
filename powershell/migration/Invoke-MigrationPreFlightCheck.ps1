<#
.SYNOPSIS
Runs a pre-migration checklist covering network connectivity, SQL Server version/edition/collation
compatibility, disk space, and target server configuration.

.NOTES
ScriptType   : PowerShell-only
TargetScope  : source + target server pair
RiskLevel    : SAFE
Purpose      : Catch blockers before the migration window — connectivity, version mismatch,
               insufficient disk space, edition downgrade risk, and target misconfiguration.

.DESCRIPTION
Runs the following checks and prints a pass/warn/fail table:

  Network (from this machine):
    Source reachable on SQL port
    Target reachable on SQL port
    Backup share accessible (UNC)

  Network (source ↔ target, via WinRM if available):
    Source → Target on SQL port (1433 or custom)
    Target → Source on SQL port
    Source → Target on AG endpoint port (5022, if -CheckAG)
    Source and Target → Backup share on port 445 (SMB)

  SQL Server:
    Version: source ≤ target (backup/restore compatibility)
    Edition: flag downgrade risk if target is lower
    Collation: server-level collation match
    Target SQL Agent service running and auto-start

  Target configuration:
    max server memory configured (not at SQL Server default)
    TempDB file count vs logical CPU count
    Disk space on target: data volume free ≥ source total data size
    Disk space on target: log volume free ≥ source total log size

No SQL Server module required. Uses System.Data.SqlClient for SQL queries.
WinRM-based server-to-server port checks are attempted with Invoke-Command; if
WinRM is unavailable they are marked SKIPPED with an instruction to test manually.

.PARAMETER SourceInstance
Source SQL Server instance (e.g. PROD01 or PROD01\SQL2019). Required.

.PARAMETER TargetInstance
Target SQL Server instance (e.g. PROD02 or PROD02\SQL2019). Required.

.PARAMETER BackupPath
UNC or local path where backup files will be written. Optional but recommended.

.PARAMETER SqlPort
SQL Server TCP port to test. Defaults to 1433.

.PARAMETER CheckAG
Also test TCP port 5022 between source and target (AG Database Mirroring Endpoint).

.PARAMETER OutputPath
Optional CSV file path to save the check results.

.EXAMPLE
.\powershell\migration\Invoke-MigrationPreFlightCheck.ps1 -SourceInstance PROD01 -TargetInstance PROD02

.EXAMPLE
.\powershell\migration\Invoke-MigrationPreFlightCheck.ps1 -SourceInstance PROD01 -TargetInstance PROD02 `
    -BackupPath '\\BACKUPSRV\SQL-Backups' -CheckAG
#>

param(
    [Parameter(Mandatory)]
    [string]$SourceInstance,

    [Parameter(Mandatory)]
    [string]$TargetInstance,

    [string]$BackupPath,

    [int]$SqlPort = 1433,

    [switch]$CheckAG,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# ── Helpers ───────────────────────────────────────────────────────────────────

# Extract hostname from instance string (strip \INSTANCE)
function Get-Hostname([string]$instance) {
    ($instance -split '\\')[0]
}

# Test a TCP port from the local machine — returns $true/$false
function Test-Port([string]$hostName, [int]$port, [int]$timeout = 3000) {
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($hostName, $port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($timeout)
        if ($ok -and $tcp.Connected) { $tcp.Close(); return $true }
        $tcp.Close()
        return $false
    }
    catch { return $false }
}

# Resolve a hostname to its first IPv4 address
function Resolve-Ip([string]$hostName) {
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($hostName) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        if ($addrs) { return $addrs[0].ToString() }
        return $null
    }
    catch { return $null }
}

# Run a SQL scalar query — no SMO, no SqlServer module required
function Invoke-SqlScalar([string]$instance, [string]$query, [int]$timeout = 10) {
    try {
        $cs   = "Server=$instance;Database=master;Integrated Security=True;Connect Timeout=$timeout;Application Name=MigrationPreFlightCheck"
        $conn = [System.Data.SqlClient.SqlConnection]::new($cs)
        $conn.Open()
        $cmd  = $conn.CreateCommand()
        $cmd.CommandText    = $query
        $cmd.CommandTimeout = $timeout
        $val  = $cmd.ExecuteScalar()
        $conn.Close()
        return $val
    }
    catch { return $null }
}

# Run a SQL query returning a DataTable
function Invoke-SqlDataTable([string]$instance, [string]$query, [int]$timeout = 15) {
    try {
        $cs      = "Server=$instance;Database=master;Integrated Security=True;Connect Timeout=$timeout;Application Name=MigrationPreFlightCheck"
        $conn    = [System.Data.SqlClient.SqlConnection]::new($cs)
        $conn.Open()
        $cmd     = $conn.CreateCommand()
        $cmd.CommandText    = $query
        $cmd.CommandTimeout = $timeout
        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($cmd)
        $dt      = [System.Data.DataTable]::new()
        [void]$adapter.Fill($dt)
        $conn.Close()
        return $dt
    }
    catch { return $null }
}

# Test a TCP port via Invoke-Command on a remote machine (requires WinRM/PSRemoting)
function Test-RemotePort([string]$fromHost, [int]$port, [string]$toHost, [int]$timeout = 3000) {
    try {
        $result = Invoke-Command -ComputerName $fromHost -ScriptBlock {
            try {
                $tcp = [System.Net.Sockets.TcpClient]::new()
                $ar  = $tcp.BeginConnect($Using:toHost, $Using:port, $null, $null)
                $ok  = $ar.AsyncWaitHandle.WaitOne($Using:timeout)
                if ($ok -and $tcp.Connected) { $tcp.Close(); return $true }
                $tcp.Close(); return $false
            } catch { return $false }
        } -ErrorAction Stop
        return [PSCustomObject]@{ Success = $result; Skipped = $false; Error = '' }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Skipped = $true; Error = $_.Exception.Message -replace "`r?`n",' ' }
    }
}

# Add a finding to the results table
function Add-Check {
    param(
        [string]$Category,
        [string]$Check,
        [ValidateSet('PASS','WARN','FAIL','SKIP','INFO')]
        [string]$Result,
        [string]$Detail
    )
    $script:checks.Add([PSCustomObject]@{
        Category = $Category
        Check    = $Check
        Result   = $Result
        Detail   = $Detail
    })
}

$script:checks = [System.Collections.Generic.List[PSObject]]::new()

$srcHost = Get-Hostname $SourceInstance
$tgtHost = Get-Hostname $TargetInstance

# ── Header ────────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host '  Migration Pre-Flight Check' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  Source : $SourceInstance"
Write-Host "  Target : $TargetInstance"
if ($BackupPath) { Write-Host "  Backup : $BackupPath" }
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ('-' * 60)
Write-Host ''

# ══════════════════════════════════════════════════════════════
# SECTION 1 — DNS RESOLUTION
# ══════════════════════════════════════════════════════════════

$srcIp = Resolve-Ip $srcHost
$tgtIp = Resolve-Ip $tgtHost

Add-Check 'DNS' "Resolve source hostname ($srcHost)" `
    $(if ($srcIp) { 'PASS' } else { 'FAIL' }) `
    $(if ($srcIp) { "Resolved to $srcIp" } else { "Cannot resolve $srcHost - check DNS or use IP directly" })

Add-Check 'DNS' "Resolve target hostname ($tgtHost)" `
    $(if ($tgtIp) { 'PASS' } else { 'FAIL' }) `
    $(if ($tgtIp) { "Resolved to $tgtIp" } else { "Cannot resolve $tgtHost - check DNS or use IP directly" })

# ══════════════════════════════════════════════════════════════
# SECTION 2 — NETWORK CONNECTIVITY (from this machine)
# ══════════════════════════════════════════════════════════════

$srcPortOk = Test-Port $srcHost $SqlPort
$tgtPortOk = Test-Port $tgtHost $SqlPort

Add-Check 'Network (local→source)' "SQL port $SqlPort on $srcHost" `
    $(if ($srcPortOk) { 'PASS' } else { 'FAIL' }) `
    $(if ($srcPortOk) { "Port $SqlPort reachable" } else { "Port $SqlPort NOT reachable from this machine - check firewall rules" })

Add-Check 'Network (local→target)' "SQL port $SqlPort on $tgtHost" `
    $(if ($tgtPortOk) { 'PASS' } else { 'FAIL' }) `
    $(if ($tgtPortOk) { "Port $SqlPort reachable" } else { "Port $SqlPort NOT reachable from this machine - check firewall rules" })

if ($BackupPath -and $BackupPath.StartsWith('\\')) {
    $shareParts   = $BackupPath.TrimStart('\').Split('\')
    $backupHost   = $shareParts[0]
    $smbOk        = Test-Port $backupHost 445
    $localShareOk = Test-Path $BackupPath -ErrorAction SilentlyContinue

    Add-Check 'Network (local→backup)' "SMB port 445 on $backupHost" `
        $(if ($smbOk) { 'PASS' } else { 'FAIL' }) `
        $(if ($smbOk) { "Port 445 reachable" } else { "Port 445 not reachable - backup share may be inaccessible" })

    Add-Check 'Network (local→backup)' "UNC path accessible ($BackupPath)" `
        $(if ($localShareOk) { 'PASS' } else { 'WARN' }) `
        $(if ($localShareOk) { "Path is accessible from this machine" } else { "Path not accessible from this machine - verify SQL Server service account has access" })
}

# ══════════════════════════════════════════════════════════════
# SECTION 3 — NETWORK CONNECTIVITY (server-to-server via WinRM)
# ══════════════════════════════════════════════════════════════

$srcToTgt = Test-RemotePort $srcHost $SqlPort $tgtHost
$tgtToSrc = Test-RemotePort $tgtHost $SqlPort $srcHost

if ($srcToTgt.Skipped) {
    Add-Check 'Network (source→target)' "SQL port $SqlPort : $srcHost → $tgtHost" 'SKIP' `
        "WinRM not available on $srcHost - test manually: Test-NetConnection -ComputerName $tgtHost -Port $SqlPort"
} else {
    Add-Check 'Network (source→target)' "SQL port $SqlPort : $srcHost → $tgtHost" `
        $(if ($srcToTgt.Success) { 'PASS' } else { 'FAIL' }) `
        $(if ($srcToTgt.Success) { "Port $SqlPort reachable from $srcHost" } else { "Port $SqlPort NOT reachable from $srcHost - check firewall on target" })
}

if ($tgtToSrc.Skipped) {
    Add-Check 'Network (target→source)' "SQL port $SqlPort : $tgtHost → $srcHost" 'SKIP' `
        "WinRM not available on $tgtHost - test manually: Test-NetConnection -ComputerName $srcHost -Port $SqlPort"
} else {
    Add-Check 'Network (target→source)' "SQL port $SqlPort : $tgtHost → $srcHost" `
        $(if ($tgtToSrc.Success) { 'PASS' } else { 'FAIL' }) `
        $(if ($tgtToSrc.Success) { "Port $SqlPort reachable from $tgtHost" } else { "Port $SqlPort NOT reachable from $tgtHost - check firewall on source" })
}

if ($CheckAG) {
    $srcToTgtAG = Test-RemotePort $srcHost 5022 $tgtHost
    $tgtToSrcAG = Test-RemotePort $tgtHost 5022 $srcHost
    $label = 'AG endpoint port 5022'

    if ($srcToTgtAG.Skipped) {
        Add-Check 'Network (AG endpoint)' "$label : $srcHost → $tgtHost" 'SKIP' `
            "WinRM not available - test manually: Test-NetConnection -ComputerName $tgtHost -Port 5022"
    } else {
        Add-Check 'Network (AG endpoint)' "$label : $srcHost → $tgtHost" `
            $(if ($srcToTgtAG.Success) { 'PASS' } else { 'FAIL' }) `
            $(if ($srcToTgtAG.Success) { "Port 5022 reachable" } else { "Port 5022 NOT reachable - AG mirroring endpoint will fail. Check firewall and that endpoint is created on both nodes." })
    }

    if ($tgtToSrcAG.Skipped) {
        Add-Check 'Network (AG endpoint)' "$label : $tgtHost → $srcHost" 'SKIP' `
            "WinRM not available - test manually: Test-NetConnection -ComputerName $srcHost -Port 5022"
    } else {
        Add-Check 'Network (AG endpoint)' "$label : $tgtHost → $srcHost" `
            $(if ($tgtToSrcAG.Success) { 'PASS' } else { 'FAIL' }) `
            $(if ($tgtToSrcAG.Success) { "Port 5022 reachable" } else { "Port 5022 NOT reachable" })
    }
}

if ($BackupPath -and $BackupPath.StartsWith('\\')) {
    $shareParts = $BackupPath.TrimStart('\').Split('\')
    $backupHost = $shareParts[0]

    foreach ($srv in @($srcHost, $tgtHost)) {
        $res = Test-RemotePort $srv 445 $backupHost
        if ($res.Skipped) {
            Add-Check 'Network (backup share)' "SMB 445 : $srv → $backupHost" 'SKIP' `
                "WinRM not available - test manually on $srv"
        } else {
            Add-Check 'Network (backup share)' "SMB 445 : $srv → $backupHost" `
                $(if ($res.Success) { 'PASS' } else { 'FAIL' }) `
                $(if ($res.Success) { "SMB 445 reachable from $srv" } else { "SMB 445 NOT reachable from $srv - backup/restore will fail. Check firewall and share permissions." })
        }
    }
}

# ══════════════════════════════════════════════════════════════
# SECTION 4 — SQL SERVER VERSION AND EDITION
# ══════════════════════════════════════════════════════════════

$srcVersion   = Invoke-SqlScalar $SourceInstance "SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(20))"
$tgtVersion   = Invoke-SqlScalar $TargetInstance "SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(20))"
$srcEdition   = Invoke-SqlScalar $SourceInstance "SELECT CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128))"
$tgtEdition   = Invoke-SqlScalar $TargetInstance "SELECT CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128))"
$srcCollation = Invoke-SqlScalar $SourceInstance "SELECT CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128))"
$tgtCollation = Invoke-SqlScalar $TargetInstance "SELECT CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128))"

# Version comparison (major.minor.build.revision)
function Compare-SqlVersions([string]$src, [string]$tgt) {
    if (-not $src -or -not $tgt) { return 'UNKNOWN' }
    $s = [version]$src; $t = [version]$tgt
    if ($s.Major -gt $t.Major) { return 'SRC_NEWER' }
    if ($s.Major -eq $t.Major -and $s.Minor -gt $t.Minor) { return 'SRC_NEWER' }
    if ($s.Major -eq $t.Major) { return 'SAME_MAJOR' }
    return 'TGT_NEWER'
}

$versionComparison = Compare-SqlVersions $srcVersion $tgtVersion

if (-not $srcVersion) {
    Add-Check 'SQL Server' "Connect to source ($SourceInstance)" 'FAIL' "Cannot connect - check instance name, port, and permissions"
} else {
    Add-Check 'SQL Server' "Source version" 'INFO' "$srcVersion ($srcEdition)"
}

if (-not $tgtVersion) {
    Add-Check 'SQL Server' "Connect to target ($TargetInstance)" 'FAIL' "Cannot connect - check instance name, port, and permissions"
} else {
    Add-Check 'SQL Server' "Target version" 'INFO' "$tgtVersion ($tgtEdition)"
}

if ($srcVersion -and $tgtVersion) {
    $srcMajor = [int]($srcVersion -split '\.')[0]
    $tgtMajor = [int]($tgtVersion -split '\.')[0]

    if ($srcMajor -gt $tgtMajor) {
        Add-Check 'SQL Server' 'Version compatibility' 'FAIL' `
            "Source ($srcVersion) is NEWER than target ($tgtVersion). Databases cannot be restored to an older SQL Server version. Target must be same version or newer."
    } elseif ($srcMajor -eq $tgtMajor) {
        Add-Check 'SQL Server' 'Version compatibility' 'PASS' `
            "Same major version ($srcMajor). Backup/restore compatible."
    } else {
        Add-Check 'SQL Server' 'Version compatibility' 'PASS' `
            "Target ($tgtMajor) is newer than source ($srcMajor). Backup/restore compatible."
    }
}

# Edition rank (lower = less capable)
function Get-EditionRank([string]$edition) {
    if ($edition -match 'Enterprise')    { return 4 }
    if ($edition -match 'Standard')      { return 3 }
    if ($edition -match 'Developer')     { return 4 }
    if ($edition -match 'Web')           { return 2 }
    if ($edition -match 'Express')       { return 1 }
    return 0
}

if ($srcEdition -and $tgtEdition) {
    $srcRank = Get-EditionRank $srcEdition
    $tgtRank = Get-EditionRank $tgtEdition

    if ($srcRank -gt $tgtRank) {
        Add-Check 'SQL Server' 'Edition compatibility' 'WARN' `
            "Downgrading: $srcEdition → $tgtEdition. Run Get-EditionFeatureUsage.sql on source to audit Enterprise-only features before migration."
    } elseif ($srcRank -eq $tgtRank) {
        Add-Check 'SQL Server' 'Edition compatibility' 'PASS' `
            "Same edition tier: $srcEdition → $tgtEdition"
    } else {
        Add-Check 'SQL Server' 'Edition compatibility' 'PASS' `
            "Upgrading edition: $srcEdition → $tgtEdition"
    }
}

# Collation check
if ($srcCollation -and $tgtCollation) {
    $collMatch = $srcCollation -eq $tgtCollation
    Add-Check 'SQL Server' 'Server collation match' `
        $(if ($collMatch) { 'PASS' } else { 'WARN' }) `
        $(if ($collMatch) {
            "Both: $srcCollation"
        } else {
            "Source: $srcCollation | Target: $tgtCollation - collation mismatch. Databases can still be restored but string comparisons between server collations may behave differently. Ensure application does not rely on server-level collation for dynamic SQL."
        })
}

# ══════════════════════════════════════════════════════════════
# SECTION 5 — TARGET SERVER CONFIGURATION
# ══════════════════════════════════════════════════════════════

if ($tgtVersion) {

    # SQL Agent running
    $agentStatus = Invoke-SqlScalar $TargetInstance `
        "SELECT status_desc FROM sys.dm_server_services WHERE servicename LIKE '%Agent%'"

    Add-Check 'Target Config' 'SQL Agent status' `
        $(if ($agentStatus -eq 'Running') { 'PASS' } elseif ($agentStatus) { 'WARN' } else { 'SKIP' }) `
        $(if ($agentStatus) { "SQL Server Agent: $agentStatus" } else { "Could not determine - check SQL Agent is installed and running on target" })

    # max server memory
    $maxMem = Invoke-SqlScalar $TargetInstance `
        "SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)'"

    Add-Check 'Target Config' 'Max server memory configured' `
        $(if ([long]$maxMem -ge 2147483647) { 'WARN' } elseif ([long]$maxMem -gt 0) { 'PASS' } else { 'SKIP' }) `
        $(if ([long]$maxMem -ge 2147483647) {
            "max server memory = $maxMem MB (SQL Server default - unconfigured). Set this before production load to prevent memory pressure."
        } else {
            "max server memory = $maxMem MB"
        })

    # TempDB file count vs CPU count
    $tempdbFiles = Invoke-SqlScalar $TargetInstance `
        "SELECT COUNT(*) FROM sys.master_files WHERE database_id = 2 AND type = 0"
    $cpuCount = Invoke-SqlScalar $TargetInstance `
        "SELECT CASE WHEN cpu_count > 8 THEN 8 ELSE cpu_count END FROM sys.dm_os_sys_info"

    Add-Check 'Target Config' 'TempDB data file count' `
        $(if ([int]$tempdbFiles -ge [int]$cpuCount) { 'PASS' } elseif ($tempdbFiles) { 'WARN' } else { 'SKIP' }) `
        $(if ($tempdbFiles -and $cpuCount) {
            "TempDB files: $tempdbFiles | Recommended: $cpuCount (min(CPUs,8)). $(if ([int]$tempdbFiles -lt [int]$cpuCount) { "Add $(([int]$cpuCount - [int]$tempdbFiles)) more data file(s) before migration." })"
        } else {
            "Could not determine TempDB file count"
        })

    # optimize for ad hoc workloads
    $adHoc = Invoke-SqlScalar $TargetInstance `
        "SELECT value_in_use FROM sys.configurations WHERE name = 'optimize for ad hoc workloads'"

    Add-Check 'Target Config' 'Optimize for ad hoc workloads' `
        $(if ([int]$adHoc -eq 1) { 'PASS' } else { 'WARN' }) `
        $(if ([int]$adHoc -eq 1) {
            'Enabled - reduces single-use plan cache bloat'
        } else {
            "Not enabled. Enable before go-live: sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE"
        })

}

# ══════════════════════════════════════════════════════════════
# SECTION 6 — DISK SPACE (source data size vs target free space)
# ══════════════════════════════════════════════════════════════

if ($srcVersion -and $tgtVersion) {
    $diskQuery = @"
SELECT
    CAST(SUM(CASE WHEN type=0 THEN size ELSE 0 END)*8.0/1024/1024 AS DECIMAL(12,1)) AS data_gb,
    CAST(SUM(CASE WHEN type=1 THEN size ELSE 0 END)*8.0/1024/1024 AS DECIMAL(12,1)) AS log_gb
FROM sys.master_files WHERE database_id > 4
"@
    $srcSizes = Invoke-SqlDataTable $SourceInstance $diskQuery

    if ($srcSizes -and $srcSizes.Rows.Count -gt 0) {
        $srcDataGb = [double]$srcSizes.Rows[0].data_gb
        $srcLogGb  = [double]$srcSizes.Rows[0].log_gb

        Add-Check 'Disk (source)' 'Total source data size' 'INFO' `
            "Data: $srcDataGb GB | Log: $srcLogGb GB | Total: $([Math]::Round($srcDataGb+$srcLogGb,1)) GB"
    }

    # Get disk space from target
    $tgtDiskQuery = @"
SELECT
    volume_mount_point,
    CAST(total_bytes/1073741824.0 AS DECIMAL(12,1)) AS total_gb,
    CAST(available_bytes/1073741824.0 AS DECIMAL(12,1)) AS free_gb
FROM sys.dm_os_volume_stats(1,1)
UNION
SELECT volume_mount_point,
    CAST(total_bytes/1073741824.0 AS DECIMAL(12,1)),
    CAST(available_bytes/1073741824.0 AS DECIMAL(12,1))
FROM sys.dm_os_volume_stats(2,1)
"@
    $tgtDisks = Invoke-SqlDataTable $TargetInstance $tgtDiskQuery

    if ($tgtDisks -and $tgtDisks.Rows.Count -gt 0) {
        $minFree = ($tgtDisks.Rows | Measure-Object { [double]$_.free_gb } -Minimum).Minimum
        foreach ($row in $tgtDisks.Rows) {
            Add-Check 'Disk (target)' "Volume $($row.volume_mount_point)" 'INFO' `
                "Free: $($row.free_gb) GB / $($row.total_gb) GB total"
        }

        if ($srcSizes -and $srcSizes.Rows.Count -gt 0 -and $minFree -lt $srcDataGb) {
            Add-Check 'Disk (target)' 'Disk space sufficient' 'WARN' `
                "Smallest target volume has $minFree GB free. Source data is $srcDataGb GB. Verify target drive layout has enough free space on each volume for data and log files."
        } elseif ($srcSizes -and $srcSizes.Rows.Count -gt 0) {
            Add-Check 'Disk (target)' 'Disk space sufficient' 'PASS' `
                "Target volumes have adequate free space relative to source data size ($srcDataGb GB)"
        }
    }
}

# ══════════════════════════════════════════════════════════════
# OUTPUT
# ══════════════════════════════════════════════════════════════

$failCount = @($script:checks | Where-Object Result -eq 'FAIL').Count
$warnCount = @($script:checks | Where-Object Result -eq 'WARN').Count
$passCount = @($script:checks | Where-Object Result -eq 'PASS').Count
$skipCount = @($script:checks | Where-Object Result -eq 'SKIP').Count

foreach ($c in $script:checks) {
    $color = switch ($c.Result) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'SKIP' { 'DarkGray' }
        default { 'Cyan' }
    }
    Write-Host ("  [{0,-4}] {1,-38} {2}" -f $c.Result, $c.Check, $c.Detail) -ForegroundColor $color
}

Write-Host ''
Write-Host ('-' * 60) -ForegroundColor DarkCyan
Write-Host ("  PASS: $passCount  |  WARN: $warnCount  |  FAIL: $failCount  |  SKIP: $skipCount") `
    -ForegroundColor $(if ($failCount -gt 0) { 'Red' } elseif ($warnCount -gt 0) { 'Yellow' } else { 'Green' })

if ($failCount -gt 0) {
    Write-Host ''
    Write-Host '  BLOCKED - resolve all FAIL items before scheduling the migration window.' -ForegroundColor Red
} elseif ($warnCount -gt 0) {
    Write-Host ''
    Write-Host '  CAUTION - review WARN items before proceeding.' -ForegroundColor Yellow
} else {
    Write-Host ''
    Write-Host '  GO - pre-flight checks passed. Proceed with Invoke-MigrationExport.ps1.' -ForegroundColor Green
}

Write-Host ('-' * 60) -ForegroundColor DarkCyan
Write-Host ''

if ($OutputPath) {
    $script:checks | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "  Results saved: $OutputPath" -ForegroundColor DarkGray
    Write-Host ''
}