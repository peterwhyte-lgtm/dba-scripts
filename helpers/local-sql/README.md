# Local SQL helpers

This folder contains the production-focused helpers for running SQL scripts from this repo against a local or remote SQL Server instance.

## Included helpers

- Test-SqlConnectivity.ps1
  - Verifies that the target SQL Server is reachable and reports basic connection details.
- Invoke-RepoSql.ps1
  - Executes a SQL script from the repo and supports terminal or CSV output.

## Recommended workflow

1. Run Test-SqlConnectivity.ps1 to confirm the server and authentication path are working.
2. Run Invoke-RepoSql.ps1 to execute an existing script from categories/ or sql-templates/.
3. Use -OutputFormat Csv and -OutputPath when you want to save results for later review.

## Example: top wait statistics

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\categories\performance-troubleshooting\powershell\Get-WaitStatistics.ps1
```
