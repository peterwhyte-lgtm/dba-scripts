<#
.SYNOPSIS
Update SQL Server Management Studio (SSMS) to the latest version.

.DESCRIPTION
Checks the currently installed SSMS version, then updates via winget (preferred)
or downloads and runs the latest installer from Microsoft's direct URL.

The direct download URL (https://aka.ms/ssmsfullsetup) always resolves to the
current latest SSMS release.

.PARAMETER Method
Update method: 'winget' (default) or 'download'.
'winget'   — uses winget upgrade (fast, no download needed if already cached).
'download' — downloads from aka.ms/ssmsfullsetup and runs the installer.

.PARAMETER DownloadDir
Directory to save the SSMS installer when using -Method download.
Default: output-files\patches\

.PARAMETER WhatIf
Show what would run without executing.

.EXAMPLE
# Update via winget (default)
.\sql-operations\patches\Update-Ssms.ps1

# Force download method
.\sql-operations\patches\Update-Ssms.ps1 -Method download
#>
param(
    [ValidateSet('winget', 'download')]
    [string]$Method      = 'winget',

    [string]$DownloadDir,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ── Logging ───────────────────────────────────────────────────────────────────
$repoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$logDir      = Join-Path $repoRoot 'output-files\patches'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts          = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile     = Join-Path $logDir "ssms-update-$ts.log"

function Write-Log {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-Log "SSMS update log — $ts" 'Cyan'

# ── Detect current SSMS version ───────────────────────────────────────────────
$ssmsVersion = $null
$ssmsName    = $null

$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($path in $uninstallPaths) {
    $found = Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' } |
        Select-Object -First 1
    if ($found) {
        $ssmsVersion = $found.DisplayVersion
        $ssmsName    = $found.DisplayName
        break
    }
}

if ($ssmsVersion) {
    Write-Log "Current SSMS : $ssmsName  v$ssmsVersion" 'White'
} else {
    Write-Log 'SSMS not detected — will perform a fresh install.' 'Yellow'
}

# ── winget method ─────────────────────────────────────────────────────────────
if ($Method -eq 'winget') {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log 'winget not available — switching to download method.' 'Yellow'
        $Method = 'download'
    } else {
        Write-Log 'Method: winget' 'Cyan'
        if ($WhatIf) {
            Write-Log 'WhatIf: winget upgrade --id Microsoft.SQLServerManagementStudio --silent' 'Yellow'
            return
        }

        Write-Log 'Running: winget upgrade --id Microsoft.SQLServerManagementStudio ...' 'Cyan'
        $wingetArgs = @(
            'upgrade',
            '--id', 'Microsoft.SQLServerManagementStudio',
            '--silent',
            '--accept-source-agreements',
            '--accept-package-agreements'
        )
        $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs `
                    -Wait -PassThru -NoNewWindow

        if ($proc.ExitCode -eq 0) {
            Write-Log 'winget upgrade completed.' 'Green'
        } elseif ($proc.ExitCode -eq -1978335212) {
            Write-Log 'SSMS is already up to date (no upgrade available).' 'Green'
        } else {
            Write-Log "winget exited with code $($proc.ExitCode) — check output above." 'Yellow'
        }
    }
}

# ── Download method ───────────────────────────────────────────────────────────
if ($Method -eq 'download') {
    Write-Log 'Method: direct download from aka.ms/ssmsfullsetup' 'Cyan'

    if (-not $DownloadDir) { $DownloadDir = $logDir }
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null

    $installerPath = Join-Path $DownloadDir "SSMS-Setup-ENU-$ts.exe"
    $downloadUrl   = 'https://aka.ms/ssmsfullsetup'

    if ($WhatIf) {
        Write-Log "WhatIf: Invoke-WebRequest '$downloadUrl' → '$installerPath'" 'Yellow'
        Write-Log "WhatIf: Start-Process '$installerPath' /install /quiet /norestart" 'Yellow'
        return
    }

    Write-Log "Downloading SSMS installer..." 'Cyan'
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        $sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
        Write-Log "Downloaded: $installerPath ($sizeMB MB)" 'Green'
    } catch {
        Write-Log "ERROR: Download failed — $($_.Exception.Message)" 'Red'
        exit 1
    }

    Write-Log 'Installing SSMS (silent)...' 'Cyan'
    $installArgs = @('/install', '/quiet', '/norestart')
    $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru

    if ($proc.ExitCode -in @(0, 3010)) {
        Write-Log 'SSMS install completed.' 'Green'
        if ($proc.ExitCode -eq 3010) { Write-Log 'Reboot required to complete install.' 'Yellow' }
    } else {
        Write-Log "Install exited with code $($proc.ExitCode)." 'Yellow'
    }
}

# ── Verify new version ────────────────────────────────────────────────────────
Write-Log ''
Write-Log 'Checking installed SSMS version...' 'Cyan'
$newVersion = $null
foreach ($path in $uninstallPaths) {
    $found = Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*SQL Server Management Studio*' } |
        Select-Object -First 1
    if ($found) { $newVersion = $found.DisplayVersion; break }
}

if ($newVersion) {
    if ($ssmsVersion -and $newVersion -ne $ssmsVersion) {
        Write-Log "SSMS updated: v$ssmsVersion  →  v$newVersion" 'Green'
    } elseif ($newVersion) {
        Write-Log "SSMS version: v$newVersion" 'Green'
    }
} else {
    Write-Log 'Could not read new SSMS version from registry — verify manually.' 'Yellow'
}

Write-Log ''
Write-Log 'Done.' 'Green'
Write-Log "Log: $logFile"
