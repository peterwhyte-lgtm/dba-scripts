# Repo structure overview

This file gives both the high-level and low-level view of the DBA scripts repo.

## High-level layout

- categories/ — DBA-first navigation by real operational topic
  - sql/ — SSMS-ready queries and reports
  - powershell/ — automation helpers and local troubleshooting scripts
- helpers/ — quick-access utilities for repo guidance, cleanup, and script generation
- tools/ — repo maintenance and support utilities
- sql-templates/ — operational SQL templates and runbook-style scripts
  - operations/ — templates for statistics maintenance, CDC, TDE, and upgrade readiness
- output-files/ — generated reports, demo exports, and backup-review snapshots
- docs/ — runbooks, roadmap, catalog, and structure notes

## Low-level working view

1. Start with helpers/triage/Show-RepoOverview.ps1 to see the current repo inventory.
2. Pick the relevant category under categories/<topic>/.
3. Use sql/ for analysis and powershell/ for automations.
4. Use sql-templates/operations for runbook-style DBA execution templates.
5. Use helpers/ for repo-wide convenience tasks.
6. Use output-files/ for generated outputs and demos.

## Practical rule of thumb

- If you need to inspect a problem, open the SQL script in the matching category.
- If you need to automate or validate locally, open the matching PowerShell helper under `categories/<topic>/powershell/`.
- If you need to run SQL from this repo against your local instance, use `helpers/local-sql/Test-SqlConnectivity.ps1` and `helpers/local-sql/Invoke-RepoSql.ps1`.
- If you need to clean generated output, use `helpers/maintenance/Clear-OutputFiles.ps1`.
- If you want a starter script quickly, use `helpers/scaffolding/Generate-NextScript.ps1` or `helpers/scaffolding/Generate-NextPowerShell.ps1`.

### Example entry points

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\triage\Show-RepoOverview.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\local-sql\Invoke-SqlFile.ps1 -ScriptPath .\categories\storage-capacity-management\sql\Get-DatabaseSizesAndFreeSpace.sql
```
