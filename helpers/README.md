# Helpers

This folder is the quick-access layer for the DBA repo during day-to-day development and AI-assisted work.

## What belongs here

- Repo navigation and triage helpers
- Local SQL connectivity and script execution helpers
- Output cleanup and task routing utilities

## Useful commands

From the repo root, the short forms are now:

```powershell
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-LongRunningQueries
.\run.ps1 categories\performance-troubleshooting\powershell\Get-WaitStatistics.ps1
```

You can also call the helper directly:

```powershell
.\helpers\Run-Helper.ps1 -ScriptName Get-WaitStatistics
.\helpers\Run-Helper.ps1 -ScriptPath .\categories\performance-troubleshooting\powershell\Get-WaitStatistics.ps1
```

## Helper layout
- local-sql/ - direct SQL execution, connectivity checks, and repo script runners
- triage/ - repo sanity checks, discovery, and quick inventory helpers
- scaffolding/ - starter script and helper generation for new DBA work
- maintenance/ - output cleanup and environment maintenance helpers

## Helpful helpers
- local-sql/Test-SqlConnectivity.ps1 - verify SQL connectivity and server details before running scripts
- local-sql/Invoke-RepoSql.ps1 - run repo SQL scripts locally against your SQL Server instance with CSV or terminal output
- triage/Quick-RepoCheck.ps1 - verify the repo is ready
- triage/Find-UsefulScript.ps1 - locate the most relevant existing script for a keyword
- triage/Quick-TaskRouter.ps1 - route a DBA task to the best category
- scaffolding/Generate-NextScript.ps1 - scaffold a new SQL starter script for a task
- scaffolding/Generate-NextPowerShell.ps1 - scaffold a new PowerShell starter helper for a task
- triage/Show-RepoOverview.ps1 - inventory the repo structure
- maintenance/Clear-OutputFiles.ps1 - clean generated output
