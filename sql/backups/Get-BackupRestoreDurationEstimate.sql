/*
Script Name : Get-BackupRestoreDurationEstimate
Category    : backups-and-recovery
Purpose     : Analyze backup duration and throughput metrics from msdb for performance baseline.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    bs.database_name,
    MAX(bs.backup_size / 1024.0 / 1024) AS backup_size_mb,
    MAX(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)) AS duration_seconds,
    MAX(bs.backup_size / 1024.0 / 1024 / NULLIF(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date), 0)) AS mb_per_second
FROM msdb.dbo.backupset AS bs
GROUP BY bs.database_name
ORDER BY backup_size_mb DESC;



