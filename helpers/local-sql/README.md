# Local SQL helpers

This folder contains the production-focused helpers for running SQL scripts from this repo against a local or remote SQL Server instance.

## Included helpers

- Test-SqlConnectivity.ps1
  - Verifies that the target SQL Server is reachable and reports basic connection details.
- Invoke-RepoSql.ps1
  - Executes a SQL script from the repo and supports terminal or CSV output.

## Recommended workflow

1. Run Test-SqlConnectivity.ps1 to confirm the server and authentication path are working.
2. Run Invoke-RepoSql.ps1 to execute an existing script from sql/, powershell/, or helpers/.
3. The helper now saves a full CSV copy to output-files/reviews/<category>/<script>-<timestamp>.csv by default, and it also shows the top 25 rows in the terminal for quick review.
4. Use -OutputFormat Csv and -OutputPath when you want to override the default collection path.

## Example: top wait statistics

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\reporting\Get-WaitStatistics.ps1
```

## Extra high-value review wrappers

```powershell
./run.ps1 Get-DatabaseSizesAndFreeSpace
./run.ps1 Get-TransactionLogSizeAndUsage
./run.ps1 Get-DatabaseGrowthRisk
./run.ps1 Get-MemoryConfigurationAndUsage
./run.ps1 Get-TempdbUsage
```
