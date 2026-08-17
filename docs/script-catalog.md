# Script catalog

Every SQL script and every PowerShell script with real logic in this repo, grouped by the folder it
actually lives in. Descriptions are the `Purpose` line from each script's own header, so this list and
the scripts cannot drift apart.

- **Post** links to the companion write-up on sqldba.blog where one exists. A blank Post column means
  the script works exactly the same, it just has not been written up yet.
- **Writes** marks the scripts that are not read-only: `CreatesObjects` creates jobs, tables, or XE
  sessions; `WritesData` changes data. Everything unmarked is read-only and safe to run in production.
- **HC** marks the 45 scripts collected by `Invoke-HealthCheckCollection.ps1`.

Every SQL script here is single-result-set and paste-and-run in SSMS. To run one from the terminal
instead, use `.\run.ps1 <ScriptName>` — see [quick-start.md](quick-start.md).

---

## SQL scripts

### Inventory — `sql/inventory/`

What is on this instance: version, OS, databases, services, logins, jobs, linked servers.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-DatabaseInventory` | Inventory user databases for migration readiness — compatibility level, recovery model, state. | [post](https://sqldba.blog/dba-scripts-get-database-inventory/) |  |  |
| `Get-DatabaseSnapshotInventory` | Lists all database snapshots with source database, age, and allocated size — snapshots silently consume filegroup space if forgotten. | [post](https://sqldba.blog/dba-scripts-get-database-snapshot-inventory/) |  |  |
| `Get-DatabaseSummary` | One-row-per-database view of every database on the instance: state, recovery model, log reuse wait, file sizes, backup currency, and configuration flags. Notes column aggregates actionable issues. Reads from system metadata and msdb only — no per-database scan. For used vs free space detail run Get-DatabaseSizesAndFreeSpace. For file-level detail run Get-DatabaseFilesDetail. | [post](https://sqldba.blog/dba-scripts-get-database-summary/) |  |  |
| `Get-Databases` | Lists all databases with key properties and allocated file sizes. Reads from system metadata only — fast, no per-database scan. Data and log sizes reflect allocated file space, not space used. Run Get-DatabaseSizesAndFreeSpace for used vs free breakdown. | [post](https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/) |  |  |
| `Get-JobInventory` | Inventory SQL Agent jobs with owner for migration dependency checks. | [post](https://sqldba.blog/dba-scripts-get-login-and-job-inventory/) |  |  |
| `Get-LinkedServerAndJobInventory` | Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews. | [post](https://sqldba.blog/dba-scripts-get-linked-servers/) |  |  |
| `Get-LinkedServerInventory` | Inventory linked servers for migration and connectivity dependency mapping. | [post](https://sqldba.blog/dba-scripts-get-linked-servers/) |  |  |
| `Get-LoginInventory` | Inventory server logins by type and status for migration and access review. | [post](https://sqldba.blog/dba-scripts-get-login-and-job-inventory/) |  |  |
| `Get-OsAndHardwareInfo` | Show OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row. | [post](https://sqldba.blog/dba-scripts-get-os-and-hardware-info/) |  | yes |
| `Get-PatchLevel` | Reports SQL Server version, Cumulative Update level, edition, and build number for patch-level tracking across an estate. Run on each server to build a patch compliance inventory. | [post](https://sqldba.blog/dba-scripts-get-patch-level/) |  |  |
| `Get-ServicesInformation` | SQL Server services — startup type, running status, and service account with risk flags. Surfaces manual/disabled startup on critical services and high-privilege service accounts (LocalSystem, SYSTEM, NetworkService). |  |  |  |
| `Get-VersionAndEdition` | Display core instance version, edition, cluster status, and patch level. |  |  | yes |

### Monitoring (instance root) — `sql/monitoring/`

Connection and linked-server checks that do not belong to a subfolder.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-ActiveConnectionsByDatabase` | Session count, active requests, open transactions, and blocked sessions grouped by database — essential check before taking any database offline or starting a decommission. | [post](https://sqldba.blog/dba-scripts-get-active-connections-by-database/) |  |  |
| `Get-LinkedServerConnectivity` | Inventories all linked servers and tests each one for connectivity using sp_testlinkedserver. | [post](https://sqldba.blog/dba-scripts-get-linked-servers/) |  |  |

### Monitoring: instance configuration — `sql/monitoring/instance/`

Config score and snapshot, memory, MAXDOP, CPU topology, trace flags, Resource Governor, OS-level checks.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-InstanceConfigurationScore` | Scores the SQL Server instance across ~20 key configuration checks. Returns PASS/WARN/FAIL per item with finding and recommended action. Run this first when taking ownership of a new instance. | [post](https://sqldba.blog/dba-scripts-get-instance-configuration-score/) |  |  |
| `Get-InstanceConfigurationSnapshot` | Capture all sp_configure settings for baseline review and change tracking. |  |  | yes |
| `Get-MaxdopConfiguration` | Show MAXDOP and cost threshold settings alongside current CPU topology. |  |  |  |
| `Get-MemoryConfigurationAndUsage` | Show configured memory limits alongside current SQL Server memory consumption. |  |  | yes |
| `Get-OsConfigurationChecks` | DMV-accessible OS and hardware configuration checks: Lock Pages in Memory, NUMA topology, scheduler affinity, and Instant File Initialization (SQL 2019+). Surfaces common misconfigurations invisible from inside SQL Server. Pair with Test-OsConfiguration.ps1 for power plan and page file checks. | [post](https://sqldba.blog/dba-scripts-get-cpu-topology-and-os-config/) |  |  |
| `Get-ResourceGovernorConfig` | Resource Governor configuration — enabled state, resource pools, workload groups, and classifier function. An active but misconfigured RG can silently throttle queries or starve the DBA's own sessions on an inherited server. | [post](https://sqldba.blog/dba-scripts-get-trace-flags-and-resource-governor/) |  |  |
| `Get-SqlServerCpuTopologyAndSchedulerDetails` | CPU topology, NUMA layout, scheduler summary, and parallelism configuration in one row. | [post](https://sqldba.blog/dba-scripts-get-cpu-topology-and-os-config/) |  |  |
| `Get-TraceFlags` | Active global and session trace flags with descriptions. Reveals undocumented tuning decisions and flags inherited from previous DBAs. | [post](https://sqldba.blog/dba-scripts-get-trace-flags-and-resource-governor/) |  |  |

### Monitoring: database health — `sql/monitoring/databases/`

Health posture, integrity-check readiness, DBCC CHECKDB history, suspect pages.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-DatabaseHealth` | Review the health and sizing posture of user databases. | [post](https://sqldba.blog/dba-scripts-get-database-health/) |  | yes |
| `Get-DatabaseIntegrityChecks` | Pre-check database readiness and configuration for integrity validation runs. | [post](https://sqldba.blog/dba-scripts-get-suspect-pages-and-integrity-checks/) |  |  |
| `Get-LastDbccCheckdb` | Show when each user database last had a successful DBCC CHECKDB run. |  |  | yes |
| `Get-SuspectPages` | Show any pages recorded in msdb.dbo.suspect_pages — evidence of I/O or corruption errors. | [post](https://sqldba.blog/dba-scripts-get-suspect-pages-and-integrity-checks/) |  | yes |

### Monitoring: space and growth — `sql/monitoring/disk-space/`

Database and file sizing, free space, filegroups, volumes, transaction log, VLFs, autogrowth history and forecast.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-AutogrowthHistory` | Reads autogrowth events from the SQL Server default trace. Autogrowth events during business hours indicate undersized files; frequent events indicate the growth increment is too small. Use this to right-size initial file sizes and growth increments. |  |  | yes |
| `Get-DatabaseFilesDetail` | Show per-file details for all user databases: path, size, max size, growth settings. | [post](https://sqldba.blog/dba-scripts-get-sql-server-database-file-details/) |  | yes |
| `Get-DatabaseFreeSpaceSummary` | Allocated, used, and free space for all online databases, ordered by total free space descending. | [post](https://sqldba.blog/dba-scripts-get-database-free-space-summary/) |  |  |
| `Get-DatabaseGrowthEvents` | Show recent autogrowth events from the default trace for capacity planning. |  |  |  |
| `Get-DatabaseGrowthForecast` | Project when database files will exhaust their configured size limits, using historical file size changes recorded by the DatabaseGrowth temporal collector. Calculates MB/day growth rate from the first and last observed size within the window, then projects forward to the configured file limit. | [post](https://sqldba.blog/dba-scripts-get-database-growth-risk-and-forecast/) |  |  |
| `Get-DatabaseGrowthRisk` | Flag databases approaching their configured file size limits. | [post](https://sqldba.blog/dba-scripts-get-database-growth-risk-and-forecast/) |  | yes |
| `Get-DatabaseSizesAndFreeSpace` | Data and log file sizes with used and free space for all online user databases. Uses dynamic SQL so FILEPROPERTY runs inside each database's own context, where it correctly reports allocated vs used pages. The original CTE approach querying sys.master_files from master caused FILEPROPERTY to return NULL for other databases' files. | [post](https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/) |  | yes |
| `Get-DiskSpace` | Show free and used space per volume that hosts SQL Server database files. | [post](https://sqldba.blog/script-check-disk-space-on-sql-server/) |  | yes |
| `Get-FilegroupSpace` | Allocated, used, and free space per filegroup across all online databases — ordered by lowest free percentage first. | [post](https://sqldba.blog/dba-scripts-get-filegroup-space/) |  |  |
| `Get-LogReuseWaits` | Reports why each database's transaction log cannot truncate and reuse space — the log_reuse_wait_desc reason per database, with recovery model, log size, and last log backup for context. This is the first question to answer when a log file is full or growing and won't shrink. | [post](https://sqldba.blog/dba-scripts-get-log-reuse-waits/) |  |  |
| `Get-TransactionLogSizeAndUsage` | Show transaction log size, used space, free space, and percent used per database. | [post](https://sqldba.blog/dba-scripts-get-transaction-log-size-and-usage/) |  | yes |
| `Get-VlfCount` | Reports virtual log file (VLF) count per database transaction log, ranked by severity. High VLF counts degrade recovery time, log backup performance, and redo during AG synchronisation. Often caused by many small autogrowth events accumulating over time. | [post](https://sqldba.blog/dba-scripts-get-vlf-counts/) |  | yes |

### Monitoring: TempDB — `sql/monitoring/tempdb/`

TempDB configuration, file balance, usage, and live hotspots.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-TempDbConfiguration` | Reviews TempDB file configuration — file count, sizing parity, autogrowth settings, and max server memory context. Surfaces common misconfigurations that cause allocation contention on busy OLTP servers. | [post](https://sqldba.blog/dba-scripts-get-temp-db-configuration/) |  | yes |
| `Get-TempDbFileBalance` | TempDB data file configuration — checks for size imbalance, growth mismatches, percent-based growth, and file count vs CPU count. | [post](https://sqldba.blog/dba-scripts-get-temp-db-usage-and-file-balance/) |  |  |
| `Get-TempdbHotspots` | Identify sessions consuming the most TempDB space for contention and spill triage. | [post](https://sqldba.blog/dba-scripts-get-temp-db-hotspots/) |  |  |
| `Get-TempdbUsage` | Show TempDB file sizes, free space, and allocation breakdown per file. | [post](https://sqldba.blog/dba-scripts-get-temp-db-usage-and-file-balance/) |  | yes |

### Monitoring: SQL Agent — `sql/monitoring/jobs/`

Job overview, failures, schedules, duration trends, alerts and operators.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-AgentAlertsAndOperators` | SQL Agent alerts and operators with severity gap analysis. Surfaces instances with no alerts for severity 19-25 (critical errors go unnoticed without these). | [post](https://sqldba.blog/dba-scripts-get-agent-alerts-and-operators/) |  |  |
| `Get-JobDurationTrends` | SQL Agent job duration over the last 30 days — flags jobs that are running significantly longer than their average. | [post](https://sqldba.blog/dba-scripts-get-job-schedules-and-duration-trends/) |  |  |
| `Get-JobScheduleSummary` | Show enabled SQL Agent jobs with their schedules and next scheduled run time. | [post](https://sqldba.blog/dba-scripts-get-job-schedules-and-duration-trends/) |  |  |
| `Get-SqlAgentJobFailureSummary` | Show SQL Agent job failures from the last 7 days with readable timestamps and error messages. | [post](https://sqldba.blog/dba-scripts-get-sql-agent-job-failure-summary/) |  | yes |
| `Get-SqlAgentJobOverview` | Show all SQL Agent jobs with enabled state, owner, and last run outcome. |  |  | yes |

### Monitoring: error log — `sql/monitoring/error-log/`

Recent entries, categorised patterns, and schema-change history from the default trace.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-ErrorLogPatterns` | Reads the current SQL Server error log and groups entries by category — surfaces memory pressure, login failures, IO issues, corruption warnings, and auto-growth events without scrolling through raw entries. | [post](https://sqldba.blog/dba-scripts-get-error-log-patterns/) |  |  |
| `Get-RecentErrorLogEntries` | Show SQL Server error log entries from the last 24 hours, filtering routine noise. | [post](https://sqldba.blog/dba-scripts-get-recent-error-log-entries/) |  | yes |
| `Get-SchemaChangeHistory` | Recent DDL changes (CREATE, ALTER, DROP) captured by the SQL Server default trace — answers "what changed on this server recently?" after an incident or unexpected behaviour. Requires the default trace to be enabled (on by default). Covers the rolling window kept by the trace files. | [post](https://sqldba.blog/dba-scripts-get-schema-change-history/) |  |  |

### Monitoring: features — `sql/monitoring/features/`

CDC and Change Tracking, Query Store, Extended Events, Service Broker, Database Mail, compression, collation and cross-database dependencies.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-CdcAndChangeTracking` | CDC (Change Data Capture) and Change Tracking enabled databases with retention, cleanup settings, and latency indicators. Both features impact transaction log growth and can stall if cleanup jobs are absent or delayed. | [post](https://sqldba.blog/dba-scripts-get-cdc-and-change-tracking/) |  | yes |
| `Get-CollationConflicts` | Databases whose collation differs from the server collation — a common source of implicit conversion errors and failed JOIN operations. | [post](https://sqldba.blog/dba-scripts-get-collation-conflicts-and-cross-database-dependencies/) |  |  |
| `Get-CompressionCandidates` | Largest uncompressed tables and heaps in the current database, ordered by reserved space — identifies the best candidates for row or page compression. | [post](https://sqldba.blog/dba-scripts-get-compression-candidates/) |  |  |
| `Get-CrossDatabaseDependencies` | Objects in the current database that reference other databases via 3-part names or linked servers — critical to find before a migration, rename, or decommission. Note: only captures statically-resolvable references. Dynamic SQL built at runtime will not appear here. | [post](https://sqldba.blog/dba-scripts-get-collation-conflicts-and-cross-database-dependencies/) |  |  |
| `Get-DatabaseMailQueue` | Database Mail items that are failed, retrying, or unsent — plus last 24 hours of sent mail for context. Shows error detail for failed items. | [post](https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/) |  |  |
| `Get-ExtendedEventsSessions` | Active Extended Events sessions — name, state, targets, and estimated disk impact. Surfaces unexpected or high-overhead XE sessions on inherited servers. | [post](https://sqldba.blog/dba-scripts-get-extended-events-sessions/) |  | yes |
| `Get-QueryStoreStatus` | Query Store enablement, fill ratio, capture mode, and health across all user databases. Surfaces databases where QS is off, full, or auto-switched to READ_ONLY. | [post](https://sqldba.blog/dba-scripts-get-query-store-status/) |  | yes |
| `Get-ServiceBrokerHealth` | Service Broker health across all user databases. Orphaned/disconnected conversation endpoints accumulate silently over months, eventually degrading SB infrastructure. SB is implicitly active on many instances (Database Mail, AG health checks use it). Surfaces conversation endpoint counts by state, transmission queue depth, and queue activation status. | [post](https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/) |  | yes |

### Performance (root) — `sql/performance/`

Wait statistics, database I/O, table sizes, and live backup/restore progress.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-BackupRestoreProgress` | Show active backup/restore progress and estimated completion for long-running operations. | [post](https://sqldba.blog/dba-scripts-get-backup-restore-progress/) |  |  |
| `Get-DatabaseIoUsage` | Database I/O totals with percentage share, MB read/written, and latency breakdown. |  |  | yes |
| `Get-TableSizes` | Largest tables across all online user databases by total size (data + index). Essential for getting to know a new instance — identifies the major data consumers and tables most likely to impact I/O, backup times, and index maintenance windows. | [post](https://sqldba.blog/dba-scripts-get-table-sizes/) |  |  |
| `Get-WaitStatistics` | Top wait types since last SQL Server restart, filtered to actionable waits only. | [post](https://sqldba.blog/sql-server-wait-statistics/) |  | yes |

### Performance: active sessions — `sql/performance/active-sessions/`

What is running right now, with or without execution plans.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-ActiveRequests` | Point-in-time snapshot of all active requests — sessions with a request currently in flight. Returns wait type, blocking chain, CPU, reads, writes, elapsed time, TempDB consumption, and the current executing statement. Excludes idle sessions and the diagnostic session itself. | [post](https://sqldba.blog/dba-scripts-get-active-sessions-and-requests/) |  |  |
| `Get-ActiveRequestsWithPlan` | Point-in-time snapshot of all active requests with XML execution plans. Same columns as Get-ActiveRequests.sql with the addition of query_plan from sys.dm_exec_query_plan. Use the PowerShell wrapper to extract plans to individual XML files for SSMS analysis. | [post](https://sqldba.blog/dba-scripts-get-active-sessions-and-requests/) |  |  |
| `Get-ActiveSessions` | Show all active user sessions with current wait type, blocking, elapsed time, and statement. | [post](https://sqldba.blog/dba-scripts-get-active-sessions-and-requests/) |  | yes |
| `Get-LongRunningQueries` | Active requests with elapsed and wait details — ordered by elapsed time descending. |  |  |  |
| `Get-WorkerThreadsAndActiveSessions` | Active user sessions with CPU, elapsed time, and current worker thread pool usage. |  |  |  |

### Performance: blocking and locking — `sql/performance/blocking-locking/`

Blocking chains and summaries, open transactions, lock escalation, deadlocks, contention.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-BlockingChains` | Traces all active blocking chains using a recursive CTE. Returns every session involved in blocking — head blockers, mid-chain nodes, and leaf victims — ordered so each chain reads depth-first. Idle head blockers (sleeping but holding locks) are included; their last executed statement is recovered via sys.dm_exec_connections. Returns no rows when the server is not blocked. | [post](https://sqldba.blog/dba-scripts-get-blocking-chains/) |  |  |
| `Get-BlockingChainsWithPlan` | Same as Get-BlockingChains.sql with the addition of query_plan for every session that has a cached plan. Use the PowerShell wrapper to extract plans to individual XML files. Plan will be NULL for idle head blockers (no active request) and sessions still in parse/compile. | [post](https://sqldba.blog/dba-scripts-get-lock-contention-and-blocking-plans/) |  |  |
| `Get-BlockingSessions` | Show sessions involved in blocking chains with wait type, timing, and current statement. | [post](https://sqldba.blog/dba-scripts-get-blocking-sessions/) |  |  |
| `Get-BlockingSummary` | Head blockers with context — who is blocking, how many sessions, and what they are running. | [post](https://sqldba.blog/dba-scripts-get-blocking-sessions/) |  |  |
| `Get-ContentionAnalysis` | Unified contention summary across lock waits, latch waits, TempDB allocation pressure, and spinlock contention. All figures are cumulative since the last SQL Server restart — high counts on a recently restarted instance are not necessarily concerning. | [post](https://sqldba.blog/dba-scripts-get-lock-contention-and-blocking-plans/) |  |  |
| `Get-DeadlockSummary` | Show recent deadlock events from the system_health XEvent ring buffer. | [post](https://sqldba.blog/dba-scripts-get-deadlock-summary/) |  |  |
| `Get-LockEscalationStats` | Shows tables with the most lock escalations since last restart. Lock escalation converts row/page locks to a table lock, increasing blocking. | [post](https://sqldba.blog/dba-scripts-get-lock-contention-and-blocking-plans/) |  |  |
| `Get-OpenTransactions` | Active transactions with age, session details, and the SQL currently running or last executed — long-running open transactions cause log growth and block readers in READ_COMMITTED isolation. | [post](https://sqldba.blog/dba-scripts-get-open-transactions/) |  |  |

### Performance: indexes — `sql/performance/indexes/`

Missing, unused, duplicate, and fragmented indexes; heaps and index design problems.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-DuplicateIndexes` | Exact duplicate and overlapping (prefix) indexes across all user databases. Duplicates waste storage and double/triple write overhead for every DML operation. Overlapping indexes (A's key columns are a left-prefix of B's) usually mean B makes A redundant. Combines with usage stats to flag duplicates that are also unused — the highest priority to remove. | [post](https://sqldba.blog/dba-scripts-get-duplicate-indexes/) |  |  |
| `Get-Heaps` | Lists tables with no clustered index (heaps) across all online user databases. Heaps cause full table scans on every non-covering lookup, accumulate forwarded records after row updates (degrading IO), and do not reclaim deleted row space without a REBUILD. Common source of hidden IO pressure that grows silently as data volumes increase. | [post](https://sqldba.blog/dba-scripts-get-heaps/) |  |  |
| `Get-IndexDesignIssues` | Tables with index design problems: excessive index count (write amplification), wide key columns (>900 bytes — approaching the 1700-byte nonclustered key limit), and tables where Missing Index DMV has > 3 recommendations (optimizer giving up on existing index coverage). Complements Get-DuplicateIndexes. | [post](https://sqldba.blog/dba-scripts-get-index-design-issues/) |  |  |
| `Get-IndexFragmentation` | Top fragmented indexes across all user databases, ranked by fragmentation pct. |  |  |  |
| `Get-IndexFragmentationAcrossDatabases` | Check index fragmentation details across all user databases for maintenance planning. |  |  |  |
| `Get-IndexUsageStats` | Show how indexes across all user databases are being used — seeks, scans, lookups, updates. | [post](https://sqldba.blog/dba-scripts-get-index-usage-stats/) |  |  |
| `Get-MissingIndexes` | Missing index candidates from DMVs, ranked by impact score (seeks x cost x impact). |  |  | yes |
| `Get-UnusedIndexes` | Identifies non-clustered indexes with zero read activity but non-zero write overhead since the last SQL Server restart. These indexes slow every INSERT, UPDATE, and DELETE on the table without benefiting any query. Run in the context of the database you want to audit. | [post](https://sqldba.blog/dba-scripts-get-unused-indexes/) |  |  |

### Performance: queries — `sql/performance/queries/`

Top CPU and I/O queries, slow queries, plan cache health, implicit conversions, memory grant spills, statistics health.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-ImplicitConversions` | Scans the plan cache for implicit conversion warnings. These cause index range scans instead of seeks and generate unnecessary CPU. Most common cause: VARCHAR column compared to NVARCHAR parameter, or INT column compared to VARCHAR. NOTE: scans plan XML — runs for 10–30 seconds on busy servers with large plan caches. | [post](https://sqldba.blog/dba-scripts-get-implicit-conversions/) |  |  |
| `Get-MemoryGrantSpills` | Top queries by memory grant spills to TempDB. Spills occur when SQL grants less memory than a sort or hash join operator needs, forcing intermediate results to disk. Invisible in wait stats — shows as TempDB I/O pressure or RESOURCE_SEMAPHORE waits. Requires SQL Server 2016+ (total_spills column). | [post](https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/) |  |  |
| `Get-PlanCacheHealth` | Summarises plan cache composition by object type — highlights single-use plan bloat, ad-hoc SQL pressure, and total memory consumption. High single-use percentages indicate parameter sniffing or missing parameterisation. | [post](https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/) |  | yes |
| `Get-QueryVariance` | Queries from the plan cache where max execution time is at least 5x the minimum — the primary signal for parameter sniffing and plan instability. High execution count with high variance means the same query performs very differently depending on the parameter values in the cached plan. | [post](https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/) |  |  |
| `Get-SlowQueriesFromCache` | Top 20 queries by average elapsed time from the plan cache — identifies habitually slow queries. | [post](https://sqldba.blog/dba-scripts-get-top-cpu-queries/) |  |  |
| `Get-StatisticsHealth` | Identifies stale, low-sample, and never-updated statistics in the current database. Returns the UPDATE STATISTICS command per row for direct copy-paste remediation. Run in the context of the target user database. | [post](https://sqldba.blog/dba-scripts-get-statistics-health/) |  |  |
| `Get-StoredProcedurePerformance` | Stored procedures from the plan cache ranked by total elapsed time — shows execution count, average and max duration, CPU, and logical reads. Resets on SQL Server restart or plan eviction. | [post](https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/) |  |  |
| `Get-TopCpuQueries` | List top 20 CPU-consuming queries with execution counts and timing metrics. | [post](https://sqldba.blog/dba-scripts-get-top-cpu-queries/) |  | yes |
| `Get-TopIoQueries` | Top 20 queries by total logical reads since last restart — primary I/O pressure source. | [post](https://sqldba.blog/dba-scripts-get-top-cpu-queries/) |  |  |

### Performance: Query Store — `sql/performance/query-store/`

Top queries, regressions, and forced plans from Query Store.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-QueryStoreForcedPlans` | Forced plans in Query Store with failure counts, plan age, forcing reason, and whether the forced plan is still the cheapest available option. A force_failure_count > 0 means QS is silently reverting to natural plans — queries you think are protected are not. Run in the context of the target database (-Database <dbname>). | [post](https://sqldba.blog/dba-scripts-get-query-store-regressions-and-forced-plans/) |  |  |
| `Get-QueryStoreRegressions` | Queries that regressed in the last 24 hours vs their 7-day average CPU/duration. Uses Query Store time-bucketed runtime stats to detect "what changed today" — queries running >2x slower or using >2x more CPU than their recent baseline. Run in the context of the target database (-Database <dbname>). | [post](https://sqldba.blog/dba-scripts-get-query-store-regressions-and-forced-plans/) |  |  |
| `Get-QueryStoreTopQueries` | Top queries from Query Store by CPU, duration, execution count, or plan regressions. Change @sort_by at the top to switch modes. Must run in the context of the target database — change the database in SSMS or pass -Database <dbname> via the PS wrapper. | [post](https://sqldba.blog/dba-scripts-get-query-store-top-queries/) |  |  |

### Backups and recovery — `sql/backups/`

Coverage, history, chain integrity, encryption, size trend, restore history, and backup/restore DDL generators.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Generate-DiffBackupScript` | Generate a DIFFERENTIAL backup script for all online user databases. @ts in the generated script resolves at execution time so filenames include the backup timestamp, not the script generation timestamp. | [post](https://sqldba.blog/dba-scripts-generate-backup-and-restore-scripts/) |  |  |
| `Generate-FullBackupScript` | Generate a FULL backup script for all online user databases. @ts in the generated script resolves at execution time so filenames include the backup timestamp, not the script generation timestamp. | [post](https://sqldba.blog/dba-scripts-generate-backup-and-restore-scripts/) |  |  |
| `Generate-RestoreScript` | Generate a RESTORE DATABASE script for all online user databases. Set @ts to the timestamp of the backup files you want to restore before executing. Review WITH MOVE if restoring to a different server. | [post](https://sqldba.blog/dba-scripts-generate-backup-and-restore-scripts/) |  |  |
| `Generate-TLogBackupScript` | Generate a transaction log backup script for all online user databases in FULL or BULK_LOGGED recovery model. SIMPLE recovery databases are excluded — log backups are not supported for them. @ts in the generated script resolves at execution time so filenames include the backup timestamp, not the script generation timestamp. | [post](https://sqldba.blog/dba-scripts-generate-backup-and-restore-scripts/) |  |  |
| `Get-BackupChainIntegrity` | LSN continuity analysis for each user database. Verifies the log backup chain from the most recent full backup to now is unbroken. A gap in the log chain means point-in-time restore is impossible for that window — coverage scripts only check recency, not continuity. Also surfaces damaged backup sets. | [post](https://sqldba.blog/dba-scripts-get-backup-chain-integrity/) |  |  |
| `Get-BackupCoverage` | Review backup coverage per database with a status flag for quick health assessment. | [post](https://sqldba.blog/dba-scripts-get-backup-coverage/) |  | yes |
| `Get-BackupEncryptionStatus` | Shows TDE status and backup encryption coverage per database. Identifies databases where TDE is on but backups are not encrypted, or where neither TDE nor backup encryption is used. | [post](https://sqldba.blog/dba-scripts-get-backup-encryption-status/) |  |  |
| `Get-BackupRestoreCompletionTime` | Monitor active backup and restore operations with estimated completion time. |  |  |  |
| `Get-BackupRestoreDurationEstimate` | Analyze backup duration and throughput metrics from msdb for performance baseline. | [post](https://sqldba.blog/dba-scripts-get-backup-restore-duration-estimate/) |  |  |
| `Get-BackupSizeTrend` | Monthly backup size trend per database over the last 12 months — an indirect proxy for data growth rate. Shrinking backups can indicate unexpected data loss; growing backups inform storage planning. | [post](https://sqldba.blog/dba-scripts-get-backup-size-trend/) |  |  |
| `Get-DatabaseBackupHistory` | Review detailed backup history for all databases over the last 2 months. | [post](https://sqldba.blog/dba-scripts-get-database-backup-history/) |  |  |
| `Get-LastDatabaseBackupTimes` | Display the latest backup timestamp per type (Full, Differential, Log) per database. |  |  | yes |
| `Get-LastRestoreHistory` | Full restore history from msdb — when each database was last restored, from which backup, and by whom. Use to verify DR restore tests have actually been run. | [post](https://sqldba.blog/dba-scripts-get-last-restore-history/) |  |  |
| `Get-RecoveryModelAudit` | Audits each database's recovery model against its actual backup posture and flags the mismatches that cause real incidents: FULL/BULK_LOGGED databases with no log backups (the log grows until the disk fills), databases with no full backup to anchor a log chain, and SIMPLE databases where someone may be expecting point-in-time recovery they do not have. | [post](https://sqldba.blog/dba-scripts-get-recovery-model-audit/) |  |  |

### Security (root) — `sql/security/`

Surface area, audit specifications, DDL triggers, linked server security, proxies and credentials.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-AuditSpecifications` | SQL Server Audit objects and specifications with compliance gap analysis. SQL Audit (the formal mechanism for SOX, GDPR, PCI-DSS) is completely separate from login monitoring — most inherited servers have none configured. Surfaces missing critical action groups (FAILED_LOGIN_GROUP, privilege changes) and database-level audit specifications across all user databases. | [post](https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/) |  |  |
| `Get-DatabaseMailAndXpCmdShell` | Security surface area audit — xp_cmdshell, CLR, Database Mail, force encryption, and active NTLM connections. |  |  | yes |
| `Get-DdlTriggers` | Server-level DDL triggers. These fire on schema changes (CREATE/ALTER/DROP) and are often unknown to incoming DBAs. Can block DDL, audit changes, or enforce naming conventions — a hidden dependency on inherited servers. | [post](https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/) |  |  |
| `Get-LinkedServerSecurity` | Lists linked servers with their security context — how local logins are mapped to remote logins. Catch-all mappings with stored credentials are the highest-risk configuration. | [post](https://sqldba.blog/dba-scripts-get-linked-servers/) |  | yes |
| `Get-ProxyAndCredentials` | Lists SQL Agent proxies and server-level credentials with their identity and associated subsystems. Proxies that use stored credentials to run Agent steps under a different account are a common privilege escalation path. | [post](https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/) |  |  |

### Security: access — `sql/security/access/`

Role membership, permissions, orphaned users, sysadmins, weak logins, failed logins, login activity.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-DatabasePermissions` | Returns all explicit object- and schema-level GRANT/DENY permissions in the current database. Shows grantee, permission, object, and grantor. Run in the context of each user database — does not iterate across databases. | [post](https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/) |  |  |
| `Get-DatabaseRoleMembers` | List database role memberships across all online user databases. | [post](https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/) |  |  |
| `Get-FailedLoginSummary` | Aggregated failed login analysis from the SQL Server error log and current lockout state per SQL login. Surfaces brute-force patterns and locked accounts. Complements Get-WeakLoginSettings (which checks policy configuration) — this checks what is actually happening. Note: SQL Server 2025 does not write 18456 events to RING_BUFFER_SECURITY_ERROR; xp_readerrorlog is the reliable cross-version source for login failures. | [post](https://sqldba.blog/dba-scripts-get-login-security-audit/) |  | yes |
| `Get-LoginLastActivity` | All SQL and Windows logins with current session status, connection details, and disabled/locked state. Note: SQL Server does not record "last login time" natively without a SQL Server Audit configured. This script shows what is available: current active sessions and login metadata. For historical last-login tracking, enable a Server Audit with LOGIN action group. | [post](https://sqldba.blog/dba-scripts-get-login-security-audit/) |  |  |
| `Get-LoginPermissions` | Show explicit server-level permissions granted or denied to logins. | [post](https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/) |  |  |
| `Get-OrphanedUsers` | Find database users with no matching server login — common after migrations or login drops. | [post](https://sqldba.blog/dba-scripts-get-orphaned-users/) |  | yes |
| `Get-ServerRoleMembers` | List members of every fixed and user-defined server role — the comprehensive server-privilege audit. | [post](https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/) |  |  |
| `Get-SysadminMembers` | List members of the sysadmin fixed server role — the focused privileged-access check (sysadmin only). | [post](https://sqldba.blog/dba-scripts-get-sysadmin-members/) |  | yes |
| `Get-UserPermissionsAudit` | Audit one login's effective access across the whole instance in a single pass: server roles/connection principals, plus per-database role membership — resolved through the real security token, so nested AD group membership shows up automatically. EDIT @LoginName below before running. |  |  |  |
| `Get-WeakLoginSettings` | Identify SQL logins with weak security settings: policy off, expiration off, or sa enabled. | [post](https://sqldba.blog/dba-scripts-get-login-security-audit/) |  | yes |

### Security: encryption — `sql/security/encryption/`

Certificates and keys, expiry warnings, TDE status.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-CertificateExpiryWarnings` | All user-managed certificates across server and user databases with days until expiry. | [post](https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/) |  | yes |
| `Get-CertificatesAndKeys` | Server-level certificates and asymmetric keys with expiry, usage detection, and lifecycle risk flags. Certificates created for TDE, AG encrypted endpoints, or linked server auth are commonly created and never monitored. An expired cert doesn't break TDE in memory but prevents restoring the database on another server. | [post](https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/) |  |  |
| `Get-TdeStatus` | Transparent Data Encryption (TDE) status across all databases. Includes encryption state, key algorithm, encryptor type, and tempdb encryption side-effect awareness. | [post](https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/) |  |  |

### High availability: Always On — `sql/high-availability/always-on/`

Replica state, latency, failover readiness, readable secondary usage.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-AgFailoverReadiness` | Per-AG, per-database failover readiness with quantified RPO and RTO estimates. Answers "would a failover succeed RIGHT NOW and what would it cost?" RTO = estimated seconds to drain redo queue at current redo rate. RPO = log send queue size (data that would be lost if primary fails now). | [post](https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/) |  | yes |
| `Get-AvailabilityGroupLatency` | Display AG replica synchronization timing, queue health, and replication rates. | [post](https://sqldba.blog/script-check-always-on-availability-group-latency/) |  | yes |
| `Get-AvailabilityGroupReplicaState` | Show AG replica health, connection state, and synchronization status for failover readiness. | [post](https://sqldba.blog/script-check-ag-replica-role-and-synchronization-state/) |  | yes |
| `Get-ReadableSecondaryUsage` | Shows Availability Group replica connection modes and read-only routing configuration. Identifies which replicas allow readable secondary access and whether routing is configured. Returns a status row on standalone instances (no AG). | [post](https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/) |  |  |

### High availability: failover cluster — `sql/high-availability/fci/`

Cluster node availability events.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-LastNodeBlip` | Returns SQL Server error log entries that mention failover, alongside the current instance start time. On an FCI, every node blip causes SQL Server to restart on the receiving node — sqlserver_start_time is when it last came online. If no rows are returned there are no 'failover' entries in the current error log archive; use the PowerShell Get-WinEvent approach to query the Windows Failover Clustering Operational log directly (see blog post). | [post](https://sqldba.blog/dba-scripts-get-last-node-blip/) |  | yes |

### High availability: mirroring — `sql/high-availability/mirroring/`

Mirroring status and endpoint health (deprecated feature, still in the field).

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-MirroringEndpointHealth` | Returns the state, port, role, and authentication configuration of the database mirroring endpoint. If the endpoint is not STARTED, mirroring cannot communicate. Run on both the principal and mirror server during troubleshooting. | [post](https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/) |  | yes |
| `Get-MirroringStatus` | Shows health, state, and point-in-time latency for all mirrored databases on this instance. Run on the principal server. Reports operating mode, mirroring state, database size, log send queue, and redo queue. Note: Database Mirroring has been deprecated since SQL Server 2012. Always On Availability Groups are the supported replacement for new deployments. | [post](https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/) |  |  |

### High availability: replication — `sql/high-availability/replication/`

Replication status, distribution and log reader agents, undistributed commands.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Get-DistributionAgentStatus` | Monitors Distribution Agent activity — status, delivery latency (current and overall), transaction and command counts, and any replication errors. Returns the last 24 hours of history. Run against the distribution database (-Database distribution). | [post](https://sqldba.blog/dba-scripts-get-replication-agent-status/) |  |  |
| `Get-LogReaderAgentStatus` | Monitors Log Reader Agent activity — status, delivery latency, transaction and command counts, and any replication errors. Returns the last 24 hours of history. Run against the distribution database (-Database distribution). | [post](https://sqldba.blog/dba-scripts-get-replication-agent-status/) |  |  |
| `Get-ReplicationStatus` | Lists all publications and subscriptions from the distribution database, including publication type, subscriber server and database, subscription type, and status. Finds the distribution database automatically and returns a status row when replication is not configured, so it is safe to run from master on any instance. | [post](https://sqldba.blog/dba-scripts-get-replication-status/) |  | yes |
| `Get-UndistributedCommands` | Shows the count of commands that have been read from the publisher transaction log but not yet delivered to subscribers. A high and growing count indicates Distribution Agent lag or failure. Run against the distribution database (-Database distribution). | [post](https://sqldba.blog/dba-scripts-get-replication-agent-status/) |  |  |

### Maintenance — `sql/maintenance/`

Job status plus DDL generators for backup, index maintenance, and housekeeping jobs.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Generate-BackupJobs` | Generates SQL Agent DDL to create three scheduled maintenance jobs: DBA - Backup - FULL daily full backup of all online user databases DBA - Backup - LOG transaction log backups on a short interval (default 15 min) DBA - Backup - Cleanup removes old backup files based on retention policy Edit the parameters section, review the output, then run on the target instance. | [post](https://sqldba.blog/dba-scripts-generate-maintenance-jobs/) |  |  |
| `Generate-IndexMaintenanceJobs` | Generates SQL Agent DDL for: DBA - Index Maintenance rebuilds/reorganizes fragmented indexes across all online user databases using LIMITED scan. Automatically uses ONLINE = ON on Enterprise/Developer; falls back to offline rebuild on Standard/Web edition. DBA - Statistics Update runs sp_updatestats on every online user database (tables that had rows modified since last update only). Edit the parameters section, review the output, then run on the target instance. | [post](https://sqldba.blog/dba-scripts-generate-maintenance-jobs/) |  |  |
| `Generate-IndexMaintenanceScript` | Generates ALTER INDEX REBUILD / REORGANIZE statements for fragmented indexes across all online user databases. Review the output, then execute the maintenance_statement column in a maintenance window. Does not execute any maintenance — read-only. |  |  |  |
| `Generate-MaintenanceJobs` | Generates SQL Agent DDL for routine housekeeping jobs: DBA - Integrity Check DBCC CHECKDB on all online user databases (weekly) DBA - History Cleanup purges msdb backup history, job history, and Database Mail log based on retention periods (weekly) DBA - Cycle Error Log sp_cycle_errorlog to rotate the SQL Server error log and prevent it growing unbounded (weekly) Edit the parameters section, review the output, then run on the target instance. | [post](https://sqldba.blog/dba-scripts-generate-maintenance-jobs/) |  |  |
| `Get-MaintenanceJobStatus` | Reports last run outcome, duration, and next scheduled run for all DBA maintenance jobs (any job whose name starts with 'DBA'). Use after deploying the maintenance framework to confirm jobs are running on schedule and not failing silently. | [post](https://sqldba.blog/dba-scripts-get-maintenance-job-status/) |  | yes |

### Migration and upgrades — `sql/migration/`

Pre-migration assessment and readiness, plus DDL generators for logins, jobs, user mappings, linked servers, and restores.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Fix-OrphanedUsers` | Generate ALTER USER statements to re-map orphaned database users to their matching server-level logins across all user databases. Run on TARGET after databases are restored and logins are created. | [post](https://sqldba.blog/dba-scripts-fix-orphaned-users/) |  |  |
| `Generate-AgentJobScript` | Generate sp_add_job DDL to recreate all SQL Agent jobs on the target server. | [post](https://sqldba.blog/dba-scripts-generate-migration-scripts/) |  |  |
| `Generate-LinkedServerScript` | Generate sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers. Run on SOURCE server. Execute the output on TARGET after migration. | [post](https://sqldba.blog/dba-scripts-generate-migration-scripts/) |  |  |
| `Generate-LoginScript` | Generate CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved. | [post](https://sqldba.blog/dba-scripts-generate-migration-scripts/) |  |  |
| `Generate-RestoreWithMoveScript` | Generate RESTORE DATABASE scripts with WITH MOVE for all online user databases. Run on SOURCE server. Supply the backup path and path prefix mappings for data and log files before executing the output on TARGET. | [post](https://sqldba.blog/dba-scripts-generate-migration-scripts/) |  |  |
| `Generate-UserMappingScript` | Generate CREATE USER and role membership DDL for all user databases. | [post](https://sqldba.blog/dba-scripts-generate-migration-scripts/) |  |  |
| `Get-CompatibilityLevelAudit` | Lists all user databases with current compatibility level, equivalent SQL version name, and the instance's native compatibility level. Use to plan compat level upgrades before or after migration. | [post](https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/) |  |  |
| `Get-DeprecatedFeaturesInUse` | Lists deprecated SQL Server features used since the last service restart, ranked by usage count. Zero rows means no deprecated features have been called. | [post](https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/) |  |  |
| `Get-EditionFeatureUsage` | Audits Enterprise-only features in active use on this instance. Run before any edition downgrade (Enterprise → Standard, Standard → Web). Each row describes a feature, whether it is in use, and what breaks on the target edition. | [post](https://sqldba.blog/dba-scripts-get-edition-feature-usage/) |  |  |
| `Get-MigrationLoginAudit` | Audits all server-level principals that need to be migrated — SQL logins, Windows logins, and server roles — with migration risk and action per login type. | [post](https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/) |  |  |
| `Get-MigrationRiskAssessment` | Pre-migration risk scan — returns categorised HIGH/MEDIUM/INFO findings for compatibility, database settings, linked server dependencies, and sizing. | [post](https://sqldba.blog/dba-scripts-get-migration-risk-assessment/) |  |  |
| `Get-PostMigrationValidation` | Run on both SOURCE and TARGET and compare the CSV outputs to confirm the migration is complete and consistent. Surfaces database count mismatches, databases not ONLINE, orphaned users, and login count deltas. | [post](https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/) |  |  |
| `Get-VersionUpgradeReadiness` | Pre-upgrade readiness summary for SQL Server version upgrades. One result set with a section column: instance summary, per-database compatibility levels, configuration items to review, and sizing for migration window planning. Run on SOURCE. Complements Get-DeprecatedFeaturesInUse.sql (feature detail) and Get-MigrationRiskAssessment.sql (per-database risk). | [post](https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/) |  |  |

### Collectors — `sql/collectors/`

SQL Agent job generators that build a DBAMonitor history, plus the delta queries that read it. See `sql/collectors/README.md`.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Generate-CollectorAlertJob` | Generates DDL to create the DBA - Collector Alert SQL Agent job. The job queries [DBAMonitor].[collector].* tables, applies threshold checks, outputs findings, and RAISERRORs on any CRITICAL result (causing the step to fail and triggering Agent notification routing). Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-AgHealth` | Generates DDL to create the DBA - Collect AG Health SQL Agent job. Creates the target database and a system-versioned (temporal) collector table if absent, then outputs T-SQL to install a recurring AG replica state MERGE job. Each run upserts current replica and database synchronization state — SQL Server automatically records every change in the paired history table, capturing exactly when replicas became disconnected, unsynchronized, or changed role. On instances with no AG configured, a NO_AG sentinel row is inserted once so the job always succeeds and the table remains queryable. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-Blocking` | Generates DDL to create the DBA - Collect Blocking SQL Agent job. Creates the target database and collector.Blocking table if absent, then outputs T-SQL to install a recurring blocking-chain collection job. The job step inserts rows only when active blocking exists. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-DatabaseGrowth` | Generates DDL to create the DBA - Collect Database Growth SQL Agent job. Creates the target database and a system-versioned (temporal) collector table if absent, then outputs T-SQL to install a recurring database file size MERGE job. Each run upserts current file sizes into DatabaseGrowthCurrent — SQL Server automatically records every change in the paired history table. Query DatabaseGrowthCurrent FOR SYSTEM_TIME BETWEEN to retrieve historical file sizes for trend analysis and growth forecasting. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-Deadlocks` | Generates DDL to create the DBA - Collect Deadlocks SQL Agent job. Creates the target database and collector.Deadlocks table if absent, then outputs T-SQL to install a recurring deadlock collection job. Reads the system_health XEvent ring buffer (~250 events, no session setup required) and inserts only events newer than the latest deadlock_time already stored for this server, preventing duplicate rows. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-ErrorLog` | Generates DDL to create the DBA - Collect Error Log SQL Agent job. Creates the target database and collector.ErrorLog table if absent, then outputs T-SQL to install a recurring error log collection job. Each run inserts only entries newer than the latest log_date already stored for this server, preventing duplicate rows. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-IndexFragmentation` | Generates DDL to create the DBA - Collect Index Fragmentation SQL Agent job. Creates the target database and collector.IndexFragmentation table if absent, then outputs T-SQL to install a weekly index fragmentation snapshot job. The job iterates all online user databases using SAMPLED mode (reads ~1% of pages — accurate for detection, avoids DETAILED overhead). Indexes smaller than 100 pages and heaps are excluded. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-Perfmon` | Generates DDL to create the DBA - Collect Perfmon SQL Agent job. Creates the target database and collector.Perfmon table if absent, then outputs T-SQL to install a recurring performance counter snapshot job. Captures sys.dm_os_performance_counters (buffer pool, memory, throughput, connections, locks, plan cache). Rate counters require delta analysis. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-QueryStore` | Generates DDL to create the DBA - Collect Query Store SQL Agent job. Creates the target database and collector.QueryStore table if absent, then outputs T-SQL to install a recurring Query Store collection job. The job iterates all online user databases with QS enabled and inserts the top 50 queries by average CPU from the most recently completed runtime stats interval. Databases without QS are silently skipped. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-StorageIO` | Generates DDL to create the DBA - Collect Storage IO SQL Agent job. Creates the target database and collector.StorageIO table if absent, then outputs T-SQL to install a recurring I/O stats snapshot job. sys.dm_io_virtual_file_stats is cumulative — diff adjacent snapshots to measure I/O activity and latency within each collection interval. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-Tempdb` | Generates DDL to create the DBA - Collect TempDB SQL Agent job. Creates the target database and collector.Tempdb table if absent, then outputs T-SQL to install a recurring TempDB space snapshot job. Captures file-level space (row_type = 'file') and top session consumers (row_type = 'session') in a single table using the row_type discriminator. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-VlfCount` | Generates DDL to create the DBA - Collect VLF Count SQL Agent job. Creates the target database and a system-versioned (temporal) collector table if absent, then outputs T-SQL to install a daily VLF count MERGE job. Each run upserts current VLF counts per database — SQL Server automatically records every change in the paired history table, capturing exactly when VLF counts spiked (autogrowth) or dropped (log maintenance). Edit parameters, review output, then run on the target instance. |  |  |  |
| `Generate-CollectorJob-WaitStats` | Generates DDL to create the DBA - Collect Wait Stats SQL Agent job. Creates the target database and collector.WaitStats table if absent, then outputs T-SQL to install a recurring wait stats snapshot job. sys.dm_os_wait_stats is cumulative — diff adjacent snapshots for interval rates. Edit parameters, review output, then run on the target instance. |  |  |  |
| `Get-PerfmonDelta` | Computes interval deltas for cumulative performance counters (cntr_type 272696576) between the two most recent snapshots in [DBAMonitor].[collector].[Perfmon]. Point-in-time gauges (cntr_type 65792) are shown as their current value. |  |  |  |
| `Get-StorageIODelta` | Computes interval I/O deltas between the two most recent snapshots in [DBAMonitor].[collector].[StorageIO]. Shows read/write counts, bytes transferred, and derived average latency for the interval. Detects SQL Server restarts and suppresses invalid deltas. |  |  |  |
| `Get-WaitStatsDelta` | Computes interval wait deltas between the two most recent snapshots in [DBAMonitor].[collector].[WaitStats]. Shows delta_wait_ms, task count, average wait per task, and percentage of total interval wait — sorted by heaviest waiter descending. Detects SQL Server restarts between snapshots and suppresses invalid deltas. |  |  |  |

### Traces (Extended Events) — `sql/traces/`

Create, review, and remove Extended Events sessions. See `sql/traces/README.md`.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Create-DecommissionAuditSession` | Creates an Extended Events session that captures all T-SQL batch, RPC, successful login, and failed login activity against a specific database (or all databases). Use before decommissioning or retiring a database to prove zero usage. Run for at least 5–7 business days to catch batch jobs and end-of-period activity. | [post](https://sqldba.blog/dba-scripts-create-decommission-audit-session/) | CreatesObjects |  |
| `Create-LoginActivitySession` | Creates a lightweight Extended Events session that captures every successful and failed login to the server — who, from where, and using which application. Use to answer "who connects to this server" before decommissioning, during security reviews, or to baseline connection patterns. | [post](https://sqldba.blog/dba-scripts-create-login-activity-session/) | CreatesObjects |  |
| `Create-SpExecutionSession` | Creates an Extended Events session capturing stored procedure and RPC execution — procedure name, duration, login, and hostname. Use to profile what procedures are called most often, by whom, and how long they take — especially useful before a migration or decommission. | [post](https://sqldba.blog/dba-scripts-create-sp-execution-session/) | CreatesObjects |  |
| `Get-ActiveXeSessions` | Shows all currently running Extended Events sessions with their targets and file output paths. | [post](https://sqldba.blog/dba-scripts-get-active-xe-sessions/) |  |  |
| `Get-XeSessionActivity` | Reads and summarises Extended Events file target data for a named session. Returns unique caller combinations (login, hostname, app, database) with occurrence counts and time range. Primary use: reviewing DecommissionAudit or LoginActivity session output to determine if a database or server is still in active use. | [post](https://sqldba.blog/dba-scripts-get-xe-session-activity/) |  |  |
| `Remove-XeSession` | Lists all DBA-created Extended Events sessions (running and stopped) and generates the DDL to stop and drop each one. Copy the remove_cmd value for any session you want to clean up and run it. .xel files on disk are NOT deleted — review them first with Get-XeSessionActivity.sql, then delete manually. | [post](https://sqldba.blog/dba-scripts-remove-xe-session/) |  |  |

### Lab — `sql/lab/`

Dev and test only. Never run these against production.

| Script | What it returns | Post | Writes | HC |
|--------|-----------------|------|--------|----|
| `Create-BlockingScenario` | Controlled blocking scenario for testing Get-BlockingChains, Get-BlockingSessions, and blocking analysis tools. |  | WritesData |  |
| `Kill-BlockingSession` | Template for terminating a blocking session after confirming it is safe to do so. Always run Get-BlockingChains first to identify the head blocker and understand the impact before killing anything. |  | WritesData |  |
| `New-TestDatabases` | Create multiple test databases with randomised names for lab and migration scenarios. | [post](https://sqldba.blog/script-generate-test-databases/) | Creates |  |

---

## PowerShell scripts

Scripts with real logic — orchestrators, DDL generators, and OS-level tools. The 153 thin wrappers
under `powershell/wrappers/` are not listed here: there is exactly one per SQL script, it carries the
same name, and it does nothing but pass your parameters to the matching `.sql` file. Adding one is
what makes a SQL script appear in the web UI.

### Reporting and health check orchestrators — `powershell/reporting/`

Human-triggered runs with real logic: collection, rules review, AI assessment, capacity and drift analysis.

| Script | What it does | Risk |
|--------|--------------|------|
| `Compare-ConfigurationBaseline` | Compare current sp_configure and key database settings against a saved baseline. | SAFE |
| `Get-CapacityProjection` | Projects days-to-full for databases and drives from collector historical data. | SAFE |
| `Invoke-AiAssessment` | Sends a healthcheck collection to the Claude API and writes an AI-generated assessment report. | SAFE (read-only locally — but sends healthcheck CSV contents to the Anthropic API; |
| `Invoke-AssessmentReport` | Runs a full instance assessment and generates a structured markdown report. | SAFE |
| `Invoke-HealthCheckCollection` | Collect all key health-check data in one pass for offline review or archiving. | SAFE |
| `Invoke-MultiServerHealthCheck` | Estate-wide health check — one command to flag which servers need | SAFE |
| `Review-HealthCheckOutput` | Turn raw CSV collection output into an actionable findings list. | SAFE |

### Live incident diagnostics — `powershell/diagnostics/`

Run these during an incident. Both support `-IncludePlan` to export execution plans.

| Script | What it does | Risk |
|--------|--------------|------|
| `Get-ActiveRequests` | Triage runaway queries, blocking chains, and TempDB consumers. | SAFE |
| `Get-BlockingChains` | Deep-dive blocking diagnostic. Shows every session in every active | SAFE |

### Multi-server (fleet) — `powershell/reporting/multi-server/`

Self-contained scripts that run against a server list. See `powershell/reporting/multi-server/README.md`.

| Script | What it does | Risk |
|--------|--------------|------|
| `MultiServer-Compare-Configuration` | Cross-server sp_configure drift detection — finds settings where any server differs from the majority. | SAFE |
| `MultiServer-GetBackupStatus` | Check backup coverage across multiple SQL Server instances. Shows last full, diff, and log backup age with coverage status. |  |
| `MultiServer-GetBlockingSessions` | Check for active blocking sessions across multiple SQL Server instances. Zero rows means no blocking. |  |
| `MultiServer-GetDatabaseSizes` | Report data and log file sizes across multiple SQL Server instances. Free space is approximate from sys.master_files. |  |
| `MultiServer-GetDiskSpace` | Check disk space on multiple remote hosts using CIM. Flags volumes below configurable thresholds. |  |
| `MultiServer-GetFirewallRules` | List Windows Firewall rules across multiple remote hosts via WinRM. |  |
| `MultiServer-GetMaintenanceJobStatus` | Checks whether DBA maintenance jobs (DBA - Backup - FULL, DBA - Backup - LOG, |  |
| `MultiServer-GetPatchLevel` | Reports SQL Server version, CU level, and edition across multiple instances. |  |
| `MultiServer-GetRecentEventLogs` | Pull recent Error and Warning events from Windows Event Logs on multiple remote hosts. |  |
| `MultiServer-GetServiceStatus` | Check Windows service status across multiple remote hosts using Get-Service over RPC. |  |
| `MultiServer-GetWaitStats` | Show top wait types ranked by total wait time across multiple SQL Server instances. |  |
| `MultiServer-RestartService` | Restart a named Windows service on multiple remote hosts via WinRM. |  |
| `MultiServer-TestSqlPort` | Test TCP connectivity to SQL Server port 1433 (or custom port) on multiple servers. No WinRM needed. |  |

### Migration toolkit — `powershell/migration/`

Pre-flight assessment, baseline export, and DDL generators that write .sql files to `output-files\migration\`.

| Script | What it does | Risk |
|--------|--------------|------|
| `Export-MigrationBaseline` | Captures a performance and configuration baseline snapshot for pre/post migration comparison. | SAFE |
| `Generate-AgentJobScript` | Produce a migration-ready Agent job script; review owner_login_name before running on target. | SAFE |
| `Generate-LinkedServerScript` | Produce a migration-ready linked server script to run on the target server after migration. | SAFE |
| `Generate-LoginScript` | Produce a migration-ready login script to run on the target server after databases are restored. | SAFE |
| `Generate-RestoreWithMoveScript` | Produce a RESTORE WITH MOVE script template for migration to a target server with different drive paths. | SAFE |
| `Generate-UserMappingScript` | Produce a migration-ready user mapping script to run on the target after logins and databases are in place. | SAFE |
| `Invoke-MigrationExport` | One-command export of logins, agent jobs, linked servers, server config, restore | SAFE |
| `Invoke-MigrationPreFlightCheck` | Catch blockers before the migration window — connectivity, version mismatch, | SAFE |
| `Invoke-PreMigrationAssessment` | Runs the full pre-migration assessment suite and saves each result as a named CSV in a timestamped folder. | SAFE |

### Instance inventory — `powershell/inventory/`

Instance-level summaries and OS configuration checks.

| Script | What it does | Risk |
|--------|--------------|------|
| `Get-InstanceHealthSummary` | Retrieve server name, edition, version, and core configuration settings for a quick health summary. | SAFE |
| `Get-InstanceSnapshot` | Retrieve SQL Server instance configuration settings for baseline, migration, or incident prep. | SAFE |
| `Test-OsConfiguration` | OS-level configuration checks not visible via SQL DMVs: power plan, page file, pending reboot. | SAFE |

### Disk and file tools — `powershell/disk-space/`

Windows-side disk and backup-folder checks. These read the file system, not SQL Server.

| Script | What it does | Risk |
|--------|--------------|------|
| `Get-BackupAge` | Report the age of the most recent backup for each user database using msdb history. | SAFE |
| `Get-DiskSpaceSummary` | Display available disk space for all local fixed drives on the current machine. | SAFE |
| `Get-LargestFolders` | Find the largest folders on a drive to identify disk space candidates for cleanup. | SAFE |
| `Get-OldestBackupFolderFiles` | Review the age of backup sets in a backup root to identify stale or missing backup media. | SAFE |

### SQL Server installation — `powershell/installation/`

Install, configure, validate, and uninstall SQL Server. These change the server.

| Script | What it does | Risk |
|--------|--------------|------|
| `configure-sql` | Apply sp_configure settings to an existing SQL Server instance. |  |
| `generate-install-report` | Generate a summary report from SQL Server installation and configuration logs. |  |
| `install-sql` | Install SQL Server from setup.exe with validated parameters and post-install configuration. |  |
| `post-install-validation` | Validate a SQL Server installation is configured correctly. |  |
| `pre-install-check` | Run pre-installation checks before deploying SQL Server. |  |
| `uninstall-sql` | Uninstall a SQL Server instance with optional data directory cleanup. |  |

### Patching — `powershell/patching/`

SQL Server and SSMS patch status and installation.

| Script | What it does | Risk |
|--------|--------------|------|
| `Patch-SqlServer` | Patch this machine's SQL Server to the latest Cumulative Update. One file, no config. | HIGH IMPACT - installs a Cumulative Update; SQL Server restarts mid-install. |
| `patch-summary` | Show patch status for all SQL Server instances and SSMS on this machine. |  |

### Patching: SQL Server — `powershell/patching/sql/`

Multi-server automated patching.

| Script | What it does | Risk |
|--------|--------------|------|
| `Invoke-SqlPatch` | Download and apply SQL Server Cumulative Updates to local or remote servers. |  |

### Patching: SSMS — `powershell/patching/ssms/`

SSMS install and uninstall.

| Script | What it does | Risk |
|--------|--------------|------|
| `install-ssms` | Install or update SQL Server Management Studio (SSMS 22 by download, SSMS 20 via winget). |  |
| `uninstall-ssms` | Silently uninstall SQL Server Management Studio (handles both the WiX and VS Installer paths). |  |

### Lab — `powershell/lab/`

Dev and test only.

| Script | What it does | Risk |
|--------|--------------|------|
| `New-MultipleDatabases` | Lab and migration simulation — generate a large set of named databases quickly. | HIGH IMPACT — creates databases |
| `Remove-DatabasesByPrefix` | Lab cleanup — remove a batch of test or migration databases by prefix. | HIGH IMPACT — drops databases permanently |
| `Run-CreateTestDatabases` | Simple SQL-driven test database creation. For SMO-based bulk creation | HIGH IMPACT — creates databases |

---

## Counts

| Layer | Count |
|-------|-------|
| SQL scripts | 181 |
| — of which have a companion post | 143 |
| — of which are in the health check suite | 45 |
| — of which create objects or write data | 6 |
| PowerShell scripts with real logic | 52 |
| Thin wrappers (one per SQL script) | 153 |
