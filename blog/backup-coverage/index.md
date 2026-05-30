---
title: How to Audit SQL Server Backup Coverage in One Query
slug: sql-server-backup-coverage-audit
published: 
status: draft
category: backups
tags: [backups, recovery, msdb, audit]
scripts:
  - sql/backups/Get-BackupCoverage.sql
  - sql/backups/Get-LastDatabaseBackupTimes.sql
  - powershell/backup-automation/Get-BackupCoverage.ps1
seo_keyphrase:    SQL Server backup coverage
seo_title:        How to Audit SQL Server Backup Coverage in One Query
seo_description:  Audit SQL Server backup coverage across all databases in one query. Spot missing backups, stale full backups, and FULL recovery databases without log backups. (158 chars)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# How to Audit SQL Server Backup Coverage in One Query

Most production SQL Server environments have backup jobs. The question is whether those jobs are actually running — and succeeding — for every database that matters. A database added two months ago might never have been added to the backup plan. An existing database might have a job that keeps failing silently. A FULL recovery database might have log backups configured but the job hasn't run in six hours.

This post covers how to get a complete, honest picture of backup coverage across all your user databases in a single query, including a status flag that makes it easy to spot problems at a glance.

## The problem

SQL Server Agent jobs don't fail loudly. A backup job that fails at 2am might not surface until someone tries to restore at 2pm and discovers the latest backup is three days old. Relying on "no alert = everything is fine" is not a backup strategy.

For FULL recovery model databases, the risk is compounded. If log backups aren't running, the transaction log grows without bound until it fills the disk — or the DBA manually shrinks it and breaks the backup chain.

The standard way to check is to query `msdb.dbo.backupset`. The difficulty is making that output actionable at a glance: which databases are actually missing backups, which are fine, which are dangerously stale?

## The script

```sql
WITH latest_backups AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        bs.type,
        bs.backup_size / 1024.0 / 1024 AS backup_size_mb,
        ROW_NUMBER() OVER (
            PARTITION BY bs.database_name, bs.type
            ORDER BY bs.backup_finish_date DESC
        ) AS rn
    FROM msdb.dbo.backupset AS bs
)
SELECT
    d.name                                                                              AS database_name,
    d.recovery_model_desc,
    MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END)                        AS last_full_backup,
    MAX(CASE WHEN lb.type = 'D' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                        AS full_backup_age_hours,
    MAX(CASE WHEN lb.type = 'D' THEN lb.backup_size_mb END)                            AS full_backup_size_mb,
    MAX(CASE WHEN lb.type = 'I' THEN lb.backup_finish_date END)                        AS last_diff_backup,
    MAX(CASE WHEN lb.type = 'I' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                        AS diff_backup_age_hours,
    MAX(CASE WHEN lb.type = 'L' THEN lb.backup_finish_date END)                        AS last_log_backup,
    MAX(CASE WHEN lb.type = 'L' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                        AS log_backup_age_hours,
    CASE
        WHEN MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END) IS NULL
            THEN 'NO_FULL_BACKUP'
        WHEN MAX(CASE WHEN lb.type = 'D' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) > 25
            THEN 'STALE_FULL'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND MAX(CASE WHEN lb.type = 'L' THEN lb.backup_finish_date END) IS NULL
            THEN 'FULL_RECOVERY_NO_LOG'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND MAX(CASE WHEN lb.type = 'L' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) > 4
            THEN 'STALE_LOG'
        ELSE 'OK'
    END                                                                                 AS backup_status
FROM sys.databases AS d
LEFT JOIN latest_backups AS lb
    ON d.name = lb.database_name
   AND lb.rn  = 1
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY
    CASE WHEN MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END) IS NULL THEN 0
         ELSE 1 END,
    MAX(CASE WHEN lb.type = 'D' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) DESC;
```

## How to run it from the repo

```powershell
# Table output sorted worst-first
.\run.ps1 Get-BackupCoverage

# Save as CSV — useful for daily review or emailing to the team
.\run.ps1 Get-BackupCoverage -OutputFormat Csv

# Against a named instance
.\run.ps1 Get-BackupCoverage -ServerInstance MYSERVER\INST01 -OutputFormat Csv
```

## Reading the output

| Column | What it means |
|--------|---------------|
| `database_name` | User database name |
| `recovery_model_desc` | FULL, BULK_LOGGED, or SIMPLE |
| `last_full_backup` | When the most recent full backup finished |
| `full_backup_age_hours` | How many hours ago that was |
| `full_backup_size_mb` | Size of the last full backup in MB |
| `last_diff_backup` | Most recent differential backup (if any) |
| `last_log_backup` | Most recent log backup (FULL/BULK_LOGGED databases only) |
| `log_backup_age_hours` | How many hours since the last log backup |
| `backup_status` | One of: `OK`, `NO_FULL_BACKUP`, `STALE_FULL`, `FULL_RECOVERY_NO_LOG`, `STALE_LOG` |

The `backup_status` column is the one to filter on. The result set is ordered worst-first: databases with `NO_FULL_BACKUP` come first, then `STALE_FULL` by age descending, so the most urgent problems are at the top.

## What each status flag means

**`NO_FULL_BACKUP`** — No full backup record exists in msdb for this database. Either the database was never backed up, or the msdb backup history has been purged. Either way: take a backup now and investigate why it's missing.

**`STALE_FULL`** — The last full backup completed more than 25 hours ago. The 25-hour threshold gives daily backup jobs a one-hour grace window for delayed starts. If you run weekly full backups, adjust the threshold to 170 hours in the script.

**`FULL_RECOVERY_NO_LOG`** — This database is in FULL or BULK_LOGGED recovery model but has never had a log backup. This is dangerous: the transaction log will grow continuously until it fills the disk, and you have no point-in-time recovery capability. Either add log backups or switch to SIMPLE recovery if point-in-time isn't needed.

**`STALE_LOG`** — FULL/BULK_LOGGED database with no log backup in the last 4 hours. The 4-hour threshold assumes hourly log backups; adjust if your schedule differs.

**`OK`** — All checks passed for this database.

## What to do when you find problems

For `NO_FULL_BACKUP` and `STALE_FULL`: check whether the database is included in your backup job, verify the job ran, check the SQL Agent job history (`Get-SqlAgentJobFailureSummary`), and take a manual backup if needed.

For `FULL_RECOVERY_NO_LOG`: this is a design issue. Decide whether the database actually needs point-in-time recovery. If yes, add a log backup job (every 15–60 minutes is typical). If no, switch the database to SIMPLE recovery and the transaction log will auto-truncate.

## Note on msdb backup history retention

This script reads from `msdb.dbo.backupset`. SQL Server's msdb cleanup job (`sysmaintplan_log_cleanup` or the maintenance plan cleanup task) may purge old history. On servers with aggressive cleanup policies, a database might look like it has `NO_FULL_BACKUP` simply because the history was deleted. Cross-check against actual backup files on disk if you're unsure.

## Related scripts in this repo

- [`Get-LastDatabaseBackupTimes.sql`](../sql/backups/Get-LastDatabaseBackupTimes.sql) — simpler view of last backup per type without the status flag
- [`Get-DatabaseBackupHistory.sql`](../sql/backups/Get-DatabaseBackupHistory.sql) — full backup history over the last 2 months, useful for trending
- [`Get-SqlAgentJobFailureSummary.sql`](../sql/monitoring/Get-SqlAgentJobFailureSummary.sql) — if backups are failing, start here

## Get the scripts

The full scripts are available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/backups/Get-BackupCoverage.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/backups/Get-BackupCoverage.sql)
- [`powershell/backup-automation/Get-BackupCoverage.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/backup-automation/Get-BackupCoverage.ps1)

---

## SEO

**Focus keyphrase:** SQL Server backup coverage

**Meta description** (158 chars — target 150–160):  
Audit SQL Server backup coverage across all databases in one query. Spot missing backups, stale full backups, and FULL recovery databases without log backups.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `backup-coverage-output.png` | SQL Server backup coverage query results showing backup_status flag with NO_FULL_BACKUP and STALE_LOG databases highlighted | SQL Server backup coverage query output |
