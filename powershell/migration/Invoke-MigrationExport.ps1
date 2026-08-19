<#
.SYNOPSIS
Generates all migration artifacts for a single source SQL Server instance — ready for execution on the target.

.NOTES
ScriptType   : runner
TargetScope  : single server (source)
RiskLevel    : SAFE
Purpose      : One-command export of logins, agent jobs, linked servers, server config, restore
               scripts, and validation baseline. Run against each source server before the migration window.

.DESCRIPTION
Runs the full set of migration DDL-generation scripts against the source server and saves
each output file into a dated folder under output-files\migration\export\<server>-<timestamp>\.

Files produced:
  00-pre-migration-assessment\    — CSV inventory from Invoke-PreMigrationAssessment.ps1
  logins.sql                      — CREATE LOGIN with SIDs (Generate-LoginScript.sql)
  agent-jobs.sql                  — sp_add_job DDL (Generate-AgentJobScript.sql)
  linked-servers.sql              — sp_addlinkedserver DDL (Generate-LinkedServerScript.sql)
  user-mappings.sql               — ALTER USER mappings per database (Generate-UserMappingScript.sql)
  full-backup.sql                 — BACKUP DATABASE for all online user databases
  restore-with-move.sql           — RESTORE DATABASE with WITH MOVE (path substitution)
  validation-baseline.csv         — source server counts — compare against target post-migration

Apply files on the target in this order:
  1. full-backup.sql          — run on SOURCE (take backups)
  2. logins.sql               — run on TARGET (create logins)
  3. restore-with-move.sql    — run on TARGET (restore databases)
  4. agent-jobs.sql           — run on TARGET
  5. linked-servers.sql       — run on TARGET (enter ENTER_PASSWORD_HERE values manually)
  6. user-mappings.sql        — run on TARGET (Fix-OrphanedUsers.sql for any remainders)
  7. validation-baseline.csv  — diff against target's Get-PostMigrationValidation.sql output

.PARAMETER ServerInstance
Source SQL Server instance. Defaults to '.'.

.PARAMETER OutputRoot
Parent folder for export output. Defaults to output-files\migration\export under the repo root.

.EXAMPLE
.\powershell\migration\Invoke-MigrationExport.ps1 -ServerInstance PROD01

.EXAMPLE
.\powershell\migration\Invoke-MigrationExport.ps1 -ServerInstance PROD01\SQL2019 -OutputRoot E:\Migrations
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
    $OutputRoot = Join-Path $repoRoot 'output-files\migration\export'
}

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFolder = Join-Path $OutputRoot "$safeName-$timestamp"
New-Item -ItemType Directory -Path $outFolder -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  Migration Export' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Server : $ServerInstance"
Write-Host "  Output : $outFolder"
Write-Host "  Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host '--------------------------------------------'
Write-Host ''

# ── Helper ────────────────────────────────────────────────────────────────────

function Run-SqlExport {
    param(
        [string]$Label,
        [string]$SqlRelPath,
        [string]$OutFile,
        [string]$Format = 'Csv'   # 'Csv' or 'DdlFile'
    )

    $sqlPath = Join-Path $repoRoot $SqlRelPath
    $outPath = Join-Path $outFolder $OutFile
    $status  = 'OK'
    $note    = ''

    if (-not (Test-Path -LiteralPath $sqlPath)) {
        $status = 'SKIPPED'; $note = 'SQL file not found'
    }
    else {
        try {
            & $runner -ScriptPath $sqlPath `
                      -ServerInstance $ServerInstance `
                      -Database 'master' `
                      -OutputFormat $Format `
                      -OutputPath $outPath *>$null
        }
        catch {
            $status = 'FAILED'; $note = $_.Exception.Message -replace "`r?`n", ' '
        }
    }

    $color = switch ($status) { 'OK' { 'Green' } 'SKIPPED' { 'Yellow' } default { 'Red' } }
    Write-Host ("  [{0,-8}] {1,-30} → {2}" -f $status, $Label, $OutFile) -ForegroundColor $color
    if ($note) { Write-Host "             $note" -ForegroundColor DarkGray }
}

# ── Phase 0: Pre-migration assessment (CSVs) ─────────────────────────────────

Write-Host '  Phase 0 - Pre-migration assessment' -ForegroundColor DarkCyan

$assessFolder = Join-Path $outFolder '00-pre-migration-assessment'
$assessScript = Join-Path $repoRoot 'powershell\migration\Invoke-PreMigrationAssessment.ps1'

if (Test-Path -LiteralPath $assessScript) {
    try {
        & $assessScript -ServerInstance $ServerInstance -OutputRoot $assessFolder
        Write-Host "  [OK      ] pre-migration assessment             → 00-pre-migration-assessment\" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FAILED  ] pre-migration assessment" -ForegroundColor Red
        Write-Host "             $($_.Exception.Message -replace '`r?`n', ' ')" -ForegroundColor DarkGray
    }
}
else {
    Write-Host '  [SKIPPED ] pre-migration assessment (script not found)' -ForegroundColor Yellow
}

Write-Host ''

# ── Phase 1: DDL generation scripts ──────────────────────────────────────────

Write-Host '  Phase 1 - Generate migration DDL' -ForegroundColor DarkCyan

# Determine the DDL output format the runner supports
# For DDL-generating scripts (they return a single 'ddl' or 'script' column),
# use Csv format and let the user copy the value from the CSV — or use DdlFile if supported.
# Using Csv here for compatibility; the runner's DdlFile mode extracts the first column automatically.

$ddlScripts = @(
    [PSCustomObject]@{ Label = 'logins';            Path = 'sql\migration\Generate-LoginScript.sql';          Out = 'logins.sql' }
    [PSCustomObject]@{ Label = 'agent-jobs';         Path = 'sql\migration\Generate-AgentJobScript.sql';       Out = 'agent-jobs.sql' }
    [PSCustomObject]@{ Label = 'linked-servers';     Path = 'sql\migration\Generate-LinkedServerScript.sql';   Out = 'linked-servers.sql' }
    [PSCustomObject]@{ Label = 'user-mappings';      Path = 'sql\migration\Generate-UserMappingScript.sql';    Out = 'user-mappings.sql' }
    [PSCustomObject]@{ Label = 'full-backup';        Path = 'sql\backups\Generate-FullBackupScript.sql';       Out = 'full-backup.sql' }
    [PSCustomObject]@{ Label = 'restore-with-move';  Path = 'sql\migration\Generate-RestoreWithMoveScript.sql';Out = 'restore-with-move.sql' }
)

foreach ($s in $ddlScripts) {
    Run-SqlExport -Label $s.Label -SqlRelPath $s.Path -OutFile $s.Out -Format 'DdlFile'
}

Write-Host ''

# ── Phase 2: Validation baseline ─────────────────────────────────────────────

Write-Host '  Phase 2 - Capture validation baseline' -ForegroundColor DarkCyan
Run-SqlExport -Label 'validation-baseline' -SqlRelPath 'sql\migration\Get-PostMigrationValidation.sql' -OutFile 'validation-baseline.csv' -Format 'Csv'

Write-Host ''

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host "  Export folder : $outFolder" -ForegroundColor Green
Write-Host ''
Write-Host '  Checklist - apply on TARGET in this order:' -ForegroundColor DarkGray
Write-Host '    1. Configure target: TempDB files, sp_configure, drive layout' -ForegroundColor DarkGray
Write-Host '    2. Review full-backup.sql - set @BackupPath, run on SOURCE' -ForegroundColor DarkGray
Write-Host '    3. Run logins.sql on TARGET' -ForegroundColor DarkGray
Write-Host '    4. Review restore-with-move.sql - set @NewDataRoot/@NewLogRoot/@ts, run on TARGET' -ForegroundColor DarkGray
Write-Host '    5. Run agent-jobs.sql on TARGET' -ForegroundColor DarkGray
Write-Host '    6. Run linked-servers.sql on TARGET (fill ENTER_PASSWORD_HERE values)' -ForegroundColor DarkGray
Write-Host '    7. Run user-mappings.sql on TARGET' -ForegroundColor DarkGray
Write-Host '    8. Run Get-PostMigrationValidation.sql on TARGET - diff against validation-baseline.csv' -ForegroundColor DarkGray
Write-Host '    9. DNS cutover - see RUNBOOK-Standalone.md Phase 7' -ForegroundColor DarkGray
Write-Host ('─' * 64) -ForegroundColor DarkCyan
Write-Host ''

$env:DBASCRIPTS_BATCH = $null