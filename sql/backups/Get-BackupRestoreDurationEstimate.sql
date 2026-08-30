/*
Script Name : Get-BackupRestoreDurationEstimate
Category    : backups-and-recovery
Purpose     : Analyze backup duration and throughput metrics from msdb for performance baseline.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-restore-duration-estimate/)
Requires    : db_datareader on msdb
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    bs.database_name,
    CAST(MAX(bs.backup_size / 1024.0 / 1024) AS DECIMAL(18,2)) AS backup_size_mb,
    MAX(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)) AS duration_seconds,
    CAST(MAX(bs.backup_size / 1024.0 / 1024
            / NULLIF(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date), 0))
        AS DECIMAL(18,2)) AS mb_per_second
FROM msdb.dbo.backupset AS bs
GROUP BY bs.database_name
ORDER BY backup_size_mb DESC;



