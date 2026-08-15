<#
.SYNOPSIS
Patch this machine's SQL Server to the latest Cumulative Update. One file, no config.

.DESCRIPTION
Self-contained single-server patcher:
  1. Detects every local SQL Server instance and its current build
  2. Compares against the embedded latest-CU table below (kept current with the
     sqldba.blog builds reference, regenerated each patch cycle)
  3. Uses your downloaded installer (-InstallerPath), a previously downloaded copy in
     the download folder, or downloads it when a direct URL is available
  4. Confirms, installs quietly (all instances of that version), and verifies after

For patching a whole estate from a config file, use sql\Invoke-SqlPatch.ps1 instead.

.PARAMETER InstallerPath
Path to an already-downloaded CU installer exe. Skips any download logic.

.PARAMETER DownloadFolder
Where installers are kept/downloaded. Default C:\SQLPatches.

.PARAMETER Preview
Show what would happen and exit. Never needs admin, never changes anything.

.PARAMETER Force
Skip the confirmation prompt.

.EXAMPLE
.\Patch-SqlServer.ps1 -Preview
.\Patch-SqlServer.ps1
.\Patch-SqlServer.ps1 -InstallerPath C:\Temp\SQLServer2025-KB5104822-x64.exe

.NOTES
Type      : runner
Scope     : single server (local machine only)
RiskLevel : HIGH IMPACT - installs a Cumulative Update; SQL Server restarts mid-install.
#>
param(
    [string]$InstallerPath,
    [string]$DownloadFolder = 'C:\SQLPatches',
    [switch]$Preview,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# -- BEGIN GENERATED LATEST-CU TABLE (source: sqldba.blog builds reference) -------
# Regenerated each patch cycle by gen-patch-map.py from sql-builds.json.
# Url is the direct installer link where Microsoft publishes one; when blank, the
# script opens the KB page for you and you rerun with -InstallerPath.
$latest = @{
    17 = @{ Label = 'SQL Server 2025 CU8';  Build = '17.0.4075.5'; KB = 'KB5104822'; KbUrl = 'https://support.microsoft.com/help/5104822'; Url = ''; FileName = 'SQLServer2025-KB5104822-x64.exe' }
    16 = @{ Label = 'SQL Server 2022 CU26'; Build = '16.0.4265.3'; KB = 'KB5093420'; KbUrl = 'https://support.microsoft.com/help/5093420'; Url = ''; FileName = 'SQLServer2022-KB5093420-x64.exe' }
    15 = @{ Label = 'SQL Server 2019 CU32'; Build = '15.0.4430.1'; KB = 'KB5054833'; KbUrl = 'https://support.microsoft.com/help/5054833'; Url = 'https://download.microsoft.com/download/6/e/7/6e72dddf-dfa4-4889-bc3d-e5d3a0fd11ce/SQLServer2019-KB5054833-x64.exe'; FileName = 'SQLServer2019-KB5054833-x64.exe' }
    14 = @{ Label = 'SQL Server 2017 CU31 + GDR'; Build = '14.0.3495.9'; KB = 'KB5058714'; KbUrl = 'https://support.microsoft.com/help/5058714'; Url = ''; FileName = 'SQLServer2017-KB5058714-x64.exe' }
}
# -- END GENERATED LATEST-CU TABLE ------------------------------------------------

function Write-Step([string]$msg, [string]$color = 'Cyan') { Write-Host "  $msg" -ForegroundColor $color }

Write-Host ''
Write-Step "Patch-SqlServer - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Host ('  ' + [string]::new('-', 68)) -ForegroundColor DarkCyan

# 1. Detect local instances + versions ---------------------------------------------
$regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
if (-not (Test-Path $regPath)) { Write-Step 'No SQL Server instances found on this machine.' 'Yellow'; exit 0 }
$instNames = Get-ItemProperty $regPath | Get-Member -MemberType NoteProperty |
    Where-Object { $_.Name -notmatch '^PS' } | Select-Object -ExpandProperty Name

$found = @()
foreach ($inst in ($instNames | Sort-Object)) {
    $srv = if ($inst -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$inst" }
    $ver = $null
    try {
        $row = Invoke-Sqlcmd -ServerInstance $srv -QueryTimeout 8 -TrustServerCertificate `
            -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)) AS pv"
        $ver = $row.pv
    } catch {
        $instId = (Get-ItemProperty $regPath).$inst
        $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instId\MSSQLServer\CurrentVersion" -ErrorAction SilentlyContinue).CurrentVersion
    }
    if ($ver) { $found += [pscustomobject]@{ Instance = $inst; Build = $ver; Major = [int]($ver -split '\.')[0] } }
}
if ($found.Count -eq 0) { Write-Step 'Instances exist but no version could be read.' 'Yellow'; exit 1 }

# 2. Compare against the latest-CU table -------------------------------------------
$behind = @()
Write-Host ''
foreach ($f in $found) {
    $t = $latest[$f.Major]
    if (-not $t) {
        Write-Step ("{0,-22} {1,-15} no CU-train target for this version; see the builds reference" -f $f.Instance, $f.Build) 'Yellow'
        continue
    }
    if ([version]$f.Build -ge [version]$t.Build) {
        Write-Step ("{0,-22} {1,-15} already current ({2})" -f $f.Instance, $f.Build, $t.Label) 'Green'
    } else {
        Write-Step ("{0,-22} {1,-15} BEHIND -> {2} ({3})" -f $f.Instance, $f.Build, $t.Build, $t.Label) 'Yellow'
        $behind += $f
    }
}
if ($behind.Count -eq 0) { Write-Host ''; Write-Step 'Nothing to do.' 'Green'; exit 0 }

$target = $latest[($behind | Select-Object -First 1).Major]
Write-Host ''
Write-Step "Target: $($target.Label)  $($target.Build)  ($($target.KB))"

if ($Preview) { Write-Step '[Preview] Stopping here; nothing downloaded or installed.' 'Yellow'; exit 0 }

# 3. Locate or fetch the installer -------------------------------------------------
$installer = $null
if ($InstallerPath) {
    if (-not (Test-Path $InstallerPath)) { Write-Step "InstallerPath not found: $InstallerPath" 'Red'; exit 1 }
    $installer = $InstallerPath
} else {
    $cached = Join-Path $DownloadFolder $target.FileName
    if (Test-Path $cached) {
        Write-Step "Using previously downloaded installer: $cached"
        $installer = $cached
    } elseif ($target.Url) {
        New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
        Write-Step "Downloading $($target.KB)..."
        Start-BitsTransfer -Source $target.Url -Destination $cached
        $installer = $cached
    } else {
        Write-Step 'Microsoft does not publish a direct link for this CU.' 'Yellow'
        Write-Step "Opening the KB page - use its download button, then rerun with:" 'Yellow'
        Write-Step "  .\Patch-SqlServer.ps1 -InstallerPath <path-to-$($target.FileName)>" 'Yellow'
        Start-Process $target.KbUrl
        exit 1
    }
}

# 4. Confirm and install -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Step 'Run from an ADMIN PowerShell to install.' 'Red'; exit 1 }

if (-not $Force) {
    Write-Host ''
    Write-Step "About to install $($target.Label). SQL Server restarts during the install." 'Yellow'
    if ((Read-Host '  Type Y to continue') -ne 'Y') { Write-Step 'Cancelled.' 'Yellow'; exit 0 }
}

Write-Step 'Installing (quiet, all instances of this version)...'
$proc = Start-Process -FilePath $installer `
    -ArgumentList '/quiet', '/IAcceptSQLServerLicenseTerms', '/allinstances' `
    -Wait -PassThru

switch ($proc.ExitCode) {
    0     { Write-Step 'Installer finished: success.' 'Green' }
    3010  { Write-Step 'Installer finished: success, REBOOT REQUIRED to complete.' 'Yellow' }
    default {
        Write-Step "Installer exit code $($proc.ExitCode) - check the newest Summary.txt under" 'Red'
        Write-Step '  C:\Program Files\Microsoft SQL Server\<nnn>\Setup Bootstrap\Log\' 'Red'
        exit $proc.ExitCode
    }
}

# 5. Verify ------------------------------------------------------------------------
Write-Host ''
Write-Step 'After:'
foreach ($f in $behind) {
    $srv = if ($f.Instance -eq 'MSSQLSERVER') { 'localhost' } else { "localhost\$($f.Instance)" }
    try {
        $row = Invoke-Sqlcmd -ServerInstance $srv -QueryTimeout 30 -TrustServerCertificate `
            -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(20)) AS pv"
        $ok = [version]$row.pv -ge [version]$target.Build
        Write-Step ("{0,-22} {1,-15} {2}" -f $f.Instance, $row.pv, $(if ($ok) { 'CURRENT' } else { 'still behind?' })) $(if ($ok) { 'Green' } else { 'Yellow' })
    } catch { Write-Step ("{0,-22} (not answering yet - normal right after restart)" -f $f.Instance) 'Yellow' }
}
Write-Host ''
