# uninstall-ssms.ps1 - Silently uninstall SQL Server Management Studio
# RiskLevel   : MEDIUM - removes SSMS from this machine; does not touch the database engine
#
# SSMS 17-20  : WiX installer - reads UninstallString, appends /uninstall /quiet /norestart
# SSMS 21+    : VS Installer  - uses vswhere to find productId, runs setup.exe uninstall -q
#               winget is tried as a fallback if vswhere fails
#
# Parameters:
#   -WhatIf   : show what would run, no changes
#   -Force    : skip confirmation prompts
#   -Passive  : show VS Installer progress window (default is silent with console timer)
#
# Examples:
#   .\uninstall-ssms.ps1 -WhatIf
#   .\uninstall-ssms.ps1
#   .\uninstall-ssms.ps1 -Force
param(
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$Passive
)

$ErrorActionPreference = 'Stop'

# -- Pending reboot check ------------------------------------------------------
$rebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
)
$rebootPending = ($rebootKeys | Where-Object { Test-Path $_ }) -or
    (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations

if ($rebootPending -and -not $WhatIf) {
    Write-Host 'NOTE: A system reboot is pending on this machine.' -ForegroundColor Yellow
}

# -- Admin check ---------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $WhatIf) {
    Write-Host 'ERROR: This script must be run as Administrator (or use -WhatIf to preview without uninstalling).' -ForegroundColor Red; exit 1
}

# -- Logging -------------------------------------------------------------------
# Falls back to a logs\ folder next to the script when run standalone (not in the repo)
$_repoOutputDir = Join-Path $PSScriptRoot '..\..\..\output-files'
$logDir = [System.IO.Path]::GetFullPath($(if (Test-Path $_repoOutputDir) {
    Join-Path $_repoOutputDir 'patches\ssms'
} else {
    Join-Path $PSScriptRoot 'logs'
}))
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$ts       = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile  = Join-Path $logDir "ssms-uninstall-$ts.log"

function Write-DbaLog {
    param([string]$Msg, [string]$Color = 'White')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $logFile -Value $line
}

Write-DbaLog "SSMS uninstall log - $ts" 'Cyan'

# -- Find all installed SSMS entries ------------------------------------------
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$ssmsEntries = @(
    foreach ($p in $regPaths) {
        Get-ItemProperty $p -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like '*SQL Server Management Studio*' -and
                # Skip MSI sub-component registrations (Language Pack, base MSI entries).
                # UninstallString starting with 'MsiExec.exe /I{' means it's an install-mode
                # registration - the main bootstrapper already removes these sub-components.
                $_.UninstallString -notmatch '^MsiExec\.exe /I\{'
            }
    }
) | Sort-Object { [version]($_.DisplayVersion -replace '[^0-9.]') } -Descending

if ($ssmsEntries.Count -eq 0) {
    Write-DbaLog 'No SSMS installation detected. Nothing to uninstall.' 'Yellow'
    exit 0
}

$script:uninstallCompletedCleanly = $false
$script:anyAttempted = $false
$script:attemptedNames = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $ssmsEntries) {
    $version = $entry.DisplayVersion
    $name    = $entry.DisplayName
    $major   = [int]($version -split '\.')[0]

    Write-DbaLog ''
    Write-DbaLog "Found : $name  v$version" 'White'

    if ($WhatIf) {
        $method = if ($major -ge 21) { 'VS Installer CLI or winget' } else { 'WiX /uninstall /quiet /norestart' }
        Write-DbaLog "  [WhatIf] Would uninstall '$name' via $method." 'Yellow'
        continue
    }

    if (-not $Force) {
        $answer = (Read-Host "  Uninstall '$name' v$version now? (yes/no)").Trim()
        if ($answer -notmatch '^(yes|y)$') {
            Write-DbaLog '  Skipped by user.' 'Yellow'
            continue
        }
    }

    # -- Check if SSMS is running ----------------------------------------------
    $ssmsProc  = Get-Process -Name 'ssms' -ErrorAction SilentlyContinue
    $forceClose = $false
    if ($ssmsProc) {
        $pidList = ($ssmsProc | ForEach-Object { $_.Id }) -join ', '
        Write-DbaLog "  WARNING: SSMS is currently running (PID $pidList)." 'Yellow'
        if ($Force) {
            Write-DbaLog "  -Force specified - will close SSMS automatically." 'Yellow'
            $forceClose = $true
        }
        else {
            $closeAnswer = (Read-Host "  Force close SSMS before uninstalling? (yes/no)").Trim()
            if ($closeAnswer -notmatch '^(yes|y)$') {
                Write-DbaLog "  Skipped - close SSMS manually and re-run." 'Yellow'
                continue
            }
            $forceClose = $true
        }
    }

    # -- SSMS 21+ (Visual Studio Installer) -----------------------------------
    if ($major -ge 21) {
        $script:anyAttempted = $true
        $script:attemptedNames.Add($name)
        Write-DbaLog "  Uninstalling '$name'..." 'Cyan'
        $uninstalled = $false
        $forceFlag   = if ($forceClose) { ' --force' } else { '' }
        $uiFlag      = if ($Passive)    { '--passive' } else { '--quiet' }

        $vswhere     = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
        $vsInstaller = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'

        # Helper: run setup.exe, wait, stream elapsed, check result
        function Invoke-VsUninstall {
            param([string]$Exe, [string]$CmdArgs, [string]$EntryName)
            $fullCmd = "  Running: $Exe $CmdArgs"
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $fullCmd" -ForegroundColor DarkGray
            Add-Content -Path $logFile -Value "[$(Get-Date -Format 'HH:mm:ss')] $fullCmd"
            $proc = Start-Process -FilePath $Exe -ArgumentList $CmdArgs -PassThru `
                -RedirectStandardOutput "$logFile.vs-stdout.txt" `
                -RedirectStandardError  "$logFile.vs-stderr.txt"
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not $proc.HasExited) {
                Write-Host ("`r    ... {0:mm\:ss} elapsed" -f $sw.Elapsed) -NoNewline -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
            }
            Write-Host ''
            if (Test-Path "$logFile.vs-stderr.txt") {
                $vsErr = (Get-Content "$logFile.vs-stderr.txt" -Raw)
                if ($vsErr) { Write-DbaLog "  VS Installer: $($vsErr.Trim())" 'DarkGray' }
            }
            # Check only for this specific entry, not all SSMS installs
            $stillThere = @(foreach ($p in $regPaths) {
                Get-ItemProperty $p -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -eq $EntryName -and $_.UninstallString -notmatch '^MsiExec\.exe /I\{' }
            })
            return ($stillThere.Count -eq 0)
        }

        # 1. vswhere - productId + channelId (avoids --installPath entirely)
        if ((Test-Path $vswhere) -and (Test-Path $vsInstaller)) {
            try {
                $vsJson      = & $vswhere -all -products '*' -format json
                $vsProducts  = $vsJson | ConvertFrom-Json
                # Match by installationPath extracted from registry UninstallString so we
                # pick the right entry when multiple SSMS versions are installed side-by-side.
                $regInstallPath = $null
                $rawCmdForMatch = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
                if ($rawCmdForMatch -match '--installPath\s+"([^"]+)"') { $regInstallPath = $Matches[1] }
                $ssmsProduct = @($vsProducts) |
                    Where-Object {
                        $_.displayName -like '*SQL Server Management Studio*' -and
                        (-not $regInstallPath -or $_.installationPath -eq $regInstallPath)
                    } |
                    Select-Object -First 1

                if ($ssmsProduct) {
                    $channelPart = if ($ssmsProduct.channelId) { " --channelId $($ssmsProduct.channelId)" } else { '' }
                    $vsArgs = "uninstall --productId $($ssmsProduct.productId)$channelPart $uiFlag --norestart$forceFlag"
                    if (Invoke-VsUninstall -Exe $vsInstaller -CmdArgs $vsArgs -EntryName $name) {
                        $script:uninstallCompletedCleanly = $true
                        $uninstalled = $true
                    }
                } else {
                    Write-DbaLog '  vswhere: SSMS not found in VS Installer catalogue - trying registry fallback.' 'DarkGray'
                }
            }
            catch { Write-DbaLog "  vswhere error: $($_.Exception.Message)" 'DarkGray' }
        }

        # 2. Registry passthrough - use the stored VS Installer command but swap --installPath
        #    for --productId when the installer rejects it (seen on SSMS 21 Preview builds)
        if (-not $uninstalled) {
            $rawCmd = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
            if ($rawCmd -match 'setup\.exe') {
                $regExe  = $null; $regArgs = $null
                if ($rawCmd -match '^"([^"]+)"(.*)$')  { $regExe = $Matches[1]; $regArgs = $Matches[2].Trim() }
                elseif ($rawCmd -match '^(\S+)(.*)$')   { $regExe = $Matches[1]; $regArgs = $Matches[2].Trim() }

                if ($regExe -and (Test-Path $regExe)) {
                    # If --installPath is present, try replacing with --productId derived from path
                    if ($regArgs -match '--installPath\s+"[^"]+"') {
                        $derivedId  = 'Microsoft.VisualStudio.Product.Ssms'
                        $regArgs    = $regArgs -replace '--installPath\s+"[^"]+"', "--productId $derivedId"
                        Write-DbaLog '  Registry fallback: replaced --installPath with --productId.' 'DarkGray'
                    }
                    if ($regArgs -notmatch '--quiet|--passive') { $regArgs += " $uiFlag" }
                    if ($regArgs -notmatch '--norestart')       { $regArgs += ' --norestart' }
                    if ($forceClose -and $regArgs -notmatch '--force') { $regArgs += ' --force' }
                    if (Invoke-VsUninstall -Exe $regExe -CmdArgs $regArgs.Trim() -EntryName $name) {
                        $script:uninstallCompletedCleanly = $true
                        $uninstalled = $true
                    }
                }
            }
        }

        # 3. Winget fallback (tries stable ID then preview ID then display name)
        if (-not $uninstalled) {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($winget) {
                $wingetAttempts = @(
                    @('uninstall', '--id', 'Microsoft.SQLServerManagementStudio',         '-e', '--silent', '--accept-source-agreements'),
                    @('uninstall', '--id', 'Microsoft.SQLServerManagementStudio.Preview',  '-e', '--silent', '--accept-source-agreements'),
                    @('uninstall', '--name', "`"$name`"",                                  '-e', '--silent', '--accept-source-agreements')
                )
                foreach ($wingetArgs in $wingetAttempts) {
                    $proc = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -in 0, 3010) {
                        $script:uninstallCompletedCleanly = $true
                        $uninstalled = $true
                        break
                    }
                }
            }
        }

        if ($uninstalled) {
            Write-DbaLog '  Uninstall completed.' 'Green'
        } else {
            Write-DbaLog '  Uninstall failed - remove manually via Settings -> Apps or:' 'Red'
            Write-DbaLog '    winget uninstall --id Microsoft.SQLServerManagementStudio.Preview -e' 'DarkGray'
            Write-DbaLog '    winget uninstall --id Microsoft.SQLServerManagementStudio -e' 'DarkGray'
        }
        continue
    }

    # -- SSMS 20 and below (WiX installer) ------------------------------------
    $rawCmd = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }

    if (-not $rawCmd) {
        Write-DbaLog "  ERROR: No uninstall command in registry for '$name'. Use Settings -> Apps." 'Red'
        continue
    }

    if ($rawCmd -match '^"([^"]+)"(.*)$') {
        $exePath      = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    elseif ($rawCmd -match '^(\S+)(.*)$') {
        $exePath      = $Matches[1]
        $existingArgs = $Matches[2].Trim()
    }
    else {
        Write-DbaLog "  ERROR: Cannot parse uninstall command." 'Red'; continue
    }

    if (-not (Test-Path $exePath)) {
        Write-DbaLog "  ERROR: Uninstall EXE not found: $exePath" 'Red'; continue
    }

    $silentArgs = [System.Collections.Generic.List[string]]::new()
    if ($existingArgs -notmatch '/uninstall') { $silentArgs.Add('/uninstall') }
    if ($existingArgs -notmatch '/quiet')     { $silentArgs.Add('/quiet') }
    if ($existingArgs -notmatch '/norestart') { $silentArgs.Add('/norestart') }
    $finalArgs = ($existingArgs + ' ' + ($silentArgs -join ' ')).Trim()

    $script:anyAttempted = $true
    $script:attemptedNames.Add($name)
    Write-DbaLog "  Uninstalling '$name'..." 'Cyan'
    Write-DbaLog "  Running: $exePath $finalArgs" 'DarkGray'
    $wixOk = $false
    try {
        $proc = Start-Process -FilePath $exePath -ArgumentList $finalArgs -PassThru
        $sw   = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            Write-Host ("`r    ... {0:mm\:ss} elapsed" -f $sw.Elapsed) -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }
        Write-Host ''
        switch ($proc.ExitCode) {
            0    { Write-DbaLog '  Uninstall completed.' 'Green'; $wixOk = $true }
            3010 { Write-DbaLog '  Uninstall completed - reboot required.' 'Yellow'; $wixOk = $true }
            1626 { Write-DbaLog "  Exit 1626 - reboot this machine and retry, or use appwiz.cpl to remove manually." 'Yellow' }
            default { Write-DbaLog "  Uninstall exited with code $($proc.ExitCode) - trying winget fallback..." 'Yellow' }
        }
    }
    catch {
        Write-DbaLog "  ERROR during uninstall: $($_.Exception.Message)" 'Red'
    }

    if (-not $wixOk) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            $wingetAttempts = @(
                @('uninstall', '--id',   'Microsoft.SQLServerManagementStudio',   '-e', '--silent', '--accept-source-agreements'),
                @('uninstall', '--name', "`"$name`"",                              '-e', '--silent', '--accept-source-agreements')
            )
            foreach ($wingetArgs in $wingetAttempts) {
                $wp = Start-Process -FilePath $winget.Source -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                if ($wp.ExitCode -in 0, 3010) {
                    Write-DbaLog '  Uninstall completed via winget.' 'Green'
                    $wixOk = $true
                    break
                }
            }
        }
        if (-not $wixOk) {
            # Last resort: find MSI product code directly from registry and call MsiExec /X
            # bypasses the Burn bootstrapper entirely, useful when Package Cache is corrupt
            $productCode = $null
            foreach ($p in $regPaths) {
                $match = Get-ItemProperty $p -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.DisplayName -eq $name -and
                        $_.PSChildName -match '^\{[0-9A-F-]+\}$'
                    } | Select-Object -First 1
                if ($match) { $productCode = $match.PSChildName; break }
            }
            if ($productCode) {
                Write-DbaLog "  Trying MsiExec direct removal (product code $productCode)..." 'DarkGray'
                $mp = Start-Process -FilePath 'MsiExec.exe' -ArgumentList "/X$productCode /qn /norestart" -Wait -PassThru
                if ($mp.ExitCode -in 0, 3010) {
                    Write-DbaLog '  Uninstall completed via MsiExec.' 'Green'
                    $wixOk = $true
                } else {
                    Write-DbaLog "  MsiExec exited with code $($mp.ExitCode)." 'Yellow'
                }
            }
        }
        if (-not $wixOk) {
            Write-DbaLog '  Uninstall failed - remove manually via Settings -> Apps or:' 'Red'
            Write-DbaLog "    winget uninstall --name `"$name`" -e" 'DarkGray'
        }
    }
}

# -- Confirm removal -----------------------------------------------------------
if (-not $WhatIf -and $script:anyAttempted) {
    Write-DbaLog ''
    Write-DbaLog 'Verifying removal...' 'Cyan'
    $stillInstalled = @(
        foreach ($p in $regPaths) {
            Get-ItemProperty $p -ErrorAction SilentlyContinue |
                Where-Object {
                    $script:attemptedNames -contains $_.DisplayName -and
                    $_.UninstallString -notmatch '^MsiExec\.exe /I\{'
                }
        }
    )
    if ($stillInstalled.Count -eq 0) {
        Write-DbaLog 'SSMS successfully removed.' 'Green'
    }
    else {
        foreach ($e in $stillInstalled) {
            Write-DbaLog "Still detected: $($e.DisplayName) v$($e.DisplayVersion)" 'Yellow'
            if ($script:uninstallCompletedCleanly) {
                Write-DbaLog "  Uninstaller exited cleanly - a reboot is likely required to finish removal." 'Yellow'
            }
            else {
                Write-DbaLog "  The uninstall may have been cancelled." 'Yellow'
                Write-DbaLog "  Re-run this script to try again, or use: Settings -> Apps -> Uninstall" 'DarkGray'
            }
        }
    }
}

Write-DbaLog ''
Write-DbaLog 'Done.' 'Green'
Write-DbaLog "Log: $logFile"
