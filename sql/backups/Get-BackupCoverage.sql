/*
Script Name : Get-BackupCoverage
Category    : backups-and-recovery
Purpose     : Review backup coverage per database with a status flag for quick health assessment.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-coverage/)
Requires    : VIEW ANY DATABASE, db_datareader on msdb
HealthCheck : Yes
Notes       : This is the DAILY OPERATIONS check: it assumes a nightly full and frequent log
              backups, so its thresholds are deliberately tighter than Get-RecoveryModelAudit,
              which asks the slower question of whether a database is CONFIGURED sanely.
              The same instance can therefore be "stale" here and not there. That is intended;
              adjust the two variables below to your own backup SLA rather than assuming the
              defaults describe your shop.

              Only ONLINE databases are reported. An offline database cannot be backed up, and
              including it produced a NO_FULL_BACKUP row that sorted to the top of the report.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @FullBackupStaleHours INT = 25;  -- a nightly job plus roughly an hour of grace
DECLARE @LogBackupStaleHours  INT = 4;   -- assumes log backups at least every few hours

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
    /* Copy-only LOG backups are excluded: they preserve the log archive point and do not
       truncate the log, so counting one would suppress FULL_RECOVERY_NO_LOG and STALE_LOG
       and report OK against a log that is still growing without bound. Copy-only FULL
       backups are deliberately kept, because a copy-only full is a valid restore base. */
    WHERE bs.type <> 'L' OR bs.is_copy_only = 0
),
coverage AS (
    SELECT
        d.name                                                                  AS database_name,
        d.recovery_model_desc,
        MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END)             AS last_full_backup,
        MAX(CASE WHEN lb.type = 'D' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                AS full_backup_age_hours,
        MAX(CASE WHEN lb.type = 'D' THEN lb.backup_size_mb END)                 AS full_backup_size_mb,
        MAX(CASE WHEN lb.type = 'I' THEN lb.backup_finish_date END)             AS last_diff_backup,
        MAX(CASE WHEN lb.type = 'I' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                AS diff_backup_age_hours,
        MAX(CASE WHEN lb.type = 'L' THEN lb.backup_finish_date END)             AS last_log_backup,
        MAX(CASE WHEN lb.type = 'L' THEN DATEDIFF(HOUR, lb.backup_finish_date, GETDATE()) END)
                                                                                AS log_backup_age_hours
    FROM sys.databases AS d
    LEFT JOIN latest_backups AS lb
        ON d.name = lb.database_name
       AND lb.rn  = 1
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE'
    GROUP BY d.name, d.recovery_model_desc
),
/*
  SEVERITY ORDER. Ranked, then the rank drives both the status text and the sort, so the
  report cannot claim to be worst-first while sorting on something else.

  FULL_RECOVERY_NO_LOG sits ABOVE STALE_FULL deliberately. Ranking stale-full higher meant a
  database in FULL recovery that had never had a log backup, but whose nightly full had merely
  run late, reported STALE_FULL — which reads as "the job was slow" when the real finding is a
  log growing without bound. That is the accidental-FULL incident, mislabelled. This ordering
  matches Get-RecoveryModelAudit so the two scripts cannot disagree about the same database.
*/
ranked AS (
    SELECT c.*,
        CASE
            WHEN c.last_full_backup IS NULL                             THEN 1
            WHEN c.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
             AND c.last_log_backup IS NULL                              THEN 2
            WHEN c.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
             AND c.log_backup_age_hours > @LogBackupStaleHours          THEN 3
            WHEN c.full_backup_age_hours > @FullBackupStaleHours        THEN 4
            ELSE 5
        END AS severity
    FROM coverage AS c
)
SELECT
    database_name,
    recovery_model_desc,
    last_full_backup,
    full_backup_age_hours,
    full_backup_size_mb,
    last_diff_backup,
    diff_backup_age_hours,
    last_log_backup,
    log_backup_age_hours,
    CASE severity
        WHEN 1 THEN 'NO_FULL_BACKUP'
        WHEN 2 THEN 'FULL_RECOVERY_NO_LOG'
        WHEN 3 THEN 'STALE_LOG'
        WHEN 4 THEN 'STALE_FULL'
        ELSE        'OK'
    END AS backup_status
FROM ranked
ORDER BY severity, full_backup_age_hours DESC, database_name;
