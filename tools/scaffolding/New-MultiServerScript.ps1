<#
.SYNOPSIS
    Generates a ready-to-run PowerShell script that executes a SQL or PowerShell
    script against multiple servers. Output is printed to the console (or written
    to a file). Nothing is executed by this tool — you copy the output and run it.

.DESCRIPTION
    Pass a path to a .sql or .ps1 file and a comma-separated list of server names.
    The generator reads the script, embeds it inline, and wraps it in a foreach loop
    (or a parallel block if -Parallel is specified). The generated script is
    self-contained — it has no dependency on this repo at runtime.

    SQL scripts:  use Invoke-Sqlcmd (requires the SqlServer module on the machine
                  you run the generated script from). Invoke-Sqlcmd connects to each
                  remote server over port 1433 — the script runs locally, not remotely.
                  Results from all servers are shown per-server, then combined in a
                  single table at the end with a Server column added.

    PS scripts:   use Invoke-Command with WinRM remoting. The scriptblock runs ON the
                  remote server. Note: repo .ps1 scripts that reference $PSScriptRoot
                  or repo helpers will not work this way — use this path for standalone
                  scriptblocks (service restarts, OS queries, etc.).
                  Use -Ssh to switch to SSH transport instead of WinRM.
                  The generated PS script includes an optional $credential variable
                  (commented out) — uncomment it for cross-domain or workgroup targets.

.PARAMETER ScriptPath
    Path to the .sql or .ps1 file to run against each server.
    The file extension determines the execution mode.

.PARAMETER Servers
    Comma-separated list of target server names or IP addresses.
    Example: "SVR-DB01,SVR-DB02,SVR-DB03"
    For named SQL instances include the instance name: "SVR01\INST01,SVR02\INST02"

.PARAMETER Database
    (SQL only) Target database to run the query against. Default: master.

.PARAMETER SqlAuth
    (SQL only) Switch. When specified, the generated script prompts for SQL Server
    credentials (username + password) instead of using Windows authentication.
    Use this when the servers are not on the same domain or SQL auth is required.

.PARAMETER Parallel
    Switch. Generates a parallel execution block using ForEach-Object -Parallel
    instead of a sequential foreach loop.
    - Requires PowerShell 7 or later.
    - Faster for large server lists.
    - Output from servers may be interleaved — harder to read than sequential.
    - Sequential (the default) is recommended unless you have 10+ servers.

.PARAMETER ThrottleLimit
    Number of concurrent parallel runspaces when -Parallel is used. Default: 10.
    Has no effect in sequential mode.

.PARAMETER Ssh
    (PS scripts only) Switch. Uses SSH transport for Invoke-Command instead of
    WinRM. Use this when target servers have SSH enabled but not WinRM (e.g.
    Linux hosts or environments where WinRM is blocked).
    Requires SSH key-based authentication to be configured on target servers.

.PARAMETER OutputFile
    Optional path to write the generated script to a .ps1 file instead of
    printing to the console. If omitted, output goes to stdout so you can
    copy it directly from the terminal.

.EXAMPLE
    # Generate a multi-server wait statistics script and view in the console
    .\New-MultiServerScript.ps1 `
        -ScriptPath "..\..\sql\performance\Get-WaitStatistics.sql" `
        -Servers "SVR-DB01,SVR-DB02,SVR-DB03"

.EXAMPLE
    # Same but with SQL auth, specific database, saved to a file
    .\New-MultiServerScript.ps1 `
        -ScriptPath "..\..\sql\performance\Get-WaitStatistics.sql" `
        -Servers "SVR-DB01,SVR-DB02" `
        -Database "YourDatabase" `
        -SqlAuth `
        -OutputFile "C:\Temp\run-wait-stats.ps1"

.EXAMPLE
    # PowerShell script across 5 servers, parallel execution
    .\New-MultiServerScript.ps1 `
        -ScriptPath ".\my-service-restart.ps1" `
        -Servers "SVR01,SVR02,SVR03,SVR04,SVR05" `
        -Parallel

.NOTES
    Author  : Peter Whyte (https://sqldba.blog)
    Repo    : https://github.com/peterwhyte-lgtm/dba-tools
    Safe    : Read-only (this script generates output only — nothing is executed)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage = 'Path to the .sql or .ps1 file to run against each server')]
    [string]$ScriptPath,

    [Parameter(Mandatory, HelpMessage = 'Comma-separated server list, e.g. "SVR01,SVR02,SVR03"')]
    [string]$Servers,

    [Parameter(HelpMessage = 'SQL only — target database (default: master)')]
    [string]$Database = 'master',

    [Parameter(HelpMessage = 'SQL only — prompt for SQL credentials instead of Windows auth')]
    [switch]$SqlAuth,

    [Parameter(HelpMessage = 'Generate parallel execution (PS7+ required). Sequential is default and easier to read')]
    [switch]$Parallel,

    [Parameter(HelpMessage = 'Max concurrent runspaces when -Parallel is used. Default: 10')]
    [int]$ThrottleLimit = 10,

    [Parameter(HelpMessage = 'PS scripts only — use SSH transport instead of WinRM for Invoke-Command')]
    [switch]$Ssh,

    [Parameter(HelpMessage = 'Write the generated script to this .ps1 file instead of printing to console')]
    [string]$OutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------

$resolvedPath = Resolve-Path -Path $ScriptPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Error "Script file not found: $ScriptPath"
    exit 1
}

$scriptFile    = Get-Item $resolvedPath.Path
$scriptContent = Get-Content $scriptFile.FullName -Raw
$extension     = $scriptFile.Extension.ToLower()
$scriptName    = $scriptFile.Name

if ($extension -notin '.sql', '.ps1') {
    Write-Error "ScriptPath must point to a .sql or .ps1 file. Got: $extension"
    exit 1
}

# A line starting with '@ at column 0 terminates a PowerShell single-quoted here-string early.
# SQL files are embedded in @'...'@ so this would break the generated script.
if ($extension -eq '.sql' -and $scriptContent -match "(?m)^'@") {
    Write-Error (
        "The SQL file contains a line beginning with '@ which would prematurely terminate " +
        "the generated here-string and corrupt the output. Remove or rewrite that line first."
    )
    exit 1
}

$isSql      = $extension -eq '.sql'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if (@($serverList).Count -eq 0) {
    Write-Error "No valid server names found in -Servers. Provide a comma-separated list."
    exit 1
}

if ($SqlAuth -and -not $isSql) {
    Write-Warning "-SqlAuth is only applicable to .sql scripts and will be ignored for .ps1 files."
    $SqlAuth = $false
}

if ($Ssh -and $isSql) {
    Write-Warning "-Ssh is only applicable to .ps1 scripts and will be ignored for SQL files."
    $Ssh = $false
}

# ---------------------------------------------------------------------------
# SqlServer module check (SQL mode only)
# ---------------------------------------------------------------------------

if ($isSql) {
    if (-not (Get-Module -Name SqlServer -ListAvailable)) {
        Write-Host ''
        Write-Host '  The SqlServer PowerShell module is required to run SQL scripts against remote servers.' -ForegroundColor Yellow
        Write-Host '  It is not installed on this machine.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Install it with:' -ForegroundColor Cyan
        Write-Host '    Install-Module -Name SqlServer -Scope CurrentUser -Force' -ForegroundColor White
        Write-Host ''
        Write-Host '  After installing, re-run this generator.' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
}

# ---------------------------------------------------------------------------
# PS script repo-dependency warning
# ---------------------------------------------------------------------------

if (-not $isSql -and ($scriptContent -match '\$PSScriptRoot' -or $scriptContent -match 'Invoke-RepoSql')) {
    Write-Warning (
        "The script '$scriptName' references `$PSScriptRoot or repo helpers. " +
        "These paths will not resolve on remote servers - Invoke-Command runs the scriptblock on the target machine where this repo does not exist. " +
        "This generator works best for self-contained PS scripts (service restarts, OS queries). " +
        "For repo-backed database queries, pass the matching .sql file instead - it runs via Invoke-Sqlcmd locally against the remote server on port 1433, no remoting needed. " +
        "Generation will continue, but the generated script may fail at runtime."
    )
}

# ---------------------------------------------------------------------------
# Helpers — build reusable string fragments
# ---------------------------------------------------------------------------

$serverArrayInner = ($serverList | ForEach-Object { "    '$_'" }) -join ",`n"

$nl = [Environment]::NewLine

$execMode = if ($Parallel) {
    "Parallel (ForEach-Object -Parallel, ThrottleLimit $ThrottleLimit) — requires PowerShell 7+"
} else {
    'Sequential (foreach)'
}

# ---------------------------------------------------------------------------
# Build the generated script — SQL path
# ---------------------------------------------------------------------------

function Build-SqlScript {

    $authLabel = if ($SqlAuth) { 'SQL authentication (prompted at runtime)' } else { 'Windows authentication (trusted connection)' }
    $header = "#Requires -Modules SqlServer$nl<#$nl" +
              "    Generated by  : New-MultiServerScript.ps1$nl" +
              "    Source script : $scriptName$nl" +
              "    Servers       : $($serverList -join ', ')$nl" +
              "    Database      : $Database$nl" +
              "    Auth          : $authLabel$nl" +
              "    Execution     : $execMode$nl" +
              "    Generated     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')$nl$nl" +
              "    Review the embedded SQL below before running.$nl" +
              "    To run: open a PowerShell session and execute this script, or paste it directly.$nl" +
              "#>"

    $serverBlock = '$servers = @(' + $nl + $serverArrayInner + $nl + ')'

    # SQL here-string — single-quoted so $variables inside the SQL stay literal
    $sqlBlock = '$sql = @' + "'" + $nl + $scriptContent.TrimEnd() + $nl + "'@"

    # Credential block (SQL auth only)
    $credBlock = $null
    if ($SqlAuth) {
        $credBlock = '# SQL authentication — enter credentials when prompted' + $nl +
                     '$credential = Get-Credential -Message ' + "'SQL Server credentials for target servers'" + $nl +
                     '$sqlUser    = $credential.UserName' + $nl +
                     '$sqlPass    = $credential.GetNetworkCredential().Password'
    }

    # Results collection — receives rows from all servers with a Server column prepended
    $resultsInit = '$allResults = [System.Collections.Generic.List[object]]::new()'

    # Invoke-Sqlcmd argument string — $server and $sql are local vars in the generated script
    $invokeArgs = if ($SqlAuth) {
        "-ServerInstance `$server -Database '$Database' -Query `$sql -Username `$sqlUser -Password `$sqlPass -TrustServerCertificate -OutputAs DataTables"
    } else {
        "-ServerInstance `$server -Database '$Database' -Query `$sql -TrustServerCertificate -OutputAs DataTables"
    }

    # Sequential try body — collects rows into $allResults with Server column
    $tryBodySeq = '        $rows = Invoke-Sqlcmd ' + $invokeArgs + $nl +
                  '        if ($rows) {' + $nl +
                  '            $rows | Format-Table -AutoSize' + $nl +
                  "            foreach (`$r in `$rows) { `$allResults.Add((`$r | Select-Object @{n='Server';e={`$server}}, *)) }" + $nl +
                  '        } else {' + $nl +
                  "            Write-Host '  (no rows returned)' -ForegroundColor DarkGray" + $nl +
                  '        }'

    # Parallel try body — outputs rows into the pipeline (piped into $allResults after the block)
    $tryBodyPar = '        $rows = Invoke-Sqlcmd ' + $invokeArgs + $nl +
                  '        if ($rows) {' + $nl +
                  '            $rows | Format-Table -AutoSize' + $nl +
                  "            `$rows | ForEach-Object { `$_ | Select-Object @{n='Server';e={`$server}}, * }" + $nl +
                  '        } else {' + $nl +
                  "            Write-Host '  (no rows returned)' -ForegroundColor DarkGray" + $nl +
                  '        }'

    if ($Parallel) {
        # $using: captures bring outer-scope variables into each parallel runspace
        $usingCaptures = '    $server = $_' + $nl +
                         '    $sql    = $using:sql'
        if ($SqlAuth) {
            $usingCaptures += $nl + '    $sqlUser = $using:sqlUser' + $nl + '    $sqlPass = $using:sqlPass'
        }
        $loop = '$servers | ForEach-Object -Parallel {' + $nl +
                $usingCaptures + $nl +
                '    Write-Host "`n=== $server ===" -ForegroundColor Cyan' + $nl +
                '    try {' + $nl +
                $tryBodyPar + $nl +
                '    } catch {' + $nl +
                '        Write-Warning "$server : $_"' + $nl +
                '    }' + $nl +
                '} -ThrottleLimit ' + $ThrottleLimit + ' | ForEach-Object { $allResults.Add($_) }'
    } else {
        $loop = 'foreach ($server in $servers) {' + $nl +
                '    Write-Host "`n=== $server ===" -ForegroundColor Cyan' + $nl +
                '    try {' + $nl +
                $tryBodySeq + $nl +
                '    } catch {' + $nl +
                '        Write-Warning "$server : $_"' + $nl +
                '    }' + $nl +
                '}'
    }

    # Combined summary table — shown after all servers complete when there are multiple
    $summary = 'if ($allResults.Count -gt 0 -and $servers.Count -gt 1) {' + $nl +
               '    Write-Host "`n── Combined ($($allResults.Count) rows across $($servers.Count) servers) ──────" -ForegroundColor DarkGray' + $nl +
               '    $allResults | Format-Table -AutoSize' + $nl +
               '}'

    $parts = @($header, $serverBlock, $sqlBlock)
    if ($credBlock) { $parts += $credBlock }
    $parts += $resultsInit, $loop, $summary, 'Write-Host "`nDone." -ForegroundColor Green'
    return $parts -join ($nl + $nl)
}

# ---------------------------------------------------------------------------
# Build the generated script — PowerShell remoting path
# ---------------------------------------------------------------------------

function Build-PsScript {

    $transport  = if ($Ssh) { 'SSH (requires SSH key auth on target servers)' } else { 'WinRM (requires PowerShell remoting enabled on target servers)' }
    $prereqNote = if ($Ssh) {
        'SSH key-based auth must be configured on target servers.'
    } else {
        "PowerShell remoting must be enabled on each target server.$nl" +
        "                    Enable with (run as admin on the target): Enable-PSRemoting -Force"
    }

    $header = "<#$nl" +
              "    Generated by  : New-MultiServerScript.ps1$nl" +
              "    Source script : $scriptName$nl" +
              "    Servers       : $($serverList -join ', ')$nl" +
              "    Transport     : $transport$nl" +
              "    Execution     : $execMode$nl" +
              "    Generated     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')$nl$nl" +
              "    Review the embedded scriptblock below before running.$nl" +
              "    Prerequisite  : $prereqNote$nl" +
              "#>"

    $serverBlock = '$servers = @(' + $nl + $serverArrayInner + $nl + ')'

    $scriptBlockDecl = '$scriptBlock = {' + $nl + $scriptContent.TrimEnd() + $nl + '}'

    # Optional credential block (WinRM only — SSH uses key auth, no password needed)
    $credTemplate = $null
    if (-not $Ssh) {
        $credTemplate = '# Optional — uncomment and set credentials for cross-domain or workgroup targets' + $nl +
                        '# $credential = Get-Credential -Message "Remote server credentials"' + $nl +
                        '$credential = $null'
    }

    # Invoke-Command invocation for both sequential and parallel paths
    $invokeBody = if ($Ssh) {
        '        Invoke-Command -HostName $server -ScriptBlock $scriptBlock'
    } else {
        '        $ic = @{ ComputerName = $server; ScriptBlock = $scriptBlock }' + $nl +
        '        if ($credential) { $ic.Credential = $credential }' + $nl +
        '        Invoke-Command @ic'
    }

    if ($Parallel) {
        # $using: captures bring outer-scope variables into each parallel runspace
        $usingCaptures = '    $server      = $_' + $nl +
                         '    $scriptBlock = $using:scriptBlock'
        if (-not $Ssh) {
            $usingCaptures += $nl + '    $credential  = $using:credential'
        }
        $loop = '$servers | ForEach-Object -Parallel {' + $nl +
                $usingCaptures + $nl +
                '    Write-Host "`n=== $server ===" -ForegroundColor Cyan' + $nl +
                '    try {' + $nl +
                $invokeBody + $nl +
                '    } catch {' + $nl +
                '        Write-Warning "$server : $_"' + $nl +
                '    }' + $nl +
                '} -ThrottleLimit ' + $ThrottleLimit
    } else {
        $loop = 'foreach ($server in $servers) {' + $nl +
                '    Write-Host "`n=== $server ===" -ForegroundColor Cyan' + $nl +
                '    try {' + $nl +
                $invokeBody + $nl +
                '    } catch {' + $nl +
                '        Write-Warning "$server : $_"' + $nl +
                '    }' + $nl +
                '}'
    }

    $parts = @($header, $serverBlock, $scriptBlockDecl)
    if ($credTemplate) { $parts += $credTemplate }
    $parts += $loop, 'Write-Host "`nDone." -ForegroundColor Green'
    return $parts -join ($nl + $nl)
}

# ---------------------------------------------------------------------------
# Generate and output
# ---------------------------------------------------------------------------

$generated = if ($isSql) { Build-SqlScript } else { Build-PsScript }

if ($OutputFile) {
    $generated | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "Generated script written to: $OutputFile" -ForegroundColor Green
    Write-Host "Review it, then run: powershell -File `"$OutputFile`"" -ForegroundColor Cyan
} else {
    Write-Output $generated
}
