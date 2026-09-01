<#
.SYNOPSIS
    Fails when work exists on a branch that main does not have.

.DESCRIPTION
    Built 2026-09-01 after the same failure hit twice in one day.

    Fixes get published to sqldba.blog while still sitting on an unmerged branch, so main -- and
    everything reading main -- serves the pre-fix version. Twice, with real cost:

      * fix/trace-flags-resource-governor-services was live on the blog but not on main, so the
        MCP server served 6 wrong trace-flag descriptions and a classifier bug.
      * An em-dash fix in Get-IndexDesignIssues landed on a branch at 10:21 and was re-reported
        as an open defect hours later by a session reading main. The duplicate fix was
        character-for-character identical.

    Neither was caught by a test, because nothing was wrong with the code. What was wrong was
    where the code lived. This is the check for that.

    Sibling of mcp/tests/check_freshness.py, which catches datasets drifting from the repo.
    This is the same class one level up: the repo drifting from itself.

.PARAMETER Remote
    Also fail when local main is ahead of origin/main, i.e. committed but never pushed.

.PARAMETER Quiet
    Print nothing on success. For hooks and CI.

.EXAMPLE
    .\tools\triage\Test-BranchesMerged.ps1
    .\tools\triage\Test-BranchesMerged.ps1 -Remote

.NOTES
    RiskLevel : SAFE
    Type      : runner
    Scope     : single repo, read only. Runs no network call unless -Remote is passed.
    Exit code : 0 clean, 1 unmerged work found, 2 could not determine (not a repo, no main).
#>
[CmdletBinding()]
param(
    [switch]$Remote,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $repoRoot
try {
    if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
        Write-Host "not a git repository: $repoRoot" -ForegroundColor Red
        exit 2
    }
    git rev-parse --verify --quiet main *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'no local branch named main, cannot compare' -ForegroundColor Red
        exit 2
    }

    # every local branch except main, and what main is missing from it
    $problems = @()
    foreach ($b in (git for-each-ref --format='%(refname:short)' refs/heads/)) {
        if ($b -eq 'main') { continue }
        $ahead = @(git rev-list --count "main..$b")[0]
        if ([int]$ahead -gt 0) {
            $subjects = git log --format='%h %s' "main..$b"
            $problems += [pscustomobject]@{
                Kind = 'unmerged branch'; Name = $b; Count = [int]$ahead; Detail = $subjects
            }
        }
    }

    if ($Remote) {
        git rev-parse --verify --quiet origin/main *> $null
        if ($LASTEXITCODE -eq 0) {
            $unpushed = @(git rev-list --count 'origin/main..main')[0]
            if ([int]$unpushed -gt 0) {
                $problems += [pscustomobject]@{
                    Kind = 'unpushed on main'; Name = 'origin/main'; Count = [int]$unpushed
                    Detail = (git log --format='%h %s' 'origin/main..main')
                }
            }
        }
    }

    if ($problems.Count -eq 0) {
        if (-not $Quiet) { Write-Host 'OK: every branch is merged into main.' -ForegroundColor Green }
        exit 0
    }

    Write-Host ''
    Write-Host 'UNMERGED WORK. main does not have everything.' -ForegroundColor Red
    Write-Host 'This is how the blog and the MCP server end up ahead of the repo.' -ForegroundColor Red
    foreach ($p in $problems) {
        Write-Host ''
        Write-Host ("  {0}: {1}  ({2} commit{3})" -f $p.Kind, $p.Name, $p.Count,
            $(if ($p.Count -eq 1) { '' } else { 's' })) -ForegroundColor Yellow
        foreach ($line in $p.Detail) { Write-Host "      $line" }
    }
    Write-Host ''
    Write-Host 'Merge it, or delete the branch if it is dead. Do not leave it.' -ForegroundColor Yellow
    exit 1
}
finally {
    Pop-Location
}
