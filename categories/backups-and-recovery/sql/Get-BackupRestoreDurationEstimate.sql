/*
Script Name : Estimate Backup and Restore Completion Time
Description : Returns Backup Restore Duration Estimate for DBA review and troubleshooting.
Author      : Peter Whyte
*/

SELECT
    bs.database_name,
    MAX(bs.backup_size / 1024.0 / 1024) AS backup_size_mb,
    MAX(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)) AS duration_seconds,
    MAX(bs.backup_size / 1024.0 / 1024 / NULLIF(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date), 0)) AS mb_per_second
FROM msdb.dbo.backupset AS bs
GROUP BY bs.database_name
ORDER BY backup_size_mb DESC;



