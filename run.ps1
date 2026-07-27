<#
.SYNOPSIS
Root launcher for DBA helper scripts. Fuzzy name match across sql/ and powershell/.

.DESCRIPTION
Finds and runs any script in the repo by name (partial match accepted).
Use -List to browse all available scripts grouped by category.

.EXAMPLES
  .\run.ps1 Get-WaitStatistics
  .\run.ps1 Get-WaitStatistics -ServerInstance MYSERVER\INST01 -OutputFormat Csv
  .\run.ps1 -List
#>

param(
    [string]$ScriptName,

    [switch]$List,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# Repo scripts use PowerShell 7 syntax (?., ternary). If launched from Windows PowerShell 5.1,
# hand off to pwsh so the same command works from any prompt.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host 'This toolkit requires PowerShell 7 (pwsh). Install it: winget install Microsoft.PowerShell' -ForegroundColor Yellow
        return
    }
    $forward = @($ScriptName | Where-Object { $_ })
    if ($List) { $forward += '-List' }
    $forward += @($Arguments | Where-Object { $null -ne $_ })
    & $pwsh.Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forward
    return
}

$repoRoot = Resolve-Path $PSScriptRoot

& (Join-Path $repoRoot 'tools\local-sql\Install-Prerequisites.ps1')

if ($List -or -not $ScriptName) {
    Write-Host ''
    Write-Host 'dba-tools — available scripts' -ForegroundColor Cyan
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''

    # ── Top scripts for production DBA ────────────────────────────────────────
    Write-Host '  Start here' -ForegroundColor Green
    Write-Host ''
    $topScripts = @(
        [PSCustomObject]@{ Name = 'Get-WaitStatistics';             Desc = 'Ranked wait types — first stop for any unexplained slowness' }
        [PSCustomObject]@{ Name = 'Get-BlockingChains';             Desc = 'Who is blocking whom — head-blocker tree with queries' }
        [PSCustomObject]@{ Name = 'Get-ActiveRequests';             Desc = 'Queries running right now — incident first look' }
        [PSCustomObject]@{ Name = 'Get-TopCpuQueries';              Desc = 'Highest CPU queries from plan cache' }
        [PSCustomObject]@{ Name = 'Get-MissingIndexes';             Desc = 'High-impact missing index recommendations' }
        [PSCustomObject]@{ Name = 'Get-DatabaseSizesAndFreeSpace';  Desc = 'All databases — data and log sizes with free space' }
        [PSCustomObject]@{ Name = 'Get-BackupCoverage';             Desc = 'Backup currency across all databases' }
        [PSCustomObject]@{ Name = 'Get-SqlAgentJobFailureSummary';  Desc = 'Recent job failures and duration outliers' }
        [PSCustomObject]@{ Name = 'Get-IndexFragmentation';         Desc = 'Fragmentation and page counts for all indexes' }
        [PSCustomObject]@{ Name = 'Get-InstanceConfigurationScore'; Desc = 'Best-practice configuration score for this instance' }
    )
    foreach ($s in $topScripts) {
        Write-Host ("  {0,-42}" -f $s.Name) -NoNewline -ForegroundColor White
        Write-Host $s.Desc -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''

    # ── Full script listing by category ───────────────────────────────────────
    $sqlRoot = Join-Path $repoRoot 'sql'
    foreach ($catDir in (Get-ChildItem $sqlRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $allScripts = @(Get-ChildItem $catDir.FullName -Recurse -Filter '*.sql' -ErrorAction SilentlyContinue)
        if ($allScripts.Count -eq 0) { continue }

        Write-Host "  sql/$($catDir.Name)/  ($($allScripts.Count))" -ForegroundColor Yellow

        $rootScripts = @(Get-ChildItem $catDir.FullName -Filter '*.sql' -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($s in $rootScripts) { Write-Host "    $($s.BaseName)" -ForegroundColor DarkGray }

        foreach ($subDir in (Get-ChildItem $catDir.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $subScripts = @(Get-ChildItem $subDir.FullName -Filter '*.sql' -ErrorAction SilentlyContinue | Sort-Object Name)
            if ($subScripts.Count -eq 0) { continue }
            Write-Host "    [$($subDir.Name)]" -ForegroundColor DarkCyan
            foreach ($s in $subScripts) { Write-Host "      $($s.BaseName)" -ForegroundColor DarkGray }
        }
        Write-Host ''
    }

    $psRoot = Join-Path $repoRoot 'powershell'
    foreach ($folder in (Get-ChildItem $psRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $scripts = Get-ChildItem $folder.FullName -Filter '*.ps1' -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(Get|Invoke|Review|Generate|Backup|Restore)-' } |
                   Sort-Object Name
        if ($scripts.Count -gt 0) {
            Write-Host "  powershell/$($folder.Name)/" -ForegroundColor Yellow
            $scripts | ForEach-Object { Write-Host "    $($_.BaseName)" -ForegroundColor DarkGray }
            Write-Host ''
        }
    }

    Write-Host ('─' * 60) -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host 'Run a script:' -ForegroundColor Cyan
    Write-Host '  .\run.ps1 Get-WaitStatistics'
    Write-Host '  Results always saved to output-files/ as CSV.' -ForegroundColor DarkGray
    Write-Host '  Add -OutputFormat Csv to suppress terminal output (CSV only).' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Set your server once per session (then no -ServerInstance needed):' -ForegroundColor Cyan
    Write-Host '  .\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance YOURSERVER'
    Write-Host ''
    Write-Host 'Or pass it per-run:' -ForegroundColor Cyan
    Write-Host '  .\run.ps1 Get-WaitStatistics -ServerInstance YOURSERVER'
    Write-Host ''
    Write-Host 'Browser UI (scripts + CSV viewer):' -ForegroundColor Cyan
    Write-Host '  .\web-ui\Start-WebUi.ps1'
    Write-Host ''
    return
}

# Resolve the script name directly — avoids a second hop through Run-Helper
# which mangles named parameters during array splatting.
$searchRoots = @(
    (Join-Path $repoRoot 'powershell'),
    (Join-Path $repoRoot 'tools'),
    (Join-Path $repoRoot 'sql')
)

$candidates = @()
foreach ($root in $searchRoots) {
    $candidates += Get-ChildItem -Path $root -Recurse -File -Include '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like $ScriptName -or $_.BaseName -like "*$ScriptName*" }
}
# Only fall back to .sql if no .ps1 wrapper found
if ($candidates.Count -eq 0) {
    foreach ($root in $searchRoots) {
        $candidates += Get-ChildItem -Path $root -Recurse -File -Include '*.sql' -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -like $ScriptName -or $_.BaseName -like "*$ScriptName*" }
    }
}

$unique = $candidates | Sort-Object FullName -Unique

# Prefer exact match over fuzzy — prevents e.g. Get-IndexFragmentation being blocked by
# Get-IndexFragmentationAcrossDatabases when the user typed the full name.
$exact = $unique | Where-Object { $_.BaseName -eq $ScriptName }
if ($exact.Count -eq 1) { $unique = $exact }
if ($unique.Count -eq 0) {
    Write-Host "No script matched '$ScriptName'." -ForegroundColor Yellow
    Write-Host "  Try: .\tools\triage\Find-UsefulScript.ps1 -Keyword $ScriptName" -ForegroundColor DarkGray
    Write-Host ''
    return
}
if ($unique.Count -gt 1) {
    Write-Host "Multiple matches for '$ScriptName' — be more specific:" -ForegroundColor Yellow
    $unique | ForEach-Object { Write-Host "  $([System.IO.Path]::GetRelativePath($repoRoot, $_.FullName))" -ForegroundColor DarkGray }
    Write-Host ''
    return
}

$target = $unique[0].FullName

# SQL files go through Invoke-RepoSql; PS files are called directly.
if ($target -like '*.sql') {
    $runner = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'
    $target = $runner
    $Arguments = @('-ScriptPath', $unique[0].FullName) + $Arguments
}

# Parse remaining string args into a hashtable so named params survive splatting.
$splat    = @{}
$orphans  = @()
$i = 0
while ($i -lt $Arguments.Count) {
    if ($Arguments[$i] -match '^-{1,2}(.+)$') {
        $key = $Matches[1]
        if (($i + 1) -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^-') {
            $splat[$key] = $Arguments[$i + 1]
            $i += 2
        } else {
            $splat[$key] = $true
            $i++
        }
    } else {
        $orphans += $Arguments[$i]
        $i++
    }
}

# Common parameter aliases: wrappers declare -ServerInstance, but DBAs type -Server,
# -ServerName, -Instance or -S (and -Db / -Format). Simple wrapper scripts silently drop
# unknown named params into $args, so without this mapping the script runs against the
# DEFAULT instance while looking like it accepted your server name.
$aliasMap = @{
    server = 'ServerInstance'; servername = 'ServerInstance'; instance = 'ServerInstance'
    sqlserver = 'ServerInstance'
    db = 'Database'; databasename = 'Database'
    format = 'OutputFormat'; output = 'OutputFormat'
}
foreach ($k in @($splat.Keys)) {
    $canon = $aliasMap[$k.ToLower()]
    if ($canon -and -not $splat.ContainsKey($canon)) {
        $splat[$canon] = $splat[$k]
        [void]$splat.Remove($k)
        Write-Host "Treating -$k as -$canon." -ForegroundColor DarkGray
    }
}

# A bare positional token is almost always a server name typed without -ServerInstance
# (.\run.ps1 Get-Something MYSERVER). Silently dropping it would run against the wrong
# server — treat the first one as ServerInstance and say so.
if ($orphans.Count -gt 0) {
    if (-not $splat.ContainsKey('ServerInstance')) {
        $splat['ServerInstance'] = $orphans[0]
        Write-Host "Treating '$($orphans[0])' as -ServerInstance." -ForegroundColor DarkGray
        $orphans = @($orphans | Select-Object -Skip 1)
    }
    if ($orphans.Count -gt 0) {
        Write-Host "Ignoring unrecognised argument(s): $($orphans -join ', ') — use named parameters (e.g. -OutputFormat Csv)." -ForegroundColor Yellow
    }
}

Write-Host "Running: $([System.IO.Path]::GetRelativePath($repoRoot, $target))" -ForegroundColor Cyan
if ($splat.Count -gt 0) { & $target @splat } else { & $target }
