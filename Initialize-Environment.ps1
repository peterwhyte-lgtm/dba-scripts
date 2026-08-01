<#
Script Name : Initialize-Environment
Purpose     : First-time setup check for this repo on a new machine. Validates
              prerequisites, installs missing modules, creates the output directory
              structure, and optionally tests SQL Server connectivity.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only. No changes made without explicit prompting, or -AutoInstall.
Impact      : Low

Usage:
    .\Initialize-Environment.ps1
    .\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019
    .\Initialize-Environment.ps1 -ServerInstance . -AutoInstall -PersistProfile
#>
[CmdletBinding()]
param (
    # SQL Server instance to test connectivity against. Defaults to local (.) — pass a named
    # instance or remote server to override, e.g. -ServerInstance PROD01\SQL2019
    [string]$ServerInstance = '.',

    # Install missing PowerShell modules (SqlServer, Pester) without prompting.
    [switch]$AutoInstall,

    # Append DBASCRIPTS_SERVER to your PowerShell profile so it survives session restarts.
    [switch]$PersistProfile
)

$ErrorActionPreference = 'Continue'
$repoRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

$script:results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Label, [string]$Status, [string]$Detail = '')
    $script:results.Add([PSCustomObject]@{ Label = $Label; Status = $Status; Detail = $Detail })
    $color = switch ($Status) {
        'OK'    { 'Green'  }
        'WARN'  { 'Yellow' }
        'FAIL'  { 'Red'    }
        'SKIP'  { 'DarkGray' }
        default { 'Gray'   }
    }
    $line = "  [{0,-4}] {1}" -f $Status, $Label
    if ($Detail) { $line += " — $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Prompt-Install {
    param([string]$ModuleName)
    if ($AutoInstall) { return $true }
    if (-not [Environment]::UserInteractive -or $env:CI) { return $false }
    $r = Read-Host "         Install $ModuleName now? [Y/n]"
    return $r -in '', 'y', 'Y'
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  DBA Scripts — Environment Setup' -ForegroundColor Cyan
Write-Host ('  ' + ('─' * 56)) -ForegroundColor DarkCyan
Write-Host ''

# ---------------------------------------------------------------------------
# 1. PowerShell version
# ---------------------------------------------------------------------------

Write-Host '  PowerShell' -ForegroundColor DarkGray
$psv = $PSVersionTable.PSVersion
if ($psv.Major -ge 7) {
    Add-Check 'PowerShell version' 'OK' "$($psv.ToString()) — all features available"
} elseif ($psv.Major -ge 5 -and $psv.Minor -ge 1) {
    Add-Check 'PowerShell version' 'WARN' "$($psv.ToString()) — parallel execution not available; upgrade to PS7 for full feature set"
} else {
    Add-Check 'PowerShell version' 'FAIL' "$($psv.ToString()) — minimum is PS 5.1; repo may not work correctly"
}

# ---------------------------------------------------------------------------
# 2. Execution policy
# ---------------------------------------------------------------------------

$policy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
if (-not $policy -or $policy -eq 'Undefined') {
    $policy = Get-ExecutionPolicy
}
switch ($policy) {
    'Bypass'       { Add-Check 'Execution policy' 'OK'   "Bypass — scripts run without restriction" }
    'Unrestricted' { Add-Check 'Execution policy' 'OK'   "Unrestricted" }
    'RemoteSigned' { Add-Check 'Execution policy' 'OK'   "RemoteSigned" }
    'AllSigned'    { Add-Check 'Execution policy' 'WARN' "AllSigned — scripts must be signed; run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" }
    'Restricted'   { Add-Check 'Execution policy' 'FAIL' "Restricted — scripts cannot run; fix with: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" }
    default        { Add-Check 'Execution policy' 'WARN' $policy }
}

# ---------------------------------------------------------------------------
# 3. Repo path
# ---------------------------------------------------------------------------

if ($repoRoot -match ' ') {
    Add-Check 'Repo path' 'WARN' "Path contains spaces ($repoRoot) — some scripts may fail; clone to a path without spaces"
} elseif ($repoRoot -match '^\\\\') {
    Add-Check 'Repo path' 'WARN' "Repo is on a UNC share — local path strongly preferred for reliable execution"
} else {
    Add-Check 'Repo path' 'OK' $repoRoot
}

# ---------------------------------------------------------------------------
# 4. SqlServer module / sqlcmd.exe
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  SQL execution' -ForegroundColor DarkGray

$hasSqlModule = $null -ne (Get-Module -Name SqlServer -ListAvailable -ErrorAction SilentlyContinue)
$hasSqlcmdExe = $null -ne (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue)

if ($hasSqlModule) {
    $modVer = (Get-Module -Name SqlServer -ListAvailable -ErrorAction SilentlyContinue |
               Sort-Object Version -Descending | Select-Object -First 1).Version
    Add-Check 'SqlServer module' 'OK' "v$modVer (Invoke-Sqlcmd available)"
} elseif ($hasSqlcmdExe) {
    Add-Check 'SqlServer module' 'SKIP' 'Not installed — sqlcmd.exe found as fallback (install module for full functionality)'
    if (Prompt-Install 'SqlServer module') {
        Write-Host '         Installing...' -ForegroundColor DarkGray
        Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
        $hasSqlModule = $null -ne (Get-Module -Name SqlServer -ListAvailable -ErrorAction SilentlyContinue)
        if ($hasSqlModule) { Add-Check 'SqlServer module (installed)' 'OK' 'Installation successful' }
        else                { Add-Check 'SqlServer module (install)' 'FAIL' 'Installation failed — install manually: Install-Module SqlServer -Scope CurrentUser -Force' }
    }
} else {
    Add-Check 'SqlServer module' 'FAIL' 'Neither Invoke-Sqlcmd nor sqlcmd.exe found'
    if (Prompt-Install 'SqlServer module') {
        Write-Host '         Installing...' -ForegroundColor DarkGray
        Install-Module SqlServer -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
        $hasSqlModule = $null -ne (Get-Module -Name SqlServer -ListAvailable -ErrorAction SilentlyContinue)
        if ($hasSqlModule) { Add-Check 'SqlServer module (installed)' 'OK' 'Installation successful' }
        else                { Add-Check 'SqlServer module (install)' 'FAIL' 'Install manually: Install-Module SqlServer -Scope CurrentUser -Force' }
    } else {
        Write-Host '         Run when ready: Install-Module SqlServer -Scope CurrentUser -Force' -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 5. Pester (for tests/)
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  Testing' -ForegroundColor DarkGray

$hasPester = $null -ne (Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue)
if ($hasPester) {
    $pesterVer = (Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue |
                  Sort-Object Version -Descending | Select-Object -First 1).Version
    Add-Check 'Pester module' 'OK' "v$pesterVer (run tests with: Invoke-Pester tests/)"
} else {
    Add-Check 'Pester module' 'SKIP' 'Not installed — optional (needed to run tests/). Install: Install-Module Pester -Force -SkipPublisherCheck'
    if (Prompt-Install 'Pester') {
        Write-Host '         Installing...' -ForegroundColor DarkGray
        Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction SilentlyContinue
        $hasPester = $null -ne (Get-Module -Name Pester -ListAvailable -ErrorAction SilentlyContinue)
        if ($hasPester) { Add-Check 'Pester module (installed)' 'OK' 'Installation successful' }
    }
}

# ---------------------------------------------------------------------------
# 6. Output directories
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  Output directories' -ForegroundColor DarkGray

# Verify key repo folders are present
Write-Host ''
Write-Host '  Repo structure' -ForegroundColor DarkGray
foreach ($folder in @('sql', 'powershell', 'powershell\wrappers', 'sql\collectors', 'tools')) {
    $full = Join-Path $repoRoot $folder
    if (Test-Path $full) {
        Add-Check "$folder/" 'OK' ''
    } else {
        Add-Check "$folder/" 'FAIL' "Expected folder not found — repo may be incomplete or cloned incorrectly"
    }
}

$outputDirs = @(
    'output-files'
    'output-files\collectors\wait-stats'
    'output-files\collectors\blocking'
    'output-files\collectors\deadlocks'
    'output-files\collectors\tempdb'
    'output-files\collectors\perfmon'
    'output-files\collectors\ag-health'
    'output-files\collectors\storage-io'
    'output-files\collectors\database-growth'
    'output-files\collectors\vlf-count'
    'output-files\collectors\errorlog'
    'output-files\collectors\query-store'
    'output-files\collectors\index-fragmentation'
    'output-files\healthcheck'
    'output-files\reviews'
    'output-files\migration'
    'output-files\assessment'
    'output-files\dry-runs'
)

$created = 0
foreach ($rel in $outputDirs) {
    $full = Join-Path $repoRoot $rel
    if (-not (Test-Path $full)) {
        New-Item -ItemType Directory -Path $full -Force | Out-Null
        $created++
    }
}

if ($created -gt 0) {
    Add-Check 'Output directories' 'OK' "Created $created missing director$(if ($created -eq 1) {'y'} else {'ies'})"
} else {
    Add-Check 'Output directories' 'OK' 'All present'
}

# Check .gitignore covers output-files
$gitignore = Join-Path $repoRoot '.gitignore'
if ((Test-Path $gitignore) -and (Get-Content $gitignore -Raw) -match 'output-files') {
    Add-Check '.gitignore' 'OK' 'output-files/ excluded from commits'
} else {
    Add-Check '.gitignore' 'WARN' 'output-files/ may not be excluded — check .gitignore to avoid committing CSV output'
}

# ---------------------------------------------------------------------------
# 7. SQL Server connectivity
# ---------------------------------------------------------------------------

if ($ServerInstance) {
    Write-Host ''
    $connHeader = if ($ServerInstance -in '.','localhost','(local)') { 'Connectivity — local SQL Server' } else { "Connectivity — $ServerInstance" }
    Write-Host "  $connHeader" -ForegroundColor DarkGray

    $connScript = Join-Path $repoRoot 'tools\local-sql\Test-SqlConnectivity.ps1'
    if (Test-Path $connScript) {
        try {
            # *>&1 captures Write-Host (Information stream 6) alongside stdout/stderr in PS7.
            # Tee to terminal so connectivity detail is visible, then collect as strings for parsing.
            $connOutput = & $connScript -ServerInstance $ServerInstance *>&1 | ForEach-Object { Write-Host $_; "$_" }
            $versionLine = $connOutput | Where-Object { $_ -match 'Version\s+:' } | Select-Object -First 1
            $statusLine  = $connOutput | Where-Object { $_ -match 'Status\s+:' }  | Select-Object -First 1

            if ($statusLine -match 'OK') {
                $detail = if ($versionLine) { ($versionLine -replace '.*Version\s+:\s*', '').Trim() } else { $ServerInstance }
                Add-Check "Connectivity to $ServerInstance" 'OK' $detail

                # SQL Server version floor check — extract major version
                if ($versionLine -match '(\d+)\.') {
                    $major = [int]$Matches[1]
                    if ($major -lt 13) {  # 13 = SQL Server 2016
                        Add-Check 'SQL Server version' 'WARN' "Version $major.x detected — minimum is SQL Server 2016 (13.x); some scripts require 2019+"
                    } else {
                        Add-Check 'SQL Server version' 'OK' "SQL Server $major.x — meets minimum requirement (2016+)"
                    }
                }

                # Set session default — only if none is already active, or the user
                # explicitly named a non-default server (avoids clobbering PROD01 with '.')
                if (-not $env:DBASCRIPTS_SERVER -or $ServerInstance -ne '.') {
                    $env:DBASCRIPTS_SERVER = $ServerInstance
                }
                Write-Host ''
                Write-Host "  Session default set: $ServerInstance" -ForegroundColor DarkGray
            } else {
                Add-Check "Connectivity to $ServerInstance" 'FAIL' 'Connection failed — see output above'
            }
        } catch {
            Add-Check "Connectivity to $ServerInstance" 'FAIL' $_.Exception.Message
        }
    } else {
        Add-Check 'Connectivity check' 'SKIP' "Test-SqlConnectivity.ps1 not found at $connScript"
    }

    # Profile persistence
    if ($PersistProfile -and $env:DBASCRIPTS_SERVER) {
        $profilePath = $PROFILE.CurrentUserCurrentHost
        $profileDir  = Split-Path $profilePath
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }

        $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
        $line = "`$env:DBASCRIPTS_SERVER = '$ServerInstance'"

        if ($profileContent -notmatch [regex]::Escape('DBASCRIPTS_SERVER')) {
            Add-Content -Path $profilePath -Value "`n# dba-tools default server`n$line"
            Add-Check 'Profile persistence' 'OK' "Added to $profilePath — survives session restarts"
        } else {
            Add-Check 'Profile persistence' 'SKIP' 'DBASCRIPTS_SERVER already in profile — update manually if needed'
        }
    } elseif ($ServerInstance -and -not $PersistProfile) {
        Write-Host ''
        Write-Host '  To persist this server across sessions, re-run with -PersistProfile' -ForegroundColor DarkGray
        Write-Host "  Or add to your profile manually:  `$env:DBASCRIPTS_SERVER = '$ServerInstance'" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# 8. Summary and next steps
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host ('  ' + ('─' * 56)) -ForegroundColor DarkCyan

$fails  = @($script:results | Where-Object { $_.Status -eq 'FAIL'  })
$warns  = @($script:results | Where-Object { $_.Status -eq 'WARN'  })
$oks    = @($script:results | Where-Object { $_.Status -eq 'OK'    })

if ($fails.Count -eq 0 -and $warns.Count -eq 0) {
    Write-Host "  Setup complete — $($oks.Count) checks passed" -ForegroundColor Green
} elseif ($fails.Count -eq 0) {
    Write-Host "  Setup ready with $($warns.Count) warning$(if ($warns.Count -ne 1) {'s'}) — review above" -ForegroundColor Yellow
} else {
    Write-Host "  $($fails.Count) check$(if ($fails.Count -ne 1) {'s'}) failed — see above before continuing" -ForegroundColor Red
}

Write-Host ''
Write-Host '  Next steps' -ForegroundColor DarkGray
if ($ServerInstance -and ($fails | Where-Object { $_.Label -match 'Connectivity' }).Count -eq 0) {
    # Connectivity passed — env var is set, so run.ps1 needs no -ServerInstance
    $serverDisplay = if ($ServerInstance -in '.','localhost','(local)') { "local SQL Server ($ServerInstance)" } else { $ServerInstance }
    Write-Host ''
    Write-Host "  Server default active: $serverDisplay — run.ps1 will use it automatically" -ForegroundColor Green
    Write-Host ''
    Write-Host '  Run a script                   ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\run.ps1 Get-WaitStatistics' -ForegroundColor White
    Write-Host '  Browse all scripts             ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\run.ps1 -List' -ForegroundColor White
    Write-Host '  Full health check              ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\powershell\reporting\Invoke-HealthCheckCollection.ps1' -ForegroundColor White
    Write-Host '  Browser UI                     ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\web-ui\Start-WebUi.ps1' -ForegroundColor White
} else {
    # Connectivity failed or not yet tested
    Write-Host ''
    if ($ServerInstance -in '.', 'localhost', '(local)') {
        Write-Host '  No local SQL Server found — target a specific instance:' -ForegroundColor DarkGray
    } else {
        Write-Host "  Could not reach $ServerInstance — check instance name and network:" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Set server for this session    ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance YOURSERVER' -ForegroundColor White
    Write-Host '  Re-run with connectivity check ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\Initialize-Environment.ps1 -ServerInstance YOURSERVER' -ForegroundColor White
    Write-Host '  Browse all scripts             ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\run.ps1 -List' -ForegroundColor White
    Write-Host '  Run a script (once server set) ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\run.ps1 Get-WaitStatistics' -ForegroundColor White
    Write-Host '  Browser UI                     ' -NoNewline -ForegroundColor DarkGray; Write-Host '.\web-ui\Start-WebUi.ps1' -ForegroundColor White
}
Write-Host ''
Write-Host '  Full guide: SETUP.md   •   Script list: docs\script-catalog.md   •   Quick start: docs\quick-start.md' -ForegroundColor DarkGray
Write-Host ''
