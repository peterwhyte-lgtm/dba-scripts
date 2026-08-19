<#
.SYNOPSIS
OS-level configuration checks not visible via SQL DMVs: power plan, page file, pending reboot.

.DESCRIPTION
Complements Get-OsConfigurationChecks.sql (which covers LPIM, NUMA, IFI via DMVs).
This script checks Windows-level settings that cause SQL Server performance issues
but are invisible from inside SQL: Balanced power plan throttles CPU under load,
undersized page file causes OS instability, pending reboot after Windows Update
leaves security patches unapplied and can cause unexpected restarts.

.NOTES
ScriptType  : automation
TargetScope : single server
RiskLevel   : SAFE
#>

param(
    [string]$ComputerName  = $env:COMPUTERNAME,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat  = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$findings = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Finding {
    param([string]$Check, [string]$CurrentValue, [string]$ExpectedValue, [string]$Status, [string]$Detail)
    $findings.Add([PSCustomObject]@{
        check          = $Check
        current_value  = $CurrentValue
        expected_value = $ExpectedValue
        status         = $Status
        detail         = $Detail
    })
}

# --- Power Plan ---
try {
    # For local machine, skip -ComputerName to avoid DCOM/WMI network path failures
    $isLocal    = $ComputerName -eq $env:COMPUTERNAME -or
                  $ComputerName -eq 'localhost'        -or
                  $ComputerName -eq '.'
    $cimSplat   = if ($isLocal) { @{} } else { @{ ComputerName = $ComputerName } }

    $activePlan = Get-CimInstance -ClassName Win32_PowerPlan -Namespace root\cimv2\power `
                      -Filter "IsActive = 'True'" @cimSplat -ErrorAction Stop |
                  Select-Object -First 1

    $planName = $activePlan.ElementName
    $status   = if ($planName -like '*High Performance*' -or $planName -like '*Ultimate Performance*') {
                    'OK'
                } elseif ($planName -like '*Balanced*') {
                    'CRITICAL'
                } else {
                    'WARN'
                }
    $detail   = if ($status -eq 'CRITICAL') {
                    'Balanced plan throttles CPU frequency under load - causes erratic query response times. Set to High Performance.'
                } elseif ($status -eq 'WARN') {
                    "Unknown plan '$planName' - verify it does not use CPU throttling."
                } else { 'No action required.' }

    Add-Finding 'Power Plan' $planName 'High Performance or Ultimate Performance' $status $detail
}
catch {
    Add-Finding 'Power Plan' 'Could not read' 'High Performance' 'WARN' "WMI query failed: $_"
}

# --- Page File ---
try {
    $pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage @cimSplat -ErrorAction Stop

    if (-not $pageFiles) {
        Add-Finding 'Page File' 'None configured' 'System-managed or fixed' 'WARN' `
            'No page file detected. SQL Server requires a page file even with LPIM; absence can cause OS crashes under memory pressure.'
    }
    else {
        foreach ($pf in $pageFiles) {
            $currentMb  = [math]::Round($pf.CurrentUsage)
            $allocMb    = [math]::Round($pf.AllocatedBaseSize)
            $physMemGb  = [math]::Round((Get-CimInstance Win32_ComputerSystem @cimSplat).TotalPhysicalMemory / 1GB, 1)
            $minRecommendMb = [math]::Max(1024, [int]($physMemGb * 1024 * 0.1))  # at least 10% of RAM or 1 GB

            $status = if ($allocMb -lt $minRecommendMb) { 'WARN' } else { 'OK' }
            $detail = if ($status -eq 'WARN') {
                "Page file ($allocMb MB) may be too small for $physMemGb GB RAM. Recommend at least $minRecommendMb MB."
            } else { "Page file is $allocMb MB; current usage $currentMb MB." }

            Add-Finding 'Page File' "$allocMb MB on $($pf.Name)" "≥ $minRecommendMb MB" $status $detail
        }
    }
}
catch {
    Add-Finding 'Page File' 'Could not read' 'System-managed' 'WARN' "WMI query failed: $_"
}

# --- Pending Reboot ---
try {
    $pendingReboot = $false
    $rebootReasons = @()

    $cbsKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuKey  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    $pfroKey= "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"

    if (Test-Path $cbsKey) { $pendingReboot = $true; $rebootReasons += 'Windows component update' }
    if (Test-Path $wuKey)  { $pendingReboot = $true; $rebootReasons += 'Windows Update' }

    $pfro = Get-ItemProperty -Path $pfroKey -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($pfro) { $pendingReboot = $true; $rebootReasons += 'Pending file rename operations' }

    $status = if ($pendingReboot) { 'WARN' } else { 'OK' }
    $value  = if ($pendingReboot) { 'YES - ' + ($rebootReasons -join ', ') } else { 'No' }
    $detail = if ($pendingReboot) {
        'A reboot is pending. SQL Server will restart unexpectedly at next planned/unplanned reboot unless scheduled.'
    } else { 'No pending reboot detected.' }

    Add-Finding 'Pending Reboot' $value 'No' $status $detail
}
catch {
    Add-Finding 'Pending Reboot' 'Could not determine' 'No' 'WARN' "Registry check failed: $_"
}

# --- Output ---
$results = $findings | Sort-Object {
    switch ($_.status) { 'CRITICAL' { 1 } 'WARN' { 2 } 'INFO' { 3 } default { 4 } }
}

if ($OutputFormat -eq 'Csv') {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile   = if ($OutputPath) { $OutputPath } else {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..') -ErrorAction SilentlyContinue
        $outDir   = if ($repoRoot) { Join-Path $repoRoot 'output-files\reviews\inventory' } else { $PWD }
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        Join-Path $outDir "Test-OsConfiguration-$timestamp.csv"
    }
    $results | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "Output saved: $outFile" -ForegroundColor Green
}
else {
    $results | Format-Table -AutoSize
}
