# Helpers

This folder is the quick-access layer for the DBA repo during day-to-day development and AI-assisted work.

## What belongs here

- Repo navigation and triage helpers
- Local SQL connectivity and script execution helpers
- Output cleanup and task routing utilities

## Useful commands

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\Show-RepoOverview.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\local-sql\Test-SqlConnectivity.ps1 -ServerInstance . -Database master
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\Invoke-SqlFile.ps1 -ScriptPath .\categories\storage-capacity-management\sql\Get-DatabaseSizesAndFreeSpace.sql
```

## Helpful helpers
- local-sql/Test-SqlConnectivity.ps1 - verify SQL connectivity and server details before running scripts
- local-sql/Invoke-RepoSql.ps1 - run repo SQL scripts locally against your SQL Server instance with CSV or terminal output
- Quick-RepoCheck.ps1 - verify the repo is ready
- Find-UsefulScript.ps1 - locate the most relevant existing script for a keyword
- Quick-TaskRouter.ps1 - route a DBA task to the best category
- Generate-NextScript.ps1 - scaffold a new SQL starter script for a task
- Generate-NextPowerShell.ps1 - scaffold a new PowerShell starter helper for a task
- Show-RepoOverview.ps1 - inventory the repo structure
- Clear-OutputFiles.ps1 - clean generated output
