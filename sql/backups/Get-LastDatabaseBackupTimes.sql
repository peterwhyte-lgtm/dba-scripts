/*
Script Name : Get-LastDatabaseBackupTimes
Category    : backups-and-recovery
Purpose     : Display the latest backup timestamp per type (Full, Differential, Log) per database.
Author      : Peter Whyte (https://sqldba.blog/get-last-database-backup-times-in-sql-server/)
Requires    : db_datareader on msdb
HealthCheck : Yes
Notes       : last_log_backup means "the latest log backup that TRUNCATED the log", not simply
              the latest log backup: copy-only log backups are excluded (see the CTE below).
              That is the right signal for "is this log being managed", and it is deliberately
              not the same question as "is this database recoverable to a point in time" — a
              database whose only log backups are copy-only shows NULL here and still has
              restorable log records. Read it alongside Get-RecoveryModelAudit.

              Only ONLINE databases are reported: an offline database cannot be backed up, and
              including it produced a row that looked like a database with no backups at all.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH latest_backups AS (
    SELECT
        bs.database_name,
        bs.type,
        bs.backup_finish_date,
        CAST(bs.backup_size / 1024.0 / 1024 AS DECIMAL(18,2)) AS backup_size_mb,
        ROW_NUMBER() OVER (
            PARTITION BY bs.database_name, bs.type
            ORDER BY bs.backup_finish_date DESC
        ) AS rn
    FROM msdb.dbo.backupset AS bs
    /* Copy-only LOG backups are excluded, so last_log_backup means "latest log backup that
       truncated the log" rather than "latest log backup". Review-HealthCheckOutput.ps1 turns
       this column straight into the "log will grow unbounded" finding, and a copy-only log
       backup would make that finding vanish while the log kept growing. Copy-only FULL
       backups are kept: a copy-only full is a valid restore base. */
    WHERE bs.type <> 'L' OR bs.is_copy_only = 0
)
SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN lb.type = 'D' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) AS full_backup_age_hours,
    MAX(CASE WHEN lb.type = 'D' THEN lb.backup_size_mb END) AS full_backup_size_mb,
    MAX(CASE WHEN lb.type = 'I' THEN lb.backup_finish_date END) AS last_diff_backup,
    MAX(CASE WHEN lb.type = 'I' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) AS diff_backup_age_hours,
    MAX(CASE WHEN lb.type = 'L' THEN lb.backup_finish_date END) AS last_log_backup,
    MAX(CASE WHEN lb.type = 'L' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END) AS log_backup_age_hours
FROM sys.databases AS d
LEFT JOIN latest_backups AS lb
    ON d.name = lb.database_name
   AND lb.rn = 1
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;



