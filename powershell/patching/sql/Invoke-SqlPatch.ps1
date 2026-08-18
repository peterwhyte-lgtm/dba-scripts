<#
.SYNOPSIS
Download and apply SQL Server Cumulative Updates to local or remote servers.

.DESCRIPTION
Reads server list and patch definitions from patch-config.psd1 (or a supplied config).
For each server and each installed SQL instance:
  - Detects the installed version via registry (no SQL connectivity required for version check)
  - Compares against the target version defined in the config
  - Reports if the server is already up to date or ahead of the configured target
  - Downloads the CU installer if not already present in PatchRoot
  - Applies the patch: locally via Start-Process, or remotely via WinRM + admin share

Remote prerequisites:
  - WinRM enabled on target servers (Test-WSMan <server> to verify)
  - Admin share accessible: \\server\D$\  (or whatever drive PatchRoot is on)
  - Script must run as a domain admin or account with local admin on target servers

.PARAMETER ConfigPath
Path to patch-config.psd1. Default: patch-config.psd1 in the same folder as this script.

.PARAMETER Server
Override the server list from the config file. Accepts one or more names.

.PARAMETER PatchRoot
Override the PatchRoot from the config file. Used as the local download folder and
mirrored on remote servers via admin share.

.PARAMETER Credential
PSCredential for WinRM connections to remote servers. Omit to use the current user.

.PARAMETER WhatIf
Report version status and planned actions without downloading or installing anything.

.PARAMETER DownloadOnly
Download CU installers to PatchRoot but do not install.

.PARAMETER Version
With -DownloadOnly: stage installers for the named config versions (e.g. SQL2025, or
just 2025 or 17) without touching or needing any local SQL Server instance. Useful for
downloading fleet installers from a workstation or jump box.

.PARAMETER Force
Skip the per-server install confirmation prompt.

.EXAMPLE
# Check status of all servers in config without making changes
.\Invoke-SqlPatch.ps1 -WhatIf

# Download all configured CU installers (no install)
.\Invoke-SqlPatch.ps1 -DownloadOnly

# Patch all servers in config (prompts before each install)
.\Invoke-SqlPatch.ps1

# Patch a single server, skip confirmation
.\Invoke-SqlPatch.ps1 -Server SQL01 -Force

# Patch multiple remote servers with alternate credentials
.\Invoke-SqlPatch.ps1 -Server SQL01,SQL02 -Credential (Get-Credential) -Force

.NOTES
RiskLevel   : HIGH IMPACT - applies a Cumulative Update; SQL Server restarts mid-install
#>
param(
    [string]$ConfigPath  = (Join-Path $PSScriptRoot 'patch-config.psd1'),
    [string[]]$Server,
    [string[]]$Version,
    [string]$PatchRoot,
    [PSCredential]$Credential,
    [switch]$WhatIf,
    [switch]$DownloadOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# -- Admin check --------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIf -and -not $DownloadOnly) {
    Write-Host 'ERROR: This script must be run as Administrator (or use -WhatIf to preview, -DownloadOnly to download only).' -ForegroundColor Red; exit 1
}

# -- Logging ------------------------------------------------------------------
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$logDir   = Join-Path $repoRoot 'output-files\patches'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logDir "sql-autopatch-$ts.log"

function Write-PatchLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

# -- Load config --------------------------------------------------------------
if (-not (Test-Path $ConfigPath)) {
    Write-PatchLog "Config not found: $ConfigPath" 'Red'; exit 1
}
$config = Import-PowerShellDataFile -Path $ConfigPath

$targetServers  = if ($Server)     { $Server }     else { $config.Servers }
$localPatchRoot = if ($PatchRoot)  { $PatchRoot }  else { $config.PatchRoot }

# Build lookup: MajorVersion (int) -> { SqlVersion; Config }
$versionMap = @{}
foreach ($key in $config.Patches.Keys) {
    $entry = $config.Patches[$key]
    $versionMap[[int]$entry.MajorVersion] = @{ SqlVersion = $key; Config = $entry }
}

Write-PatchLog "SQL Server Autopatch - $ts" 'Cyan'
Write-PatchLog "Config    : $ConfigPath"
Write-PatchLog "Servers   : $($targetServers -join ', ')"
Write-PatchLog "PatchRoot : $localPatchRoot"
if ($WhatIf)       { Write-PatchLog '[WhatIf - no changes will be made]' 'Yellow' }
if ($DownloadOnly) { Write-PatchLog '[DownloadOnly - will not install]' 'Yellow' }
Write-PatchLog ''

# -- Get SQL instances and versions -------------------------------------------
# Queries SERVERPROPERTY('ProductVersion') via SQL first - this reflects the true
# running version immediately after a patch, even before a pending reboot.
# Falls back to the registry only if the SQL service is unreachable.
function Get-SqlVersions {
    param([string]$ComputerName, [PSCredential]$Cred)

    $scriptBlock = {
        $base    = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
        $nameReg = "$base\Instance Names\SQL"
        if (-not (Test-Path $nameReg)) { return }

        (Get-ItemProperty $nameReg).PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object {
                $instName = $_.Name
                $instId   = $_.Value
                $srvConn  = if ($instName -eq 'MSSQLSERVER') { '.' } else { ".\$instName" }
                $curVer   = $null
                $source   = 'registry'

                # Try Invoke-Sqlcmd (SqlServer module)
                try {
                    $row = Invoke-Sqlcmd -ServerInstance $srvConn `
                        -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS v" `
                        -TrustServerCertificate -QueryTimeout 5 -ErrorAction Stop
                    if ($row.v) { $curVer = $row.v; $source = 'sql' }
                } catch { }

                # Try sqlcmd.exe fallback
                if (-not $curVer) {
                    try {
                        $out = & sqlcmd.exe -S $srvConn -Q "SET NOCOUNT ON;SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50))" -h -1 -W 2>&1
                        $line = $out | Where-Object { $_ -match '^\d+\.\d+' } | Select-Object -First 1
                        if ($line) { $curVer = $line.Trim(); $source = 'sql' }
                    } catch { }
                }

                # Registry fallback - may show pre-reboot version for patches that exit 3010
                if (-not $curVer) {
                    $verKey = "$base\$instId\MSSQLServer\CurrentVersion"
                    $curVer = (Get-ItemProperty $verKey -ErrorAction SilentlyContinue).CurrentVersion
                }

                if ($curVer) {
                    [pscustomobject]@{
                        Instance       = $instName
                        InstId         = $instId
                        MajorVersion   = [int]($curVer -split '\.')[0]
                        ProductVersion = $curVer
                        Source         = $source
                    }
                }
            }
    }

    $isLocal = $ComputerName -in '.', 'localhost', $env:COMPUTERNAME
    if ($isLocal) { return & $scriptBlock }

    $params = @{ ComputerName = $ComputerName; ScriptBlock = $scriptBlock }
    if ($Cred) { $params.Credential = $Cred }
    Invoke-Command @params
}

# -- Resolve a download link from the Microsoft Update Catalog ----------------
function Get-CatalogUrl([string]$kb) {
    try {
        $sr = Invoke-WebRequest -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=$kb" `
                -UseBasicParsing -TimeoutSec 60
        $m = [regex]::Match($sr.Content, 'goToDetails\("([0-9a-f-]{36})"')
        if (-not $m.Success) { return $null }
        $guid = $m.Groups[1].Value
        $body = @{ updateIDs = "[{`"size`":0,`"languages`":`"`",`"uidInfo`":`"$guid`",`"updateID`":`"$guid`"}]" }
        $dr = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
                -Method Post -Body $body -UseBasicParsing -TimeoutSec 60
        $u = [regex]::Match($dr.Content, "https?://[^'`"]+\.exe")
        if ($u.Success) { return $u.Value }
    } catch { }
    return $null
}

# -- Download CU installer if not already present -----------------------------
function Get-PatchFile {
    param([hashtable]$Entry, [string]$Root)

    $cfg  = $Entry.Config
    $dir  = Join-Path $Root "$($Entry.SqlVersion)\$($cfg.CU)_$($cfg.KB)"
    $file = Join-Path $dir $cfg.FileName

    if (Test-Path $file) {
        Write-PatchLog "    Already downloaded: $($cfg.FileName)" 'DarkGray'
        return $file
    }

    $url = $cfg.Url
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-PatchLog "    No direct link configured; asking the Microsoft Update Catalog for $($cfg.KB)..." 'Cyan'
        $url = Get-CatalogUrl $cfg.KB
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-PatchLog "    ERROR: No download URL for $($Entry.SqlVersion) ($($cfg.KB)) and the Catalog lookup failed." 'Red'
        Write-PatchLog "    Update patch-config.psd1 - see: https://learn.microsoft.com/en-us/troubleshooting/sql/releases/download-and-install-latest-updates" 'Red'
        return $null
    }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-PatchLog "    Downloading $($cfg.KB) ($($Entry.SqlVersion) $($cfg.CU))..." 'Cyan'

    try {
        Start-BitsTransfer -Source $url -Destination $file -DisplayName "SQL Patch: $($cfg.FileName)"
        $sizeMB = [math]::Round((Get-Item $file).Length / 1MB, 1)
        Write-PatchLog "    Downloaded: $($cfg.FileName) ($sizeMB MB)" 'Green'
        return $file
    }
    catch {
        Write-PatchLog "    Download failed: $($_.Exception.Message)" 'Red'
        if (Test-Path $file) { Remove-Item $file -Force }
        return $null
    }
}

# -- Convert local absolute path to UNC via admin share -----------------------
function ConvertTo-Unc {
    param([string]$LocalPath, [string]$ComputerName)
    # D:\SQLPatches\... -> \\SERVER\D$\SQLPatches\...
    if ($LocalPath -match '^([A-Za-z]):\\(.*)') {
        return "\\$ComputerName\$($Matches[1])`$\$($Matches[2])"
    }
    throw "Cannot convert '$LocalPath' to a UNC path (expected drive-letter path)."
}

# -- Apply patch on a remote server via WinRM ---------------------------------
function Invoke-RemotePatch {
    param(
        [string]$ComputerName,
        [string]$LocalInstaller,
        [string]$RemotePatchRoot,
        [hashtable]$Entry,
        [PSCredential]$Cred
    )

    $cfg     = $Entry.Config
    $remDir  = Join-Path $RemotePatchRoot "$($Entry.SqlVersion)\$($cfg.CU)_$($cfg.KB)"
    $remFile = Join-Path $remDir $cfg.FileName

    $sessionParams = @{ ComputerName = $ComputerName }
    if ($Cred) { $sessionParams.Credential = $Cred }
    $session = New-PSSession @sessionParams

    try {
        # Ensure the remote folder exists
        Invoke-Command -Session $session -ScriptBlock {
            New-Item -ItemType Directory -Path $Using:remDir -Force | Out-Null
        }

        # Copy installer via admin share (handles large files; admin share must be accessible)
        $uncFile = ConvertTo-Unc -LocalPath $remFile -ComputerName $ComputerName
        if (-not (Test-Path $uncFile)) {
            Write-PatchLog "    Copying installer to \\$ComputerName..." 'Cyan'
            Copy-Item -Path $LocalInstaller -Destination $uncFile
            Write-PatchLog "    Copy complete." 'Green'
        }
        else {
            Write-PatchLog "    Installer already present on $ComputerName." 'DarkGray'
        }

        # Run installer silently on the remote server
        Write-PatchLog "    Running installer on $ComputerName..." 'Cyan'
        $exitCode = Invoke-Command -Session $session -ScriptBlock {
            $proc = Start-Process -FilePath $Using:remFile `
                -ArgumentList '/quiet', '/IAcceptSQLServerLicenseTerms', '/allinstances' `
                -Wait -PassThru
            $proc.ExitCode
        }

        return $exitCode
    }
    finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}

# -- Apply patch on the local machine -----------------------------------------
function Invoke-LocalPatch {
    param([string]$Installer)

    Write-PatchLog "    Running installer locally..." 'Cyan'
    $proc = Start-Process -FilePath $Installer `
        -ArgumentList '/quiet', '/IAcceptSQLServerLicenseTerms', '/allinstances' `
        -Wait -PassThru `
        -RedirectStandardOutput "$logFile.stdout" `
        -RedirectStandardError  "$logFile.stderr"
    return $proc.ExitCode
}

# -- Handle installer exit code -----------------------------------------------
function Write-PatchResult {
    param([int]$ExitCode, [string]$Server)
    switch ($ExitCode) {
        0    { Write-PatchLog "    Patch applied successfully on $Server." 'Green';          return 'Patched' }
        3010 { Write-PatchLog "    Patch applied on $Server - reboot required." 'Yellow';   return 'PatchedRebootNeeded' }
        default {
            Write-PatchLog "    Patch FAILED on $Server (exit $ExitCode). See: $logFile" 'Red'
            return "Failed(exit$ExitCode)"
        }
    }
}

# -- Version-only download: stage installers with no local SQL Server needed ---
if ($Version) {
    if (-not $DownloadOnly) {
        Write-PatchLog '-Version is a download-staging option; add -DownloadOnly to use it.' 'Red'
        exit 1
    }
    $ok = $true
    foreach ($v in $Version) {
        $entry = $null
        foreach ($key in $config.Patches.Keys) {
            $e = $config.Patches[$key]
            if ($key -ieq $v -or $key -ieq "SQL$v" -or "$($e.MajorVersion)" -eq $v) {
                $entry = @{ SqlVersion = $key; Config = $e }; break
            }
        }
        if (-not $entry) {
            Write-PatchLog "No config block matches -Version '$v' (known: $($config.Patches.Keys -join ', '))." 'Red'
            $ok = $false; continue
        }
        Write-PatchLog "--- staging installer: $($entry.SqlVersion) $($entry.Config.CU) ---" 'Cyan'
        if (-not (Get-PatchFile -Entry $entry -Root $localPatchRoot)) { $ok = $false }
    }
    Write-PatchLog ''
    Write-PatchLog "Installers staged under: $localPatchRoot" $(if ($ok) { 'Green' } else { 'Yellow' })
    exit $(if ($ok) { 0 } else { 1 })
}

# -- Main loop ----------------------------------------------------------------
$results = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($srv in $targetServers) {

    Write-PatchLog "--- $srv -----------------------------------------" 'Cyan'

    try {
        $sqlInstances = @(Get-SqlVersions -ComputerName $srv -Cred $Credential)
    }
    catch {
        Write-PatchLog "  ERROR connecting to $srv - $($_.Exception.Message)" 'Red'
        $results.Add([pscustomobject]@{ Server=$srv; Instance='?'; Installed='?'; Target='?'; Status='ConnectionFailed' })
        continue
    }

    if ($sqlInstances.Count -eq 0) {
        Write-PatchLog "  No SQL Server instances found on $srv." 'Yellow'
        continue
    }

    foreach ($inst in $sqlInstances) {

        $current = [Version]$inst.ProductVersion
        $major   = $inst.MajorVersion
        $name    = $inst.Instance

        $srcNote = if ($inst.Source -eq 'registry') { ' (registry - reboot may be pending)' } else { '' }
        Write-PatchLog "  Instance  : $name  ($($inst.InstId))"
        Write-PatchLog "  Installed : $($inst.ProductVersion)$srcNote"

        if (-not $versionMap.ContainsKey($major)) {
            Write-PatchLog "  Status    : No patch configured for SQL major version $major - skipping." 'Yellow'
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target='N/A'; Status='NoPatchConfigured' })
            Write-PatchLog ''
            continue
        }

        $entry  = $versionMap[$major]
        $target = [Version]$entry.Config.TargetVersion

        Write-PatchLog "  Target    : $($entry.Config.TargetVersion) ($($entry.SqlVersion) $($entry.Config.CU) / $($entry.Config.KB))"

        if ($current -gt $target) {
            Write-PatchLog "  Status    : AHEAD - installed ($current) is newer than configured target ($target)." 'Yellow'
            Write-PatchLog "             Update patch-config.psd1 or check builds: https://learn.microsoft.com/en-us/troubleshooting/sql/releases/download-and-install-latest-updates" 'DarkGray'
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='Ahead' })
            Write-PatchLog ''
            continue
        }

        if ($current -eq $target) {
            Write-PatchLog "  Status    : UP TO DATE - no action needed." 'Green'
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='UpToDate' })
            Write-PatchLog ''
            continue
        }

        # Patch needed
        # Two-tone console (verdict word red, target yellow); plain line to the log file
        $stamp = "[$(Get-Date -Format 'HH:mm:ss')]"
        Write-Host "$stamp   Status    : " -ForegroundColor White -NoNewline
        Write-Host 'PATCH NEEDED' -ForegroundColor Red -NoNewline
        Write-Host "  $current  ->  $target" -ForegroundColor Yellow
        Add-Content -Path $logFile -Value "$stamp   Status    : PATCH NEEDED  $current  ->  $target"

        if ($WhatIf) {
            Write-PatchLog "  [WhatIf] Would download and install $($entry.Config.KB) on $srv." 'Cyan'
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='WouldPatch' })
            Write-PatchLog ''
            continue
        }

        # Download
        $installer = Get-PatchFile -Entry $entry -Root $localPatchRoot
        if (-not $installer) {
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='DownloadFailed' })
            Write-PatchLog ''
            continue
        }

        if ($DownloadOnly) {
            Write-PatchLog "  [DownloadOnly] Skipping install on $srv." 'DarkGray'
            $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='Downloaded' })
            Write-PatchLog ''
            continue
        }

        # Confirm
        if (-not $Force) {
            $answer = Read-Host "  Apply $($entry.Config.KB) to $srv\$name now? (yes/no)"
            if ($answer -notmatch '^(yes|y)$') {
                Write-PatchLog "  Skipped by user." 'Yellow'
                $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status='Skipped' })
                Write-PatchLog ''
                continue
            }
        }

        # Install
        $isLocal = $srv -in '.', 'localhost', $env:COMPUTERNAME
        try {
            $exitCode = if ($isLocal) {
                Invoke-LocalPatch -Installer $installer
            }
            else {
                Invoke-RemotePatch -ComputerName $srv -LocalInstaller $installer `
                    -RemotePatchRoot $localPatchRoot -Entry $entry -Cred $Credential
            }
            $status = Write-PatchResult -ExitCode $exitCode -Server $srv
        }
        catch {
            Write-PatchLog "  ERROR during install on $srv - $($_.Exception.Message)" 'Red'
            $status = 'InstallError'
        }

        # Post-patch version check
        if ($status -in 'Patched', 'PatchedRebootNeeded') {
            Write-PatchLog "  Checking version after patch (waiting 10s for registry update)..." 'DarkGray'
            Start-Sleep -Seconds 10
            try {
                $post = @(Get-SqlVersions -ComputerName $srv -Cred $Credential) |
                    Where-Object { $_.Instance -eq $name }
                if ($post) {
                    $newVer  = $post.ProductVersion
                    $changed = $newVer -ne $inst.ProductVersion
                    $color   = if ($changed) { 'Green' } else { 'Yellow' }
                    $note    = if ($changed) { 'updated' } else { 'unchanged - reboot may be required' }
                    Write-PatchLog "  Post-patch: $newVer ($note)" $color
                }
            }
            catch {
                Write-PatchLog "  Could not verify post-patch version: $($_.Exception.Message)" 'Yellow'
            }
        }

        $results.Add([pscustomobject]@{ Server=$srv; Instance=$name; Installed=$inst.ProductVersion; Target=$target; Status=$status })
        Write-PatchLog ''
    }
}

# -- Summary ------------------------------------------------------------------
Write-PatchLog '--- Summary -----------------------------------------' 'Cyan'
$tableStr = $results | Format-Table Server, Instance, Installed, Target, Status -AutoSize | Out-String
Write-Host $tableStr
Add-Content -Path $logFile -Value $tableStr
Write-PatchLog "Log file: $logFile" 'DarkGray'
