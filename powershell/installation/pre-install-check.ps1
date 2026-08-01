<#
.SYNOPSIS
Run pre-installation checks before deploying SQL Server.

.DESCRIPTION
Validates the machine is ready for SQL Server installation. Reports PASS / WARN / FAIL
for each check. Does not make any changes to the system.

.PARAMETER InstanceName
Target instance name to check for existing installs. Default: MSSQLSERVER.

.PARAMETER InstallDir
Planned SQL Server binary directory — checked for disk space.

.PARAMETER DataDir
Planned data directory — checked for disk space.

.PARAMETER LogDir
Planned log directory — checked for disk space.

.PARAMETER SqlVersion
SQL Server version being installed (2016|2017|2019|2022). Default: 2022.

.EXAMPLE
.\admin\installation\pre-install-check.ps1
.\admin\installation\pre-install-check.ps1 -SqlVersion 2019 -DataDir D:\SQLData
#>
param(
    [string]$InstanceName = 'MSSQLSERVER',
    [string]$InstallDir   = 'C:\Program Files\Microsoft SQL Server',
    [string]$DataDir      = 'C:\SQLData',
    [string]$LogDir       = 'C:\SQLLogs',
    [ValidateSet('2016','2017','2019','2022')]
    [string]$SqlVersion   = '2022'
)

$ErrorActionPreference = 'SilentlyContinue'

$pass  = 0; $warn = 0; $fail = 0
$results = [System.Collections.Generic.List[PSObject]]::new()

function Add-Check {
    param([string]$Category, [string]$Check, [string]$Status, [string]$Detail)
    $color = switch ($Status) { 'PASS'{'Green'} 'WARN'{'Yellow'} 'FAIL'{'Red'} default{'White'} }
    $results.Add([PSCustomObject]@{ Category=$Category; Check=$Check; Status=$Status; Detail=$Detail })
    Write-Host ("  [{0,-4}] {1,-38} {2}" -f $Status, $Check, $Detail) -ForegroundColor $color
    switch ($Status) { 'PASS'{$script:pass++} 'WARN'{$script:warn++} 'FAIL'{$script:fail++} }
}

Write-Host ""
Write-Host "  SQL Server $SqlVersion Pre-Install Checks" -ForegroundColor Cyan
Write-Host ("  " + [string]::new('-',60)) -ForegroundColor DarkCyan
Write-Host ""

# ── Admin elevation ───────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
               [Security.Principal.WindowsBuiltInRole]::Administrator)
Add-Check 'System' 'Running as Administrator' `
    $(if ($isAdmin) {'PASS'} else {'FAIL'}) `
    $(if ($isAdmin) {'Elevated'} else {'Re-run as Administrator'})

# ── OS version ────────────────────────────────────────────────────────────────
$os      = Get-CimInstance Win32_OperatingSystem
$osBuild = [int]$os.BuildNumber
$osName  = $os.Caption

$minBuild = switch ($SqlVersion) {
    '2022' { 17763 }  # Windows Server 2019
    '2019' { 14393 }  # Windows Server 2016
    '2017' { 14393 }  # Windows Server 2016
    '2016' { 9600  }  # Windows Server 2012 R2
}
$osStatus = if ($osBuild -ge $minBuild) {'PASS'} else {'FAIL'}
Add-Check 'System' 'OS version' $osStatus "$osName (Build $osBuild)"

# ── Pending reboot ────────────────────────────────────────────────────────────
$pendingReboot = $false
$rebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
)
foreach ($key in $rebootKeys) {
    if (Test-Path $key) { $pendingReboot = $true; break }
}
Add-Check 'System' 'No pending reboot' `
    $(if ($pendingReboot) {'WARN'} else {'PASS'}) `
    $(if ($pendingReboot) {'Pending reboot detected — install may fail'} else {'Clean'})

# ── RAM ───────────────────────────────────────────────────────────────────────
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$ramStatus = if ($ramGB -ge 8) {'PASS'} elseif ($ramGB -ge 4) {'WARN'} else {'FAIL'}
Add-Check 'Hardware' 'RAM' $ramStatus "$ramGB GB $(if ($ramGB -lt 8) {'(8 GB recommended)'})"

# ── CPU count ─────────────────────────────────────────────────────────────────
$cpus = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Add-Check 'Hardware' 'Logical CPUs' 'PASS' "$cpus processors"

# ── .NET Framework ────────────────────────────────────────────────────────────
$netKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
$netVer = $netKey.Release
$netStatus = if ($netVer -ge 461808) {'PASS'} elseif ($netVer -ge 394802) {'WARN'} else {'FAIL'}
$netLabel  = if ($netVer -ge 528040) {'4.8+'} elseif ($netVer -ge 461808) {'4.7.2'} elseif ($netVer -ge 394802) {'4.6.2'} else {"$netVer (4.7.2+ required)"}
Add-Check 'Prerequisites' '.NET Framework' $netStatus $netLabel

# ── PowerShell version ────────────────────────────────────────────────────────
$psVer = $PSVersionTable.PSVersion
$psStatus = if ($psVer.Major -ge 5) {'PASS'} else {'WARN'}
Add-Check 'Prerequisites' 'PowerShell version' $psStatus "$($psVer.Major).$($psVer.Minor)"

# ── Disk space ────────────────────────────────────────────────────────────────
$diskChecks = @(
    @{ Path=$InstallDir; Label='Install dir';  MinGB=20 },
    @{ Path=$DataDir;    Label='Data dir';     MinGB=50 },
    @{ Path=$LogDir;     Label='Log dir';      MinGB=20 }
)
foreach ($dc in $diskChecks) {
    $drive   = Split-Path -Qualifier $dc.Path
    $psDrive = Get-PSDrive ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($psDrive) {
        $freeGB = [math]::Round($psDrive.Free / 1GB, 1)
        $status = if ($freeGB -ge $dc.MinGB) {'PASS'} elseif ($freeGB -ge ($dc.MinGB / 2)) {'WARN'} else {'FAIL'}
        Add-Check 'Disk' $dc.Label $status "$freeGB GB free on $drive (need $($dc.MinGB) GB)"
    } else {
        Add-Check 'Disk' $dc.Label 'WARN' "Drive $drive not found — will be created"
    }
}

# ── TCP port 1433 availability ────────────────────────────────────────────────
$port1433InUse = $false
try {
    $tcpConn = Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue
    if ($tcpConn) { $port1433InUse = $true }
} catch {
    Write-Error $_
    throw
}
Add-Check 'Network' 'TCP port 1433' `
    $(if ($port1433InUse) {'WARN'} else {'PASS'}) `
    $(if ($port1433InUse) {'Already in use — check existing SQL instance'} else {'Available'})

# ── Existing SQL Server instances ─────────────────────────────────────────────
$regInstances = @()
$regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
if (Test-Path $regPath) {
    $regInstances = Get-ItemProperty $regPath |
        Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -notmatch '^PS' } |
        Select-Object -ExpandProperty Name
}

if ($regInstances.Count -eq 0) {
    Add-Check 'SQL Server' 'Existing instances' 'PASS' 'None found'
} elseif ($regInstances -contains $InstanceName) {
    Add-Check 'SQL Server' 'Existing instances' 'FAIL' "Instance '$InstanceName' already exists: $($regInstances -join ', ')"
} else {
    Add-Check 'SQL Server' 'Existing instances' 'WARN' "Other instances present: $($regInstances -join ', ')"
}

# ── Windows Firewall ──────────────────────────────────────────────────────────
try {
    $fwProfile = (Get-NetFirewallProfile -ErrorAction Stop | Where-Object Enabled -eq $true | Select-Object -First 1).Name
    if ($fwProfile) {
        Add-Check 'Network' 'Windows Firewall' 'WARN' "Active profile: $fwProfile — ensure port 1433 rule is added post-install"
    } else {
        Add-Check 'Network' 'Windows Firewall' 'PASS' 'No active firewall profiles'
    }
} catch {
    Add-Check 'Network' 'Windows Firewall' 'WARN' 'Could not check firewall state'
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("  " + [string]::new('=',60)) -ForegroundColor DarkCyan
$summaryColor = if ($fail -gt 0) {'Red'} elseif ($warn -gt 0) {'Yellow'} else {'Green'}
$verdict      = if ($fail -gt 0) {'NOT READY — fix FAIL items before proceeding'} `
                elseif ($warn -gt 0) {'READY WITH WARNINGS — review WARN items'} `
                else {'READY — all checks passed'}
Write-Host "  $verdict" -ForegroundColor $summaryColor
Write-Host "  PASS: $pass   WARN: $warn   FAIL: $fail" -ForegroundColor $summaryColor
Write-Host ""