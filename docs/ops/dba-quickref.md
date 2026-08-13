# DBA Runbook

## Quick triage commands

```powershell
# Full healthcheck — collect 45 scripts, review findings
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance . -Quiet
.\powershell\reporting\Review-HealthCheckOutput.ps1

# Live triage — what is happening right now
.\run.ps1 Get-ActiveSessions
.\run.ps1 Get-BlockingSummary
.\run.ps1 Get-LongRunningQueries

# Preflight
.\tools\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .
.\run.ps1 -List
```

---

## Daily checks

Run once per shift / once per day:

1. **Healthcheck collection** — `.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -Quiet`
2. **Review findings** — `.\powershell\reporting\Review-HealthCheckOutput.ps1`
3. **Check thresholds in the review output:**

| Severity | Rule | Action |
|----------|------|--------|
| CRITICAL | Suspect pages recorded | Run DBCC CHECKDB immediately on affected database |
| CRITICAL | SA login enabled | Disable or rename SA |
| CRITICAL | Database not ONLINE | Investigate `state_desc` — suspect, emergency, restoring |
| CRITICAL | No full backup ever | Take an immediate full backup; check backup job |
| WARNING  | Full backup > 25h old | Investigate backup job failures |
| WARNING  | Log backup > 4h (FULL recovery) | Check log backup schedule |
| WARNING  | DBCC CHECKDB > 7 days | Schedule CHECKDB run |
| WARNING  | Log > 80% used | Check log backup frequency |
| WARNING  | Max server memory unconfigured | Set `max server memory` (MB) appropriately |

---

## Weekly checks

```powershell
# Index fragmentation — per database (run against each user DB)
.\run.ps1 Get-IndexFragmentation -Database YourDatabase -OutputFormat Csv

# Cross-database fragmentation — run off-peak
.\run.ps1 Get-IndexFragmentationAcrossDatabases -OutputFormat Csv

# Missing indexes — review top results by impact_score
.\run.ps1 Get-MissingIndexes -OutputFormat Csv

# Slow queries from plan cache
.\run.ps1 Get-SlowQueriesFromCache -OutputFormat Csv

# Job schedule review
.\run.ps1 Get-JobScheduleSummary
```

Fragmentation thresholds (`recommended_action` column): `REBUILD` >= 30%, `REORGANIZE` 10–29%. Indexes < 1000 pages are excluded.

---

## Incident triage

### High CPU

```powershell
.\run.ps1 Get-WaitStatistics          # look for signal_wait_time_ms (CPU queue)
.\run.ps1 Get-TopCpuQueries -OutputFormat Csv
.\run.ps1 Get-LongRunningQueries
.\run.ps1 Get-SlowQueriesFromCache -OutputFormat Csv
```

### Blocking

```powershell
.\run.ps1 Get-BlockingSummary         # head blockers + affected session counts
.\run.ps1 Get-BlockingSessions        # full chain — who is blocked by whom
.\run.ps1 Get-ActiveSessions -OutputFormat Csv
.\run.ps1 Get-DeadlockSummary         # recent deadlocks from system_health ring buffer
```

### I/O pressure

```powershell
.\run.ps1 Get-WaitStatistics          # look for PAGEIOLATCH_SH / PAGEIOLATCH_EX
.\run.ps1 Get-DatabaseIoUsage         # read/write latency per database
.\run.ps1 Get-TopIoQueries -OutputFormat Csv
```

Latency concern thresholds: > 20ms read or > 10ms write on data files.

### TempDB pressure

```powershell
.\run.ps1 Get-TempdbUsage             # file sizes and free space per file
.\run.ps1 Get-TempdbHotspots          # sessions consuming TempDB right now
```

### Memory pressure

```powershell
.\run.ps1 Get-MemoryConfigurationAndUsage
.\run.ps1 Get-WaitStatistics          # look for RESOURCE_SEMAPHORE (memory grant waits)
```

### Backup / restore incident

```powershell
.\run.ps1 Get-BackupCoverage          # backup_status flag per database
.\run.ps1 Get-LastDatabaseBackupTimes
.\run.ps1 Get-SqlAgentJobFailureSummary
.\run.ps1 Get-BackupRestoreCompletionTime   # live progress on active backup/restore
.\run.ps1 Get-DatabaseBackupHistory -OutputFormat Csv
```

### Integrity concern

```powershell
.\run.ps1 Get-SuspectPages            # any entries = CRITICAL — run CHECKDB immediately
.\run.ps1 Get-LastDbccCheckdb         # last successful CHECKDB per database
.\run.ps1 Get-DatabaseIntegrityChecks # pre-CHECKDB readiness review
```

---

## Post-incident investigation with collectors

The collectors build timestamped historical records. Use them when a problem has already resolved and you need to understand what happened.

### "Blocking occurred at 3am — investigate"

```powershell
# Open the blocking collector CSV for that date
# output-files\collectors\blocking\<server>-<YYYYMMDD>.csv
$blocking = Import-Csv "output-files\collectors\blocking\PROD01-20260603.csv"

# Find the worst blocking events
$blocking | Sort-Object wait_time_ms -Descending | Select-Object -First 20 |
    Format-Table collection_time, blocked_spid, blocking_spid, is_head_blocker,
                   wait_type, wait_time_ms, login_name, blocked_statement -AutoSize

# Identify the head blockers
$blocking | Where-Object { $_.is_head_blocker -eq '1' } |
    Group-Object blocking_spid, login_name | Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize
```

### "Wait stats spiked last Tuesday — what was it?"

```powershell
# Wait-stats snapshots are cumulative — diff two adjacent ones to get interval waits
$snap = Import-Csv "output-files\collectors\wait-stats\PROD01-20260527.csv"

# Get two adjacent snapshots
$times = $snap.collection_time | Sort-Object | Get-Unique
$snap1 = $snap | Where-Object { $_.collection_time -eq $times[6] }  # 08:30
$snap2 = $snap | Where-Object { $_.collection_time -eq $times[7] }  # 08:45

# Delta for the 15-minute interval
$t1 = $snap1 | Group-Object wait_type -AsHashTable
$snap2 | ForEach-Object {
    $prev = $t1[$_.wait_type]
    if ($prev -and $_.sqlserver_start_time -eq $prev.sqlserver_start_time) {
        [PSCustomObject]@{
            wait_type       = $_.wait_type
            delta_wait_ms   = [long]$_.wait_time_ms - [long]$prev.wait_time_ms
            delta_tasks     = [long]$_.waiting_tasks_count - [long]$prev.waiting_tasks_count
        }
    }
} | Where-Object { $_.delta_wait_ms -gt 0 } |
    Sort-Object delta_wait_ms -Descending | Select-Object -First 10 |
    Format-Table wait_type, delta_wait_ms, delta_tasks -AutoSize

# NOTE: if sqlserver_start_time differs between snap1 and snap2, SQL Server restarted
# between those snapshots — discard the delta for that interval.
```

### "I/O latency was high overnight — which files?"

```powershell
$io = Import-Csv "output-files\collectors\storage-io\PROD01-20260603.csv"
$times = $io.collection_time | Sort-Object | Get-Unique

$snap1 = $io | Where-Object { $_.collection_time -eq $times[0] }
$snap2 = $io | Where-Object { $_.collection_time -eq $times[1] }

$t1 = $snap1 | Group-Object database_name, file_id -AsHashTable
$snap2 | ForEach-Object {
    $key  = "$($_.database_name) $($_.file_id)"
    $prev = $t1[$key]
    if ($prev -and $_.sqlserver_start_time -eq $prev.sqlserver_start_time) {
        $dr = [long]$_.num_of_reads  - [long]$prev.num_of_reads
        $rs = [long]$_.io_stall_read_ms - [long]$prev.io_stall_read_ms
        [PSCustomObject]@{
            database_name    = $_.database_name
            file_type        = $_.file_type
            interval_reads   = $dr
            interval_read_stall_ms = $rs
            avg_read_ms      = if ($dr -gt 0) { [Math]::Round($rs / $dr, 1) } else { 0 }
        }
    }
} | Where-Object { $_.avg_read_ms -gt 5 } |
    Sort-Object avg_read_ms -Descending |
    Format-Table database_name, file_type, interval_reads, avg_read_ms -AutoSize
```

### Correlating collectors

```text
LCK_M_* spike in wait-stats delta
  → blocking: head blocker login, blocked_statement, time of peak wait_time_ms

PAGEIOLATCH_* spike in wait-stats delta
  → storage-io: which database file had the highest interval read stall?
  → perfmon: was PLE dropping at the same time? (cntr_value for 'Page life expectancy')

PAGELATCH_* spike in wait-stats delta
  → tempdb: version_store_mb growing? large user_objects_mb?
  → tempdb: session row — which login is the top consumer?

HADR_SYNC_COMMIT spike in wait-stats delta
  → ag-health: redo_queue_kb and log_send_queue_kb on secondary at that time
```

---

## Multi-server estate checks

```powershell
# Check backup coverage across all SQL instances
.\powershell\reporting\multi-server\MultiServer-GetBackupStatus.ps1 -Servers "SVR01,SVR02,SVR03" -Parallel

# Check for active blocking across all instances right now
.\powershell\reporting\multi-server\MultiServer-GetBlockingSessions.ps1 -Servers "SVR01,SVR02,SVR03"

# Disk space across all Windows servers
.\powershell\reporting\multi-server\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02,SVR03" -WarnBelowPctFree 15

# Test SQL port reachability across estate
.\powershell\reporting\multi-server\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03,SVR04,SVR05" -Parallel

# Generate a custom multi-server wrapper for any SQL script
.\tools\scaffolding\New-MultiServerScript.ps1 `
    -ScriptPath sql\performance\Get-WaitStatistics.sql `
    -Servers "SVR01,SVR02,SVR03" `
    -OutputFile C:\Temp\run-waits.ps1
# Review the generated script, then: pwsh -File C:\Temp\run-waits.ps1
```

---

## Common maintenance procedures

### Rebuild / reorganize fragmented indexes

```powershell
# Identify — run against each user database
.\run.ps1 Get-IndexFragmentation -Database YourDatabase -OutputFormat Csv

# Generate maintenance script
.\run.ps1 Generate-IndexMaintenanceScript -Database YourDatabase -OutputFormat Csv
# Review output-files\...\Generate-IndexMaintenanceScript-*.csv, then run in SSMS
```

### Update statistics

```powershell
# Find stale statistics
.\run.ps1 Get-StatisticsHealth -Database YourDatabase -OutputFormat Csv
# Output includes UPDATE STATISTICS commands — copy from CSV and run in SSMS
```

### Shrink transaction log (last resort)

```powershell
# Check log usage first
.\run.ps1 Get-TransactionLogSizeAndUsage -OutputFormat Csv
```

Then in SSMS:
```sql
-- 1. Take a log backup first (FULL/BULK_LOGGED recovery models)
BACKUP LOG [YourDatabase] TO DISK = N'NUL';

-- 2. Shrink to reclaim VLFs (not the file itself — just the unused space)
USE [YourDatabase];
DBCC SHRINKFILE (YourDatabase_log, 1);

-- 3. Check VLF count after
SELECT COUNT(*) AS vlf_count FROM sys.dm_db_log_info(DB_ID('YourDatabase'));
-- > 1000 VLFs = consider log backup cycle review; > 10000 = serious
```

**Never use AUTO_SHRINK. Never shrink data files unless disk is critically low.**

### Clear output files before a fresh assessment run

```powershell
.\tools\maintenance\Clear-OutputFiles.ps1
```

---

## Security review

```powershell
.\run.ps1 Get-SysadminMembers       -OutputFormat Csv
.\run.ps1 Get-ServerRoleMembers     -OutputFormat Csv
.\run.ps1 Get-DatabaseRoleMembers   -OutputFormat Csv
.\run.ps1 Get-OrphanedUsers         -OutputFormat Csv
.\run.ps1 Get-LoginPermissions      -OutputFormat Csv
.\run.ps1 Get-WeakLoginSettings     -OutputFormat Csv
.\run.ps1 Get-DatabaseMailAndXpCmdShell
```

---

## Pre-migration inventory

```powershell
.\run.ps1 Get-DatabaseInventory        -OutputFormat Csv
.\run.ps1 Get-LoginInventory           -OutputFormat Csv
.\run.ps1 Get-JobInventory             -OutputFormat Csv
.\run.ps1 Get-LinkedServerInventory    -OutputFormat Csv
.\run.ps1 Get-MigrationRiskAssessment
.\run.ps1 Get-LinkedServerAndJobInventory -OutputFormat Csv
```

---

## Output files

| Location | What goes there |
|----------|----------------|
| `output-files\healthcheck\<server>-<timestamp>\` | Named CSVs from `Invoke-HealthCheckCollection.ps1` |
| `output-files\reviews\<category>\<script>-<timestamp>.csv` | Individual script runs via `Invoke-RepoSql.ps1` |
| `output-files\collectors\<type>\<server>-<YYYYMMDD>.csv` | Scheduled collector snapshots |
| `output-files\assessment\<server>-<timestamp>.md` | Assessment reports |
| `output-files\migration\*.sql` | Generated DDL scripts (logins, jobs, user mappings) |

Clear all generated output: `.\tools\maintenance\Clear-OutputFiles.ps1`
