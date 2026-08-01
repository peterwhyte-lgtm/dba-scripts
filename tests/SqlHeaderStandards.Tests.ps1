#Requires -Modules Pester

<#
Pester smoke tests — every SQL script in sql/ must meet the header standard
defined in CLAUDE.md and docs/standards.md.

No SQL Server connection required.

Excluded categories:
  sql/lab/        — dev/test scripts, held to a lower standard
  sql/collectors/ — SQL Agent job DDL generators, different format

Run from repo root:
    Invoke-Pester tests/SqlHeaderStandards.Tests.ps1
#>

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$sqlRoot  = Join-Path $repoRoot 'sql'

$sqlFiles = Get-ChildItem $sqlRoot -Recurse -Filter '*.sql' -File |
    Where-Object { $_.FullName -notmatch '\\(lab|collectors)\\' }

$testCases = @($sqlFiles | ForEach-Object {
    @{
        SqlRelPath = $_.FullName.Replace($repoRoot + '\', '')
        FullPath   = $_.FullName
    }
})

Describe 'SQL script header standards' {

    It 'found SQL scripts to check' -TestCases @(@{ Count = $sqlFiles.Count }) {
        param($Count)
        $Count | Should -BeGreaterThan 0
    }

    It '<SqlRelPath> has all required header fields' -TestCases $testCases {
        param($SqlRelPath, $FullPath)
        $content = Get-Content $FullPath -Raw
        $content | Should -Match 'Script Name\s*:'
        $content | Should -Match 'Category\s*:'
        $content | Should -Match 'Purpose\s*:'
        $content | Should -Match 'Author\s*:'
        $content | Should -Match 'Requires\s*:'
    }

    It '<SqlRelPath> has valid -- SAFE: and -- IMPACT: annotations' -TestCases $testCases {
        param($SqlRelPath, $FullPath)
        $content = Get-Content $FullPath -Raw
        $content | Should -Match '-- SAFE:(ReadOnly|WritesData|CreatesObjects)'
        $content | Should -Match '-- IMPACT:(Low|Medium|High)'
    }
}
