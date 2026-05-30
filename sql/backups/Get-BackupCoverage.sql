/*
Script Name : Get-BackupCoverage
Category    : backups-and-recovery
Purpose     : Review backup coverage per database with a status flag for quick health assessment.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

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
