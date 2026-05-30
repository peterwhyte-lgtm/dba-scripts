---
title: One-Command SQL Server Health Check
slug: sql-server-health-check-one-command
published: 
status: draft
category: monitoring
tags: [health-check, monitoring, automation, powershell]
scripts:
  - powershell/reporting/Invoke-HealthCheckCollection.ps1
  - powershell/reporting/Review-HealthCheckOutput.ps1
seo_keyphrase:    SQL Server health check
seo_title:        One-Command SQL Server Health Check
seo_description:  Run a complete SQL Server health check with one command. Collect 19 diagnostic data points and get a prioritised list of CRITICAL and WARNING findings. (151 chars)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# One-Command SQL Server Health Check

The best health checks are the ones you actually run. Complex multi-tool dashboards are great when you're actively monitoring, but when you're on-call and something is wrong at 10pm, you want one command that gives you a prioritised list of problems to deal with.

This post covers the health check workflow from the dba-scripts repo: a two-command approach that collects 19 diagnostic data points from a SQL Server instance and surfaces a findings list rated CRITICAL, WARNING, and INFO.

## The workflow

There are two steps:

**Step 1 — collect.** Run 19 SQL scripts against the target instance and save each result as a named CSV in a timestamped folder.

**Step 2 — review.** Read those CSVs and apply threshold rules to produce a ranked findings list.

Splitting them means the collection can run on a schedule and you review later, or you can run both back-to-back for live triage.

```powershell
# Step 1 — collect (quiet mode suppresses verbose per-script output)
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance . -Quiet

# Step 2 — review (auto-picks the most recent collection folder)
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

Or if you have the root launcher:
```powershell
.\run.ps1 Invoke-HealthCheckCollection -Quiet
.\run.ps1 Review-HealthCheckOutput
```

## What gets collected

The collection script runs these 19 scripts in sequence:

| Label | What it captures |
|-------|----------------|
| server-info | SQL version, edition, patch level |
| os-hardware | OS release, CPU count, RAM, uptime |
| database-health | Database state, recovery model, auto-shrink, auto-close flags |
| database-sizes | Data and log file sizes with free space per database |
| database-files | Per-file paths, sizes, growth settings |
| backup-times | Last full, diff, and log backup per database |
| backup-coverage | Backup status flag (OK / STALE_FULL / NO_FULL_BACKUP / etc.) |
| tlog-usage | Transaction log used/free space per database |
| memory-config | Max server memory setting vs current SQL Server consumption |
| wait-stats | Top 20 wait types with benign waits filtered out |
| active-sessions | Currently connected users and requests |
| tempdb-usage | TempDB file sizes and free space |
| job-failures | SQL Agent failures in the last 7 days |
| recent-errors | Error log entries from the last 24 hours |
| dbcc-checkdb | Last successful DBCC CHECKDB per database |
| suspect-pages | Any pages recorded in msdb.dbo.suspect_pages |
| io-usage | Per-database I/O with read/write latency |
| security-surface-area | xp_cmdshell, CLR, Database Mail enabled state |
| weak-logins | SQL logins with password policy or expiration disabled |

Each CSV is saved to `output-files\healthcheck\<servername>-<timestamp>\` and named after its label. The folder name contains the collection timestamp so you always know when the data is from.

## What the review checks

The review script reads the CSVs and applies 17 rules. Findings are rated CRITICAL, WARNING, or INFO.

**CRITICAL — stop what you are doing:**
- Any entry in `suspect-pages` — this means SQL Server has recorded a storage-level page corruption. Run `DBCC CHECKDB` on the affected database immediately.
- `sa` login is enabled — a security configuration that should be resolved.
- A database is not ONLINE — investigate `state_desc`: SUSPECT, EMERGENCY, or RESTORING all need immediate attention.
- A database has never had a full backup.

**WARNING — investigate today:**
- Full backup older than 25 hours
- Log backup older than 4 hours for a FULL recovery database
- FULL recovery database with no log backup ever recorded
- DBCC CHECKDB not run in over 7 days
- Transaction log more than 80% used
- Read or write I/O latency above 50ms
- SQL Agent job failures in the last 7 days
- `max server memory` left at the SQL Server default (2,147,483,647 MB — uncapped)
- Data files with less than 10% free space
- AUTO_SHRINK or AUTO_CLOSE enabled
- Percent-based autogrowth on any database file
- SQL login with password policy or expiration disabled
- Specific high-concern wait types above 10% of total wait time: `PAGEIOLATCH`, `WRITELOG`, `RESOURCE_SEMAPHORE`, `CXPACKET`, `LCK_M_X`

**INFO — worth knowing:**
- Active blocked sessions
- Sessions with open transactions
- Error log entries (filtered for noise — if this fires, look at the CSV for details)

## Example output

```text
============================================
  DBA Health Check Review
============================================
  Folder    : output-files\healthcheck\.-20260529-091500
  Collected : 2026-05-29 09:15:00
  Reviewed  : 2026-05-29 09:15:42
--------------------------------------------

  [CRITICAL ] Backup               SalesDB
               No full backup on record

  [WARNING  ] DBCC CHECKDB         ReportingDB
               Last good CHECKDB was 12 days ago (threshold: 7 days)

  [WARNING  ] Memory Config        max server memory
               max server memory is at the SQL Server default (2,147,483,647 MB = uncapped)

  [WARNING  ] Wait Statistics      WRITELOG
               18.4% of total wait time — Transaction log write bottleneck

  [INFO     ] Error Log            SQL Server error log
               3 non-routine entry/entries in last 24h — review recent-errors.csv

--------------------------------------------
  CRITICAL: 1  |  WARNING: 3  |  INFO: 1
```

## Saving the findings as CSV

Pass `-OutputFormat Csv` to the review script to write the findings to a `findings.csv` in the collection folder. Useful for tracking what you found and fixed over time.

```powershell
.\powershell\reporting\Review-HealthCheckOutput.ps1 -OutputFormat Csv
```

## Running against a remote server

```powershell
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance MYSERVER\INST01 -Quiet
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

The collection script creates a separate folder per server (`MYSERVER-INST01-20260529-091500`), so you can collect from multiple servers and review each folder independently.

## Adjusting the thresholds

The review thresholds are set for typical daily backup schedules and standard SLA expectations. To adjust them, open `powershell\reporting\Review-HealthCheckOutput.ps1` and find the relevant check block:

- Full backup threshold: `$ageH -gt 25` → change 25 to your full backup interval in hours plus a buffer
- Log backup threshold: `$logAgeH -gt 4` → change 4 to your log backup interval in hours plus a buffer
- I/O latency: `$readLat -gt 50` → change 50ms to your storage tier's expected latency
- DBCC staleness: `$days -gt 7` → change 7 to match your CHECKDB schedule

## Related scripts in this repo

- [`Get-SuspectPages.sql`](../sql/monitoring/Get-SuspectPages.sql) — if the review flags suspect pages, drill in here
- [`Get-LastDbccCheckdb.sql`](../sql/monitoring/Get-LastDbccCheckdb.sql) — full per-database CHECKDB history
- [`Get-BackupCoverage.sql`](../sql/backups/Get-BackupCoverage.sql) — detailed backup status per database

## Get the scripts

The full workflow is available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`powershell/reporting/Invoke-HealthCheckCollection.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Invoke-HealthCheckCollection.ps1)
- [`powershell/reporting/Review-HealthCheckOutput.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Review-HealthCheckOutput.ps1)

---

## SEO

**Focus keyphrase:** SQL Server health check

**Meta description** (151 chars — target 150–160):  
Run a complete SQL Server health check with one command. Collect 19 diagnostic data points and get a prioritised list of CRITICAL and WARNING findings.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `healthcheck-review-output.png` | SQL Server health check review output showing CRITICAL and WARNING findings with timestamps in PowerShell terminal | SQL Server health check review findings output |
| `healthcheck-collection-output.png` | SQL Server health check collection script running 19 diagnostic scripts with OK status for each in PowerShell | SQL Server health check collection script output |