# Local SQL helpers

Everything that actually talks to SQL Server on behalf of the repo. Every wrapper and every
`.\run.ps1` call ends up here.

## The helpers

| Script | What it does |
|--------|--------------|
| `Invoke-RepoSql.ps1` | The core runner. Executes a `.sql` file from the repo and returns a table, a CSV, or both |
| `Set-SqlConnection.ps1` | Sets the target server for the whole session so you stop repeating `-ServerInstance` |
| `Test-SqlConnectivity.ps1` | Confirms the server is reachable and reports what it connected as |
| `Test-ServerNetwork.ps1` | DNS and port pre-flight. `Invoke-RepoSql.ps1` runs it automatically when a connection fails, so you get "port closed" or "name does not resolve" instead of a generic timeout |
| `Install-Prerequisites.ps1` | Checks for the SqlServer module / `sqlcmd.exe`. `run.ps1` calls it on every run |
| `Invoke-LocalSql.ps1` | Ad-hoc query runner for a string of T-SQL rather than a repo file |

## Recommended workflow

1. `Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019` — once per session.
2. `Test-SqlConnectivity.ps1` — confirm it works before you start running things.
3. `.\run.ps1 <ScriptName>` — or call a wrapper directly.

```powershell
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa   # SQL auth, prompts
.\tools\local-sql\Set-SqlConnection.ps1 -Show                                 # what is set now
.\tools\local-sql\Set-SqlConnection.ps1 -Clear                                # back to local
```

The session server lives in `$env:DBASCRIPTS_SERVER` (with `DBASCRIPTS_USER` / `DBASCRIPTS_PASS` for
SQL auth) and disappears when the session ends. An explicit `-ServerInstance` on a call always wins.

## What `Invoke-RepoSql.ps1` does

- Tries `Invoke-Sqlcmd` from the SqlServer module first, falls back to `sqlcmd.exe`, throws if neither
  is available.
- **Always writes a CSV**, even when you asked for a table:
  `output-files\reviews\<category>\<script>-<timestamp>.csv`. The category comes from the `sql/` folder
  the script lives in.
- Prints the top 25 rows to the terminal as a table. `-OutputFormat Csv` suppresses that and writes the
  file only; `-TopResults` changes the preview size.
- `-OutputPath` overrides the default file location entirely.
- Prints a `http://localhost:8787/csv?p=...` link for the result, and tells you if the web UI is not
  running.

```powershell
# Run a repo script directly through the runner
.\tools\local-sql\Invoke-RepoSql.ps1 -ScriptPath .\sql\performance\Get-WaitStatistics.sql -ServerInstance .
```

**One thing it cannot do:** capture a large `NVARCHAR(MAX)` value. The `Generate-*` migration scripts
return their whole DDL script as a single value and the CSV pipeline truncates it, which is why
`powershell/migration/Generate-*.ps1` bypasses this runner. See
[`sql/migration/README.md`](../../sql/migration/README.md).

## Worth running early on a new instance

```powershell
.\run.ps1 Get-VersionAndEdition
.\run.ps1 Get-DatabaseSizesAndFreeSpace
.\run.ps1 Get-TransactionLogSizeAndUsage
.\run.ps1 Get-DatabaseGrowthRisk
.\run.ps1 Get-MemoryConfigurationAndUsage
.\run.ps1 Get-TempdbUsage
```
