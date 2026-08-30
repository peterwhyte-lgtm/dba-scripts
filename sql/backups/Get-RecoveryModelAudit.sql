/*
Script Name : Get-RecoveryModelAudit
Category    : backups-and-recovery
Purpose     : Audits each database's recovery model against its actual backup posture and
              flags the mismatches that cause real incidents: FULL/BULK_LOGGED databases
              with no log backups (the log grows until the disk fills), databases with no
              full backup to anchor a log chain, and SIMPLE databases where someone may be
              expecting point-in-time recovery they do not have.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-recovery-model-audit/)
Requires    : VIEW ANY DATABASE, db_datareader on msdb
Notes       : "Accidental FULL" is the classic finding — a database left in FULL recovery
              with no log backup job. It runs fine for months, then the log fills the drive.
              Run Get-LogReuseWaits and Get-TransactionLogSizeAndUsage alongside this to see
              the live effect. Thresholds below are defaults; adjust to your backup SLA.

              WHERE THIS GOES BLIND. Every date here comes from msdb.dbo.backupset on THIS
              instance, so a CRITICAL is evidence of missing local history, which is usually
              but not always a missing backup job. Confirm against one of these before
              raising it:
                - Availability Groups: backup history is instance-local. Backups taken on
                  another replica leave no row here.
                - Purged history: sp_delete_backuphistory or a maintenance-plan cleanup task
                  trims backupset, so a young instance-restart or an aggressive retention
                  setting can empty this out.
                - Snapshot backups that bypass the SQL backup path: VM or storage-array
                  snapshots taken without VSS/VDI integration never write a backupset row.
                  (Most third-party tools — Veeam application-aware, Commvault, LiteSpeed,
                  Redgate — go through VDI and DO appear here.)
                - Renamed databases: backupset records the name at backup time, so history
                  stays behind under the old name and the database reads as never backed up.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @LogBackupStaleHours INT = 24;
DECLARE @FullBackupStaleDays INT = 7;

;WITH FullBackup AS
(
    /* Copy-only fulls are deliberately COUNTED here. A copy-only full backup is a valid
       restore base and log backups can be applied on top of it, so it genuinely does let
       a log chain start. (What it does not do is reset the differential base, which is a
       different question this script does not ask.) Filtering it out here would raise a
       false CRITICAL against a database that is in fact restorable. */
    SELECT database_name, MAX(backup_finish_date) AS last_full_backup
    FROM msdb.dbo.backupset
    WHERE type = 'D'
    GROUP BY database_name
),
LogBackup AS
(
    /* Copy-only log backups are EXCLUDED, and this one matters. A copy-only log backup
       preserves the log archive point and does not truncate the log, so counting it as
       evidence the log is being managed inverts the finding this script exists to make:
       one copy-only log backup would downgrade a genuine "log will grow until the disk
       fills" CRITICAL to a mild staleness warning while the log kept growing. */
    SELECT database_name, MAX(backup_finish_date) AS last_log_backup
    FROM msdb.dbo.backupset
    WHERE type = 'L'
      AND is_copy_only = 0
    GROUP BY database_name
)

SELECT
    d.name AS database_name,
    d.recovery_model_desc AS recovery_model,
    fb.last_full_backup,
    lb.last_log_backup,
    CAST(SUM(CAST(mf.size AS BIGINT)) * 8.0 / 1024
        AS DECIMAL(18,1)) AS log_size_mb,
    CASE
        -- FULL / BULK_LOGGED: the log only truncates when a log backup runs.
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED') AND fb.last_full_backup IS NULL
            THEN 'CRITICAL: no full backup, log backup chain cannot start'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED') AND lb.last_log_backup IS NULL
            THEN 'CRITICAL: ' + d.recovery_model_desc + ' recovery with no log backups, log will grow until the disk fills'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
             AND DATEDIFF(HOUR, lb.last_log_backup, GETDATE()) > @LogBackupStaleHours
            THEN 'WARNING: log backups are stale (>' + CAST(@LogBackupStaleHours AS VARCHAR(10)) + 'h)'
        WHEN fb.last_full_backup IS NULL
            THEN 'WARNING: no full backup on record'
        WHEN DATEDIFF(DAY, fb.last_full_backup, GETDATE()) > @FullBackupStaleDays
            THEN 'WARNING: full backup is stale (>' + CAST(@FullBackupStaleDays AS VARCHAR(10)) + 'd)'
        WHEN d.recovery_model_desc = 'SIMPLE'
            THEN 'INFO: SIMPLE - no point-in-time recovery between full/diff backups'
        ELSE 'OK'
    END AS finding
FROM sys.databases AS d
JOIN sys.master_files AS mf
    ON mf.database_id = d.database_id
    AND mf.type_desc = 'LOG'
LEFT JOIN FullBackup AS fb
    ON fb.database_name = d.name
LEFT JOIN LogBackup AS lb
    ON lb.database_name = d.name
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4
GROUP BY
    d.name,
    d.recovery_model_desc,
    fb.last_full_backup,
    lb.last_log_backup
ORDER BY
    CASE
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED') AND lb.last_log_backup IS NULL THEN 0
        WHEN fb.last_full_backup IS NULL THEN 1
        ELSE 2
    END,
    d.name;
