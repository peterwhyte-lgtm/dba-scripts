# Repo structure overview

This file gives both the high-level and low-level view of the DBA scripts repo.

## High-level layout

The repo should use two views at the same time:

1. Canonical working map (current): sql/, powershell/, hybrid/, docs/, examples/
   - sql/ — SSMS-ready queries and reports
   - powershell/ — automation helpers and local troubleshooting scripts
   - hybrid/ — repo runners, reporting, and operational glue
2. Compatibility map (legacy): categories/ — DBA-first navigation for older references and migrations
   - sql/performance/, backups/, security/, monitoring/
   - powershell/inventory/, backup-automation/, reporting/, health-checks/
   - hybrid/sql-inventory-reporting/, agent-job-monitoring/, backup-validation/

This layout keeps the repo usable now while giving the toolkit a cleaner long-term structure for production use. The canonical top-level folders now contain the real migrated SQL and PowerShell scripts, and the legacy category tree remains only as a compatibility map.

- helpers/ — quick-access utilities for repo guidance, cleanup, and script generation
- tools/ — repo maintenance and support utilities
- sql-templates/ — operational SQL templates and runbook-style scripts
  - operations/ — templates for statistics maintenance, CDC, TDE, and upgrade readiness
- output-files/ — generated reports, demo exports, and backup-review snapshots
- docs/ — runbooks, roadmap, catalog, and structure notes

## Low-level working view

1. Start with helpers/triage/Show-RepoOverview.ps1 to see the current repo inventory.
2. Pick the relevant script in sql/ or powershell/ for the task you are working on.
3. Use the legacy categories/ tree only for compatibility references that still point to migrated work.
4. Use sql-templates/operations for runbook-style DBA execution templates.
5. Use helpers/ for repo-wide convenience tasks.
6. Use output-files/ for generated outputs and demos.

## Practical rule of thumb

- If you need to inspect a problem, open the matching SQL script under `sql/` first.
- If you need to automate or validate locally, open the matching PowerShell helper under `powershell/`.
- When the canonical layout is implemented, place operational SQL under `sql/<domain>/`, automation under `powershell/<domain>/`, and glue/reporting workflows under `hybrid/<workflow>/`.
- If you need to run SQL from this repo against your local instance, use `helpers/local-sql/Test-SqlConnectivity.ps1` and `helpers/local-sql/Invoke-RepoSql.ps1`.
- If you need to clean generated output, use `helpers/maintenance/Clear-OutputFiles.ps1`.
- If you want a starter script quickly, use `helpers/scaffolding/Generate-NextScript.ps1` or `helpers/scaffolding/Generate-NextPowerShell.ps1`.

### Example entry points

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\triage\Show-RepoOverview.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\local-sql\Invoke-SqlFile.ps1 -ScriptPath .\sql\storage-capacity-management\Get-DatabaseSizesAndFreeSpace.sql
```
