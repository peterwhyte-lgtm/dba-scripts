/*
Script Name : Get Detailed Database Backup History
Description : Returns Database Backup History for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

DECLARE @MonthsBack INT = 2;

SELECT
    bs.server_name,
    bs.database_name,
    bs.user_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    bs.type,
    bs.backup_size / 1024.0 / 1024 AS backup_size_mb,
    bs.recovery_model
FROM msdb.dbo.backupset AS bs
WHERE bs.backup_start_date >= DATEADD(MONTH, -@MonthsBack, GETDATE())
ORDER BY bs.backup_finish_date DESC;



