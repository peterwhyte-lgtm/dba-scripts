# Collectors

Point-in-time scripts tell you what is happening now. Collectors tell you what changed. Each script
here generates a SQL Agent job that snapshots one thing on a schedule into a `DBAMonitor` database, so
that three weeks later you can answer "when did this start" instead of guessing.

Twelve collectors, one alert job, and three delta queries.

## How they work

**These scripts do not change anything when you run them.** They are marked `SAFE:ReadOnly` because
their output *is* a T-SQL script — the DDL to create the database, the table, and the Agent job. You
read that output, decide you are happy with it, and run it yourself on the target instance.

The flow for any collector:

1. Open the `Generate-CollectorJob-*.sql` script and edit the parameter block at the top.
2. Run it. The result set is the DDL.
3. Read the DDL. Run it on the instance you want collecting.

Every collector exposes the same parameters:

| Parameter | Default | Notes |
|-----------|---------|-------|
| `@TargetDatabase` | `DBAMonitor` | Created by the generated DDL if it does not exist |
| `@JobOwner` | `sa` | Change this if `sa` is disabled on your instance |
| `@CategoryName` | `DBA Collectors` | The Agent job category |
| `@IntervalMinutes` | per collector, see below | How often the job runs |

Running the generated DDL needs **sysadmin**. The job itself runs as its owner and needs
`VIEW SERVER STATE` (a few need `VIEW ANY DEFINITION` or database-level rights — each script's
`Requires` line is specific).

## The collectors

| Script | Agent job | Default interval | Captures |
|--------|-----------|-----------------:|----------|
| `Generate-CollectorJob-Blocking` | `DBA - Collect Blocking` | 2 min | Active blocking chains |
| `Generate-CollectorJob-AgHealth` | `DBA - Collect AG Health` | 5 min | Always On replica sync state and latency |
| `Generate-CollectorJob-Deadlocks` | `DBA - Collect Deadlocks` | 5 min | Deadlock events from the system_health ring buffer |
| `Generate-CollectorJob-Perfmon` | `DBA - Collect Perfmon` | 5 min | OS and SQL Server performance counters |
| `Generate-CollectorJob-ErrorLog` | `DBA - Collect Error Log` | 10 min | Error log entries by severity |
| `Generate-CollectorJob-Tempdb` | `DBA - Collect TempDB` | 10 min | TempDB space use per session |
| `Generate-CollectorJob-WaitStats` | `DBA - Collect Wait Stats` | 15 min | Wait type snapshot |
| `Generate-CollectorJob-QueryStore` | `DBA - Collect Query Store` | 30 min | Top queries from Query Store |
| `Generate-CollectorJob-StorageIO` | `DBA - Collect Storage IO` | 30 min | Database file I/O per volume |
| `Generate-CollectorJob-DatabaseGrowth` | `DBA - Collect Database Growth` | 60 min | Database file sizes, for growth trending |
| `Generate-CollectorJob-VlfCount` | `DBA - Collect VLF Count` | daily | VLF count per database log |
| `Generate-CollectorJob-IndexFragmentation` | `DBA - Collect Index Fragmentation` | weekly | Index fragmentation snapshot |

Plus `Generate-CollectorAlertJob` (`DBA - Collector Alert`, 30 min), which reads the tables the
collectors have filled, applies threshold checks, outputs the findings, and raises an error on any
`CRITICAL` result so the job fails visibly rather than passing quietly.

## Reading the history back

Three of the collectors write a **temporal** table pair — `collector.AgHealthCurrent` /
`AgHealthHistory`, and the same shape for `DatabaseGrowth` and `VlfCount`. Those jobs `MERGE` the
current state and SQL Server keeps the history for you, so `FOR SYSTEM_TIME` queries work. The rest
append one row-batch per run.

Wait stats, storage I/O, and perfmon collect counters that accumulate rather than reset, so a single
snapshot is close to useless on its own. Diff two adjacent snapshots instead:

| Script | Reads |
|--------|-------|
| `Get-WaitStatsDelta` | `collector.WaitStats` — delta wait ms, task count, average wait per task, share of interval |
| `Get-StorageIODelta` | `collector.StorageIO` — read/write counts, bytes, derived average latency for the interval |
| `Get-PerfmonDelta` | `collector.Perfmon` — interval deltas for the cumulative counters |

Each compares the two most recent snapshots. The wait stats collector also records
`sqlserver_start_time`, so a delta that spans a restart can be detected rather than silently reported
as a negative.

For longer-range analysis over the same tables, `powershell/reporting/Get-CapacityProjection.ps1`
turns the growth history into days-until-full.

## Notes

- **Nothing here is in the web UI**, and none of these scripts has a PowerShell wrapper. They are
  deployed once per instance and then run on a schedule; there is nothing to launch on demand.
- **Start with two or three.** Every job costs a little overhead and a lot of rows. Blocking at 2
  minutes and perfmon at 5 add up faster than you expect on a busy instance.
- **Nothing prunes these tables.** Decide on a retention window and add your own cleanup job, or the
  `DBAMonitor` database will grow forever.
