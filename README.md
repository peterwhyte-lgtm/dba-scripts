# DBA Scripts

A production-ready DBA toolkit for SQL Server operations, troubleshooting, and operational review.
It combines SQL analysis, PowerShell automation, and lightweight hybrid helpers so the repo behaves like a real enterprise support library rather than a loose script dump.

The repo is organized into three practical layers:
- SQL layer for DMVs, diagnostics, and read-only investigations
- PowerShell layer for automation, orchestration, and local execution
- Hybrid layer for repo runners, CSV output, and repeatable DBA workflows

This repository is designed to support the DBA Scripts section of the site and to give production SQL Server DBAs a fast, copy/paste-friendly toolkit for daily troubleshooting and operational checks.

## What is included

- Production-safe diagnostics and monitoring scripts for day-to-day DBA work
- SSMS-first SQL queries with practical comments, safety tags, and evidence-oriented output
- PowerShell helpers for local ops, cleanup, orchestration, and quick triage
- A clear separation between investigation scripts, automation helpers, and repo-wide utilities
- A canonical top-level layout under sql/, powershell/, hybrid/, and examples/ that is now the real working model for the repo
- Lab/test scripts for environment setup and database generation
- A legacy compatibility map under categories/ for older references and migration paths
- A dedicated sql-templates/ operations layer for repeatable DBA runbooks and operational templates
- Top-level helpers/ and tools/ folders for reusable utilities and repo maintenance
- A small helper layer in helpers/ for quick repo checks, script discovery, and task routing during AI-assisted work

## Start here

If you want the fastest path into the repo, use this order:
1. Run `helpers/triage/Show-RepoOverview.ps1` to get the repo inventory.
2. Start with the matching script in `sql/` or `powershell/` for the task you are working on.
3. Use `helpers/local-sql/Test-SqlConnectivity.ps1` and `helpers/local-sql/Invoke-SqlFile.ps1` for local SQL validation and execution.
4. Use `sql-templates/operations` when you need a production-style runbook or change-order template.
5. Save any outputs you want to reuse under `output-files/`.

### Example commands

```powershell
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-LongRunningQueries
.\helpers\Run-Helper.ps1 -ScriptName Get-WaitStatistics
.\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master
```

## What we are optimizing for

- Fast copy/paste into SSMS or Azure Data Studio
- Clear category grouping by real DBA task
- Easy handoff to other production DBAs
- A solid foundation for future blog posts and runbooks

## Category map at a glance

Use the canonical top-level layout:

- sql/performance — waits, blocking, long-running queries, missing indexes, and I/O analysis
- sql/backups — backup coverage, restore prep, backup history, and DR readiness
- sql/monitoring — health, memory, MAXDOP, jobs, AG, and environment snapshots
- sql/security — permission and access reviews
- powershell/inventory — storage, growth, instance inventory, and disk analysis
- powershell/backup-automation — backup, restore, and recovery automation helpers
- powershell/reporting — wait, blocking, and index reporting wrappers
- powershell/health-checks — database health and TempDB operational checks

Use sql-templates/operations for the production-style runbook templates that complement the category scripts.

## How to use this repo

1. Start in sql/ for the SSMS-ready analysis scripts.
2. Use powershell/ for automation and local troubleshooting helpers.
3. Use sql-templates/operations for runbook-style SQL templates such as statistics maintenance, CDC, TDE, and upgrade readiness.
4. Use helpers/triage/ for repo inventory and discovery, helpers/maintenance/ for cleanup, and helpers/local-sql/ for local connectivity checks and repo SQL execution.
5. Use tools/ for repo maintenance and catalog tasks.
6. Read docs/structure.md for the high-level and low-level repo map.
7. Treat the scripts as production-safe starting points and extend them for your environment.

## Notes

- Folder names are lowercase for consistency.
- Scripts are grouped by real production DBA use case.
- The DBA Lab Scripts area is intentionally separate for test and simulation work.
- Use docs/ for runbooks, templates, and operational notes.
