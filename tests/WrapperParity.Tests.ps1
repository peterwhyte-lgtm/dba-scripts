#Requires -Modules Pester

<#
Pester tests — every SQL script in sql/ (with documented exclusions) must have a
matching PowerShell wrapper in powershell/wrappers/.

Excluded categories:
  sql/lab/        — dev/test scripts, not exposed in web UI
  sql/collectors/ — SQL Agent job DDL; no wrapper needed, served via sql/collectors/ directly

Excluded scripts (served by non-wrapper orchestrators):
  sql/migration/Generate-*.sql        — served by powershell/migration/Generate-*.ps1 orchestrators
                                        which use Invoke-Sqlcmd directly (DDL generators, not Invoke-RepoSql)
  sql/performance/Get-ActiveRequests.sql         — served by powershell/diagnostics/Get-ActiveRequests.ps1
  sql/performance/Get-ActiveRequestsWithPlan.sql — served by Get-ActiveRequests.ps1 -IncludePlan
  sql/performance/Get-BlockingChains.sql         — served by powershell/diagnostics/Get-BlockingChains.ps1
  sql/performance/Get-BlockingChainsWithPlan.sql — served by Get-BlockingChains.ps1 -IncludePlan

No SQL Server connection required.

Run from repo root:
    Invoke-Pester tests/WrapperParity.Tests.ps1
#>

$repoRoot    = (Resolve-Path "$PSScriptRoot\..")
$sqlRoot     = Join-Path $repoRoot 'sql'
$wrapperRoot = Join-Path $repoRoot 'powershell\wrappers'

# Scripts intentionally served by orchestrators rather than thin wrappers
$orchestratorServed = @(
    'Get-ActiveRequests',
    'Get-ActiveRequestsWithPlan',
    'Get-BlockingChains',
    'Get-BlockingChainsWithPlan'
)

$sqlFiles = Get-ChildItem $sqlRoot -Recurse -Filter '*.sql' -File |
    Where-Object { $_.FullName -notmatch '\\(lab|collectors)\\' } |
    Where-Object { -not ($_.FullName -match '\\migration\\' -and $_.BaseName -like 'Generate-*') } |
    Where-Object { $orchestratorServed -notcontains $_.BaseName }

$testCases = @($sqlFiles | ForEach-Object {
    @{
        SqlRelPath  = $_.FullName.Replace($repoRoot.Path + '\', '')
        ScriptName  = $_.BaseName
    }
})

Describe 'Wrapper parity' {

    It 'found SQL scripts to check' -TestCases @(@{ Count = $sqlFiles.Count }) {
        param($Count)
        $Count | Should -BeGreaterThan 0
    }

    It '<SqlRelPath> has a matching wrapper in powershell/wrappers/' -TestCases $testCases {
        param($SqlRelPath, $ScriptName)
        $match = Get-ChildItem $wrapperRoot -Recurse -Filter "$ScriptName.ps1" -File -ErrorAction SilentlyContinue
        $match.Count | Should -BeGreaterThan 0
    }
}
