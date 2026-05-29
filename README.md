# DBA Scripts

A curated collection of practical SQL Server scripts used in real production environments.
Focused on performance, backups, configuration, security, and operational visibility.
Built for DBAs who need answers quickly.

This repository is designed to support the DBA Scripts section of the site and to give production SQL Server DBAs a fast, copy/paste-friendly toolkit for daily troubleshooting and operational checks.

## What is included

- Production-safe diagnostics and monitoring scripts for day-to-day DBA work
- SSMS-first SQL queries with practical comments and evidence-oriented output
- PowerShell helpers for local ops, cleanup, and quick triage
- Lab/test scripts for environment setup and database generation
- A category-first layout under categories/ for the DBA workflow
- A dedicated sql-templates/ operations layer for repeatable DBA runbooks and operational templates
- Top-level helpers/ and tools/ folders for reusable utilities and repo maintenance
- A small helper layer in helpers/ for quick repo checks, script discovery, and task routing during AI-assisted work

## Start here

If you want the fastest path into the repo, use this order:
1. Run `helpers/Show-RepoOverview.ps1` to get the repo inventory.
2. Open the category that matches the incident or task.
3. Use `helpers/local-sql/Test-SqlConnectivity.ps1` and `helpers/Invoke-SqlFile.ps1` for local SQL validation and execution.
4. Use `sql-templates/operations` when you need a production-style runbook or change-order template.
5. Save any outputs you want to reuse under `output-files/`.

### Example commands

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\Show-RepoOverview.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\Invoke-SqlFile.ps1 -ScriptPath .\categories\storage-capacity-management\sql\Get-DatabaseSizesAndFreeSpace.sql
```

## What we are optimizing for

- Fast copy/paste into SSMS or Azure Data Studio
- Clear category grouping by real DBA task
- Easy handoff to other production DBAs
- A solid foundation for future blog posts and runbooks

## Category map at a glance

Use the category-first layout under categories/:

- performance-troubleshooting — blocking, waits, long-running queries, missing indexes, and I/O analysis
- storage-capacity-management — database size, disk space, transaction log usage, and growth risk
- backups-and-recovery — backup coverage, restore prep, backup history, and DR readiness
- maintenance-and-reliability — integrity checks, fragmentation, TempDB, and health routines
- configuration-and-environment — instance settings, memory, MAXDOP, jobs, and environment snapshots
- security-and-permissions — server and database permissions, role audits, and access reviews
- high-availability-and-disaster-recovery — AG and DR checks, failover prep, and resilience validation
- dba-lab-scripts — test database creation, cleanup, and lab automation

Use sql-templates/operations for the production-style runbook templates that complement the category scripts.

## How to use this repo

1. Start in categories/<area>/sql for the SSMS-ready analysis scripts.
2. Use categories/<area>/powershell for automation and local troubleshooting helpers.
3. Use sql-templates/operations for runbook-style SQL templates such as statistics maintenance, CDC, TDE, and upgrade readiness.
4. Use helpers/ for repo-wide utilities such as Show-RepoOverview.ps1 and Clear-OutputFiles.ps1, and helpers/local-sql/ for local connectivity checks and repo SQL execution.
5. Use tools/ for repo maintenance and catalog tasks.
6. Read docs/structure.md for the high-level and low-level repo map.
7. Treat the scripts as production-safe starting points and extend them for your environment.

## Notes

- Folder names are lowercase for consistency.
- Scripts are grouped by real production DBA use case.
- The DBA Lab Scripts area is intentionally separate for test and simulation work.
- Use docs/ for runbooks, templates, and operational notes.
