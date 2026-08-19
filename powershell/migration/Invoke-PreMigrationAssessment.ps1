<#
.SYNOPSIS
Runs the full pre-migration assessment suite and saves each result as a named CSV in a timestamped folder.

.NOTES
ScriptType   : runner
TargetScope  : single server
RiskLevel    : SAFE

.DESCRIPTION
Orchestrates all sql\migration\ assessment scripts plus key monitoring scripts against the source SQL Server.
Output saved to output-files\migration\assessment\<server>-<timestamp>\.

Run this against the source server before any migration activity.
Address all HIGH findings before proceeding to the migration window.

Scripts collected:
  risk-assessment       - categorised HIGH/MEDIUM/INFO risk findings
  deprecated-features   - deprecated features in active use since last restart
  compat-level-audit    - database compatibility levels vs instance native
  login-audit           - server principals with migration risk classification
  database-health       - database state, recovery model, auto flags
  database-sizes        - data/log sizes and free space per database
  database-files        - per-file paths, sizes, autogrowth settings
  backup-coverage       - databases with missing or stale backups
  agent-jobs            - SQL Agent jobs, owners, schedules
  linked-servers        - linked server inventory
  ag-state              - Availability Group replica sync state
  sysadmin-members      - sysadmin role membership
  security-surface      - xp_cmdshell, CLR, database mail enabled state
  disk-space            - volume free space

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.'.

.PARAMETER OutputRoot
Parent folder for output. Defaults to output-files\migration\assessment under the repo root.

.EXAMPLE
.\powershell\migration\Invoke-PreMigrationAssessment.ps1

.EXAMPLE
.\powershell\migration\Invoke-PreMigrationAssessment.ps1 -ServerInstance PROD01\SQL2019
#>

param(
    [string]$ServerInstance = '.',
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$env:DBASCRIPTS_BATCH  = '1'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner   = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'

if (-not (Test-Path -LiteralPath $runner)) { throw "Runner not found: $runner" }

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'output-files\migration\assessment'
}

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFolder = Join-Path $OutputRoot "$safeName-$timestamp"
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  Pre-Migration Assessment' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Server : $ServerInstance"
Write-Host "  Output : $outFolder"
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'
Write-Host ''

$scripts = @(
    [PSCustomObject]@{ Label = 'risk-assessment';     Path = 'sql\migration\Get-MigrationRiskAssessment.sql' }
    [PSCustomObject]@{ Label = 'deprecated-features'; Path = 'sql\migration\Get-DeprecatedFeaturesInUse.sql' }
    [PSCustomObject]@{ Label = 'compat-level-audit';  Path = 'sql\migration\Get-CompatibilityLevelAudit.sql' }
    [PSCustomObject]@{ Label = 'login-audit';         Path = 'sql\migration\Get-MigrationLoginAudit.sql' }
    [PSCustomObject]@{ Label = 'database-health';     Path = 'sql\monitoring\databases\Get-DatabaseHealth.sql' }
    [PSCustomObject]@{ Label = 'database-sizes';      Path = 'sql\monitoring\disk-space\Get-DatabaseSizesAndFreeSpace.sql' }
    [PSCustomObject]@{ Label = 'database-files';      Path = 'sql\monitoring\disk-space\Get-DatabaseFilesDetail.sql' }
    [PSCustomObject]@{ Label = 'backup-coverage';     Path = 'sql\backups\Get-BackupCoverage.sql' }
    [PSCustomObject]@{ Label = 'agent-jobs';          Path = 'sql\monitoring\jobs\Get-SqlAgentJobOverview.sql' }
    [PSCustomObject]@{ Label = 'linked-servers';      Path = 'sql\inventory\Get-LinkedServerAndJobInventory.sql' }
    [PSCustomObject]@{ Label = 'ag-state';            Path = 'sql\high-availability\always-on\Get-AvailabilityGroupReplicaState.sql' }
    [PSCustomObject]@{ Label = 'sysadmin-members';    Path = 'sql\security\access\Get-SysadminMembers.sql' }
    [PSCustomObject]@{ Label = 'security-surface';    Path = 'sql\security\Get-DatabaseMailAndXpCmdShell.sql' }
    [PSCustomObject]@{ Label = 'disk-space';          Path = 'sql\monitoring\disk-space\Get-DiskSpace.sql' }
)

$summary = [System.Collections.Generic.List[PSObject]]::new()

foreach ($s in $scripts) {
    $sqlPath = Join-Path $repoRoot $s.Path
    $csvPath = Join-Path $outFolder "$($s.Label).csv"
    $status  = 'OK'
    $note    = ''

    if (-not (Test-Path -LiteralPath $sqlPath)) {
        $status = 'SKIPPED'
        $note   = 'SQL file not found'
    }
    else {
        try {
            & $runner -ScriptPath $sqlPath `
                      -ServerInstance $ServerInstance `
                      -Database 'master' `
                      -OutputFormat 'Csv' `
                      -OutputPath $csvPath *>$null
        }
        catch {
            $status = 'FAILED'
            $note   = $_.Exception.Message -replace "`r?`n", ' '
        }
    }

    $color = switch ($status) { 'OK' { 'Green' } 'SKIPPED' { 'Yellow' } default { 'Red' } }
    Write-Host ("  [{0,-8}] {1}" -f $status, $s.Label) -ForegroundColor $color

    $summary.Add([PSCustomObject]@{
        Script  = $s.Label
        Status  = $status
        CsvFile = if ($status -eq 'OK') { Split-Path -Leaf $csvPath } else { '' }
        Note    = $note
    })
}

Write-Host ''
Write-Host '--------------------------------------------'
$ok      = @($summary | Where-Object Status -eq 'OK').Count
$failed  = @($summary | Where-Object Status -eq 'FAILED').Count
$skipped = @($summary | Where-Object Status -eq 'SKIPPED').Count
Write-Host "  OK: $ok  |  Failed: $failed  |  Skipped: $skipped" -ForegroundColor Cyan
Write-Host ''
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Output : $outFolder" -ForegroundColor Green
Write-Host ''
Write-Host '  Next steps:' -ForegroundColor DarkGray
Write-Host '    1. risk-assessment.csv     - address all HIGH findings before proceeding' -ForegroundColor DarkGray
Write-Host '    2. deprecated-features.csv - test application against target compat level' -ForegroundColor DarkGray
Write-Host '    3. login-audit.csv         - run Generate-LoginScript.ps1 to script logins' -ForegroundColor DarkGray
Write-Host '    4. compat-level-audit.csv  - plan compat level upgrade sequence' -ForegroundColor DarkGray
Write-Host '    5. backup-coverage.csv     - confirm backup chain is complete' -ForegroundColor DarkGray
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''
$env:DBASCRIPTS_BATCH = $null