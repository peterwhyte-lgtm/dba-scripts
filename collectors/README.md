# Collectors

Scheduled data collection scripts that build historical records for trend analysis and
post-incident investigation. Each collector appends timestamped snapshots to daily CSV files.

## Collector types

| Collector | Source | Interval | Write condition | Delta needed? |
|-----------|--------|----------|----------------|--------------|
| `wait-stats` | `sys.dm_os_wait_stats` | 15 min | Always | Yes — cumulative |
| `blocking` | `sys.dm_exec_requests` | 1–5 min | Blocking only | No — point-in-time |
| `deadlocks` | `system_health` XEvent | 1–5 min | New events only | No — event log |
| `tempdb` | `sys.dm_db_file_space_usage` | 5–15 min | Always | No — point-in-time |
| `perfmon` | `sys.dm_os_performance_counters` | 1–5 min | Always | Rate counters only |
| `ag-health` | `sys.dm_hadr_*` | 1–5 min | AG present only | No — point-in-time |
| `storage-io` | `sys.dm_io_virtual_file_stats` | 15–30 min | Always | Yes — cumulative |
| `database-growth` | `sys.master_files` | 1–6 hr | Always | No — point-in-time |

## Output structure

```text
output-files/
  collectors/
    wait-stats/         <server>-<YYYYMMDD>.csv + <server>-collector.log
    blocking/           (empty on quiet servers — only writes during blocking events)
    deadlocks/          (only writes when new deadlocks are detected)
    tempdb/
    perfmon/
    ag-health/          (empty on standalone instances — skips NO_AG rows)
    storage-io/
    database-growth/
```

## Running manually

```powershell
# Point at a server for the session
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# Run any collector
.\collectors\wait-stats\Collect-WaitStats.ps1
.\collectors\blocking\Collect-Blocking.ps1
.\collectors\deadlocks\Collect-Deadlocks.ps1
.\collectors\tempdb\Collect-TempDb.ps1
.\collectors\perfmon\Collect-Perfmon.ps1
.\collectors\ag-health\Collect-AgHealth.ps1
.\collectors\storage-io\Collect-StorageIo.ps1
.\collectors\database-growth\Collect-DatabaseGrowth.ps1
```

## Delta calculation (cumulative collectors)

`wait-stats`, `storage-io`, and `perfmon` rate counters are **cumulative since SQL Server start**.
Calculate deltas between adjacent snapshots:

```text
delta_value = snapshot2.value - snapshot1.value
```

**Restart detection:** Each cumulative collector captures `sqlserver_start_time`. If it
differs between two snapshots, the counters reset — discard that delta.

## SQL Agent job setup

See the README in each collector folder for the exact T-SQL to create the job.
All jobs follow the same pattern:

- **Job category:** `DBA Collectors` (create once, shared across all jobs)
- **Step type:** `CmdExec` — runs `pwsh` directly, avoiding the 32-bit PS Agent environment
- **On failure:** notify operator or write to Windows Application Event Log

## Correlating collectors

```text
PAGEIOLATCH_SH spike in wait-stats
  → storage-io: which database file is driving the reads?
  → perfmon: is PLE dropping at the same time? (memory pressure pushing reads to disk)

LCK_M_X spike in wait-stats
  → blocking: who is the head blocker?
  → deadlocks: are any blocking chains terminating as deadlocks?

PAGELATCH_* spike in wait-stats
  → tempdb: is this TempDB allocation contention?
  → tempdb: check version_store_mb — long-running transactions driving version store growth?

HADR_SYNC_COMMIT spike in wait-stats
  → ag-health: check redo_queue_kb and log_send_queue_kb on secondary replicas
```
