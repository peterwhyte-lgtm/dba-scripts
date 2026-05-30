# Wait Stats Collector

Captures timestamped snapshots of `sys.dm_os_wait_stats` on a schedule. Builds a historical
record that can be diffed to see what SQL Server was waiting on during any given interval.

## Why this exists

`Get-WaitStatistics.sql` (in `sql/performance/`) shows cumulative totals since the last
SQL Server restart — useful for a point-in-time picture but not for trend analysis.
This collector captures the full raw snapshot every 15 minutes so you can answer:

- What were the top waits between 2am and 3am last Tuesday?
- Has PAGEIOLATCH_SH been trending up over the last week?
- Did waits change after the index rebuild job ran at midnight?

## Output

Daily CSV files at `output-files/collectors/wait-stats/`:

```text
<server>-<YYYYMMDD>.csv         wait stats snapshots for that day
<server>-collector.log          run log (one line per execution)
```

Each row in the CSV is one wait type from one snapshot run. Columns:

| Column | Description |
|--------|-------------|
| `collection_time` | When the snapshot was taken (SQL Server time) |
| `server_name` | `@@SERVERNAME` — identifies the source in multi-server setups |
| `sqlserver_start_time` | SQL Server start time — use to detect restarts between snapshots |
| `wait_type` | Wait type name |
| `waiting_tasks_count` | Cumulative task count since SQL Server start |
| `wait_time_ms` | Cumulative wait time (ms) since start |
| `max_wait_time_ms` | Longest single wait observed since start |
| `signal_wait_time_ms` | Time waiting on CPU scheduler (cpu pressure indicator) |
| `resource_wait_time_ms` | `wait_time_ms - signal_wait_time_ms` (actual resource waits) |

## How to calculate deltas

The counters are cumulative. To get waits for a specific interval:

```text
delta_wait_time_ms   = snapshot2.wait_time_ms   - snapshot1.wait_time_ms
delta_task_count     = snapshot2.waiting_tasks_count - snapshot1.waiting_tasks_count
avg_wait_ms_interval = delta_wait_time_ms / delta_task_count
```

**Restart detection:** If `snapshot2.sqlserver_start_time != snapshot1.sqlserver_start_time`,
the counters reset between the two snapshots. Discard that delta — it is not meaningful.

## Collection frequency

| Environment | Recommended interval | Notes |
|-------------|---------------------|-------|
| Production (busy) | 5–15 minutes | Finer granularity for incident post-mortems |
| Production (quiet) | 15–30 minutes | Sufficient for trend analysis |
| Dev/test | 30–60 minutes | Reduces file size; trend accuracy less critical |

A 15-minute interval on a mid-size server produces ~50–150 rows per snapshot,
or roughly 5,000–15,000 rows per day. A daily CSV stays under 2 MB.

## Running manually

```powershell
# Local instance
.\collectors\wait-stats\Collect-WaitStats.ps1

# Remote instance
.\collectors\wait-stats\Collect-WaitStats.ps1 -ServerInstance PROD01\SQL2019

# Set session default, then run
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\collectors\wait-stats\Collect-WaitStats.ps1
```

## SQL Agent job setup

Run this T-SQL in SSMS to create the collector job. Update the script path and instance
name before running.

```sql
USE msdb;
GO

-- Create job category
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'DBA Collectors')
    EXEC msdb.dbo.sp_add_category
        @class    = N'JOB',
        @type     = N'LOCAL',
        @name     = N'DBA Collectors';
GO

-- Create job
EXEC msdb.dbo.sp_add_job
    @job_name        = N'DBA - Wait Stats Collector',
    @description     = N'Captures wait stats snapshots every 15 minutes for trend analysis.',
    @category_name   = N'DBA Collectors',
    @owner_login_name = N'sa',         -- change to a low-privilege login if preferred
    @enabled         = 1;

-- Add job step (CmdExec — runs as SQL Agent service account)
EXEC msdb.dbo.sp_add_jobstep
    @job_name          = N'DBA - Wait Stats Collector',
    @step_name         = N'Collect',
    @subsystem         = N'CmdExec',
    @command           = N'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\dba-scripts\collectors\wait-stats\Collect-WaitStats.ps1"',
    @on_success_action = 1,   -- quit with success
    @on_fail_action    = 2;   -- quit with failure

-- Create 15-minute recurring schedule
EXEC msdb.dbo.sp_add_schedule
    @schedule_name       = N'Every 15 Minutes',
    @freq_type           = 4,       -- daily
    @freq_interval       = 1,
    @freq_subday_type    = 4,       -- minutes
    @freq_subday_interval = 15,
    @active_start_time   = 0,       -- midnight
    @active_end_time     = 235959;  -- end of day

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'DBA - Wait Stats Collector',
    @schedule_name = N'Every 15 Minutes';

EXEC msdb.dbo.sp_add_jobserver
    @job_name = N'DBA - Wait Stats Collector';
GO
```

**Permissions required** for the SQL Agent service account (or proxy account):
- `VIEW SERVER STATE` — to read `sys.dm_os_wait_stats` and `sys.dm_os_sys_info`
- Write access to the `output-files\collectors\wait-stats\` folder on the server

## Relationship to other collectors

Wait stats is the foundation. Other collectors that build on the same pattern:

| Collector | Pairs with wait stats to answer... |
|-----------|-----------------------------------|
| Blocking | Are high `LCK_M_*` waits caused by specific blocking chains? |
| TempDB | Are `PAGELATCH_*` waits caused by TempDB contention? |
| Perfmon | Are `PAGEIOLATCH_*` waits correlated with disk saturation? |
| Storage/IO | Same — which databases drive the I/O? |
| AG Health | Are `HADR_*` waits related to replica lag? |
