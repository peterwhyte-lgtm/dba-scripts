# PowerShell layer

Two different things live here, and the distinction matters more than anything else on this page.

- **`wrappers/`** — 153 thin shims, one per SQL script. They contain no logic. They resolve the repo
  root, find the matching `.sql` file, and hand your parameters to `tools\local-sql\Invoke-RepoSql.ps1`.
  A SQL script only appears in the web UI if it has one.
- **everything else** — 52 scripts that do real work: orchestrators, DDL generators, live incident
  runners, and OS-level tools that never touch a `.sql` file.

Full descriptions of all 52: [docs/script-catalog.md](../docs/script-catalog.md).

## Layout

```text
powershell/
  reporting/            — health check collection, rules review, AI assessment, client report,
                          multi-server health check, capacity projection, configuration drift
    multi-server/       — 13 self-contained fleet scripts (see its own README)
  diagnostics/          — live incident triage: Get-ActiveRequests, Get-BlockingChains
                          (both take -IncludePlan to export execution plans)
  migration/            — pre-flight and assessment orchestrators, plus the DDL generators that
                          write .sql files to output-files\migration\
  inventory/            — Get-InstanceSnapshot, Get-InstanceHealthSummary, Test-OsConfiguration
  disk-space/           — Windows-side checks: Get-DiskSpaceSummary, Get-LargestFolders,
                          Get-OldestBackupFolderFiles, Get-BackupAge
  installation/         — install, configure, validate, uninstall SQL Server; templates/ holds
                          the .ini answer files
  patching/             — patch-summary.ps1, Patch-SqlServer.ps1
    sql/                — Invoke-SqlPatch.ps1 (multi-server), patch-config.psd1
    ssms/               — install-ssms.ps1, uninstall-ssms.ps1
  lab/                  — dev and test only

  wrappers/             — thin shims; the folder tree mirrors sql/ exactly
    inventory/          backups/          maintenance/      migration/
    high-availability/  traces/
    monitoring/         — plus instance/ databases/ disk-space/ tempdb/ jobs/ error-log/ features/
    performance/        — plus active-sessions/ blocking-locking/ indexes/ queries/ query-store/
    security/           — plus access/ encryption/
```

## Key rules

- **Wrapper depth depends on where it sits.** `powershell/wrappers/<category>/` is 3 levels from the
  repo root (`$PSScriptRoot '..\..\..'`); `powershell/wrappers/<category>/<subfolder>/` is 4
  (`$PSScriptRoot '..\..\..\..'`). Getting this wrong is the most common way a new wrapper breaks.
- **Orchestrators** in `powershell/<subfolder>/` are 2 levels from the root (`$PSScriptRoot '..\..'`).
- Every wrapper delegates to `tools\local-sql\Invoke-RepoSql.ps1`. No wrapper calls `Invoke-Sqlcmd`
  directly.
- The wrapper's SQL path must mirror the `sql/` path exactly, subfolder included.
- Every `.ps1` needs a `.NOTES` block with `ScriptType`, `TargetScope`, `RiskLevel`, and `Purpose`.
- A Pester test (`tests/WrapperParity.Tests.ps1`) fails the build if a SQL script loses its wrapper.

## The two exceptions to "one wrapper per SQL script"

`powershell/diagnostics/` and `powershell/migration/Generate-*.ps1` are deliberately **not** thin
wrappers, and the parity test knows about both:

- **`diagnostics/`** — `Get-ActiveRequests.ps1` and `Get-BlockingChains.ps1` pick between two SQL
  scripts based on `-IncludePlan` (`Get-BlockingChains.sql` or `Get-BlockingChainsWithPlan.sql`) and
  write plan output to `output-files\diagnostics\`. That is why four SQL scripts in
  `sql/performance/` have no wrapper of their own.
- **`migration/Generate-*.ps1`** — these bypass the CSV pipeline entirely. They call `Invoke-Sqlcmd`
  with `MaxCharLength 2000000` to capture the full `NVARCHAR(MAX)` DDL string and write it to a `.sql`
  file under `output-files\migration\`. **Never run them through `Invoke-RepoSql.ps1`** — the CSV path
  truncates the output.

## Adding a new wrapper

```powershell
.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\<subfolder>\Get-Something.sql
```

It works out the category, subfolder, and correct depth from the path you give it. Or copy an existing
wrapper **from the same level** and update the three path variables — copying a category-root wrapper
into a subfolder gives you the wrong depth.
