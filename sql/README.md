# SQL scripts

181 scripts you can open, copy, and paste straight into SSMS. No parameters to fill in, no magic
variables, no install step. Every script is a single result set and starts with `SET NOCOUNT ON;`.

Full list with descriptions and companion blog posts: [docs/script-catalog.md](../docs/script-catalog.md).

## Where things are

| Folder | Scripts | What it answers |
|--------|--------:|-----------------|
| [`inventory/`](inventory/) | 12 | What is on this instance — version, OS, databases, services, logins, jobs, linked servers |
| [`monitoring/`](monitoring/) | 46 | Is it healthy, and will it stay that way — config, space, TempDB, Agent jobs, error log, features |
| [`performance/`](performance/) | 37 | Why is it slow — waits, blocking, indexes, queries, Query Store, active sessions |
| [`backups/`](backups/) | 14 | Are we protected, and how fast could we recover |
| [`security/`](security/) | 18 | Who can do what, and is anything exposed |
| [`high-availability/`](high-availability/) | 11 | Always On, failover clustering, mirroring, replication |
| [`migration/`](migration/) | 13 | Getting on or off this server safely — see [migration/README.md](migration/README.md) |
| [`maintenance/`](maintenance/) | 5 | Maintenance job status, and DDL to create the jobs |
| [`collectors/`](collectors/) | 16 | Scheduled history for trend analysis — see [collectors/README.md](collectors/README.md) |
| [`traces/`](traces/) | 6 | Extended Events sessions — see [traces/README.md](traces/README.md) |
| [`lab/`](lab/) | 3 | Dev and test only. Never run these against production |

`monitoring/`, `performance/`, `security/`, and `high-availability/` are split into subfolders by area
(`monitoring/tempdb/`, `performance/indexes/`, `security/access/`, and so on). Browse the folder or use
the catalog — script names describe the outcome, so `Get-BlockingChains` is in
`performance/blocking-locking/` and `Get-VlfCount` is in `monitoring/disk-space/`.

## What is safe to run

**175 of the 181 scripts are read-only.** They read DMVs, system catalog views, and msdb history.
Nothing in `sql/` writes to your databases unless its header says so.

Check the two annotations at the top of any script before you run it:

```sql
-- SAFE:ReadOnly
-- IMPACT:Low
```

| `SAFE:` | Meaning | Where |
|---------|---------|-------|
| `ReadOnly` | Reads only. Safe on production at any time. | 175 scripts |
| `CreatesObjects` | Creates something when you run it. | The three `traces/Create-*` scripts |
| `WritesData` | Changes data. | `lab/` only |

`IMPACT:` is `Low` / `Medium` / `High` and describes the load the script itself puts on the instance,
not the risk of what it returns.

**The `Generate-*` scripts are read-only despite the name.** They build a T-SQL script as their output
and hand it back to you as text — creating backup jobs, migration DDL, collector jobs, and so on.
Nothing happens until you review that output and run it yourself. That covers everything in
`collectors/`, `maintenance/Generate-*`, `backups/Generate-*`, and `migration/Generate-*`.

## Finding a script

```powershell
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking
.\run.ps1 -List
```

## Running one without opening SSMS

Every script here has a matching PowerShell wrapper under `powershell/wrappers/` at the same relative
path, so you can run it by name and get a CSV:

```powershell
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019 -OutputFormat Csv
```

Four folders are deliberately wrapper-free: `lab/` and `collectors/` are not exposed in the web UI,
`migration/Generate-*` is driven by the orchestrators in `powershell/migration/`, and the four
`Get-ActiveRequests*` / `Get-BlockingChains*` scripts are served by the richer runners in
`powershell/diagnostics/` instead. Everything else has a wrapper, and a Pester test fails the build if
one goes missing.

## Adding a script

Header standard and folder rules: [docs/standards.md](../docs/standards.md). Scaffold the wrapper with
`.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\<Name>.sql`.
