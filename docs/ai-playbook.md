# AI Playbook — dba-tools

Decision-support for AI agents working with this repo. This is not a structure guide (see `CLAUDE.md` and `docs/repo-structure.md`). This is the answer to: *"A DBA has described a problem — which scripts, in what order, and what do I do with the output?"*

---

## The one command that covers most cases

```powershell
.\run.ps1 <ScriptName>
```

`run.ps1` is the repo entry point. It fuzzy-matches by name across `sql/` and `powershell/`, finds the script, and executes it. No paths, no params needed unless specifying a server or output format. If the DBA has already run `Set-SqlConnection.ps1`, even the server is implicit.

Use the direct wrapper path only when scripting a specific invocation or when `run.ps1` returns multiple matches:
```powershell
.\powershell\wrappers\performance\Get-WaitStatistics.ps1 -ServerInstance PROD01 -OutputFormat Csv
```

---

## Incident triage — symptom to script

### Database is slow / unexplained performance degradation

1. `Get-WaitStatistics` — the first look. Identifies dominant wait type. Run this before anything else.
2. If CXPACKET dominant → `Get-MaxdopConfiguration`, check parallelism settings
3. If PAGEIOLATCH dominant → `Get-DatabaseIoUsage`, then `Get-MissingIndexes`
4. If LCK_M_* dominant → `Get-BlockingChains` or `Get-BlockingSummary`
5. If RESOURCE_SEMAPHORE → `Get-MemoryConfigurationAndUsage`
6. `Get-TopCpuQueries` — find the query driving CPU
7. `Get-LongRunningQueries` — find what's been running longest right now

### Active blocking

1. `Get-BlockingSummary` — quick view: head blockers and count of affected sessions
2. `Get-BlockingChains` — full chain tree with queries and wait details
3. `Get-ActiveSessions` — all connections with wait type and elapsed time
4. `Get-DeadlockSummary` — if deadlocks are suspected (reads XEvent ring buffer)

For a blocking chain with a query plan:
```powershell
.\run.ps1 Get-BlockingChains -IncludePlan
```

### High CPU

1. `Get-WaitStatistics` — confirm CPU is the bottleneck (SOS_SCHEDULER_YIELD, high signal_wait_time)
2. `Get-TopCpuQueries` — top queries by CPU from plan cache
3. `Get-SlowQueriesFromCache` — top queries by elapsed time

### I/O pressure

1. `Get-WaitStatistics` — look for PAGEIOLATCH_SH / PAGEIOLATCH_EX / WRITELOG
2. `Get-DatabaseIoUsage` — per-database read/write latency breakdown
3. `Get-TopIoQueries` — queries driving I/O
4. `Get-MissingIndexes` — if reads are high and scans suspected

Latency thresholds: >20ms read or >10ms write on data files is concerning.

### TempDB pressure

1. `Get-TempdbUsage` — file sizes, free space, allocation per file
2. `Get-TempdbHotspots` — sessions consuming TempDB right now
3. `Get-TempDbConfiguration` — file count, sizing parity, autogrowth type
4. `Get-ContentionAnalysis` — latch waits and TempDB allocation bitmap contention

### Memory pressure

1. `Get-MemoryConfigurationAndUsage` — max server memory vs actual committed
2. `Get-WaitStatistics` — RESOURCE_SEMAPHORE = memory grant waits
3. `Get-PlanCacheHealth` — single-use plan bloat consuming buffer pool

### Backup concern

1. `Get-BackupCoverage` — backup status per database (CURRENT / STALE / MISSING)
2. `Get-LastDatabaseBackupTimes` — last full/diff/log per database
3. `Get-DatabaseBackupHistory` — history with durations for trend analysis
4. `Get-BackupRestoreCompletionTime` — live progress if a backup is running now

### Security review

1. `Get-SysadminMembers` — who has sysadmin
2. `Get-WeakLoginSettings` — SQL logins with policy/expiration off
3. `Get-DatabaseMailAndXpCmdShell` — surface area (xp_cmdshell, CLR, Database Mail enabled)
4. `Get-OrphanedUsers` — orphaned DB users after migrations
5. `Get-LinkedServerSecurity` — linked server login mapping risk
6. `Get-ServerRoleMembers`, `Get-DatabaseRoleMembers` — full role membership audit

### Pre-migration / instance inventory

1. `Get-MigrationRiskAssessment` — compatibility gaps, edition features, deprecations
2. `Get-DatabaseInventory`, `Get-LoginInventory`, `Get-JobInventory`, `Get-LinkedServerInventory`
3. `Invoke-PreMigrationAssessment` — orchestrates all of the above in one pass
4. `Export-MigrationBaseline` — snapshot current metrics for before/after comparison

---

## Health check workflow — collect, review, AI-assess

The healthcheck is the centrepiece of the repo, and it has THREE steps. The whole point of
collecting 39 CSVs is so that both the rules engine and an AI can review the instance —
security, performance, backups, everything. Do not stop at step 2.

```powershell
# 1. Collect all 39 healthcheck scripts → named CSVs in output-files\healthcheck\
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01

# 2. Rules review — surfaces CRITICAL / WARNING / INFO from fixed thresholds
.\powershell\reporting\Review-HealthCheckOutput.ps1

# 3. AI assessment — correlation, root cause, prioritized written report
.\powershell\reporting\Invoke-AiAssessment.ps1          # via Claude API (needs ANTHROPIC_API_KEY)
```

**If you are an AI agent reading this (Claude Code session): step 3 is YOUR job — do not
call the API script.** Read every CSV in the latest `output-files\healthcheck\<folder>`,
follow `powershell\reporting\ai-assessment-rubric.md` exactly, and write the report to
`output-files\assessments\<server>-<timestamp>-claude-code.md`. Treat findings.csv as leads
to verify and correlate, not as the answer. Setup and corporate guidance: `docs/ai-assessment.md`.

The 39 scripts in the healthcheck suite are tagged `HealthCheck : Yes` in their headers — the web UI groups them as "Health Check Suite."

**Flags raised by Review-HealthCheckOutput:**
- CRITICAL: suspect pages, SA enabled, database not ONLINE, no full backup ever
- WARNING: stale backups, DBCC CHECKDB >7 days, log >80% used, percent-based autogrowth, max memory unconfigured, I/O latency >50ms, VLF >200, maintenance job missing/failed

---

## What is safe to run immediately

**Everything in `sql/monitoring/`, `sql/performance/`, `sql/backups/`, `sql/security/`, `sql/high-availability/`** — all read-only, `SET NOCOUNT ON`, no `USE database`. Safe to run in production at any time. (`sql/lab/` and `sql/maintenance/Generate-*` are excluded — those write data or create objects.)

**Everything in `powershell/wrappers/`** — thin wrappers that call Invoke-RepoSql with the matching SQL script. Same safety level as the SQL scripts themselves.

**Reporting orchestrators** (`Invoke-HealthCheckCollection`, `Review-HealthCheckOutput`) and **incident diagnostics** (`powershell/diagnostics/` — `Get-BlockingChains`, `Get-ActiveRequests`) — read-only, safe.

**Requires judgment before running:**
- `powershell/wrappers/backups/Generate-*` — wrappers for SQL backup/restore DDL generators and backup health queries
- `powershell/wrappers/maintenance/` — generates DDL that deploys SQL Agent jobs
- `powershell/migration/Generate-*.ps1` — DDL generators, write to files
- `powershell/installation/` — modifies SQL Server configuration
- `docs/ops/change-templates/*.sql` — change operations; review before executing

---

## Output files

All script runs write to `output-files/`:

| Location | Created by |
|----------|-----------|
| `output-files\reviews\<category>\<script>-<timestamp>.csv` | `run.ps1` and direct wrapper calls |
| `output-files\healthcheck\<server>-<timestamp>\*.csv` | `Invoke-HealthCheckCollection` |
| `output-files\assessment\<server>-<timestamp>.md` | `Invoke-AssessmentReport` |
| `output-files\assessments\<server>-<timestamp>.md` | `Invoke-AiAssessment` (AI report; `-claude-code` suffix when written by a Claude Code session) |
| `output-files\migration\*.sql` | `Generate-LoginScript`, etc. |
| `output-files\collectors\<type>\<server>-<YYYYMMDD>.csv` | Scheduled collectors |

To clear before a fresh run: `.\tools\maintenance\Clear-OutputFiles.ps1`

---

## Adding new scripts (development tasks)

1. Create `sql/<category>/Get-Something.sql` with the standard header (see `docs/standards.md`)
2. Generate the wrapper: `.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\Get-Something.sql`
3. If it belongs in the daily healthcheck, add `HealthCheck : Yes` to the header AND add an entry to `Invoke-HealthCheckCollection.ps1`'s `$scripts` array
4. Run `Get-StandardsAudit` to verify header compliance

---

## Key paths — quick reference

```text
sql/                          ← SQL scripts by category
powershell/wrappers/          ← thin PS wrappers (one per SQL script; mirrors sql/ categories)
powershell/migration/         ← migration toolkit (DDL generators, orchestrators)
powershell/wrappers/maintenance/ ← maintenance job generators (wrappers for sql/maintenance/ DDL generators)
powershell/reporting/         ← healthcheck collection, AI assessment, on-demand diagnostics
sql/collectors/               ← scheduled trend collectors (SQL Agent job DDL generators)
docs/ops/                     ← runbooks, change orders, SQL templates
tools/local-sql/              ← Invoke-RepoSql (core runner), Set-SqlConnection
tools/triage/                 ← Show-RepoOverview, Find-UsefulScript
output-files/                 ← all generated output (gitignored)
```
