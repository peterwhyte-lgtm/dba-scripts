/*
Script Name : Check Backup Coverage Across All Databases
Description : Returns Backup Coverage for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

WITH BackupHistory AS
(
    SELECT
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.type,
        ROW_NUMBER() OVER (PARTITION BY bs.database_name, bs.type ORDER BY bs.backup_finish_date DESC) AS rn
    FROM msdb.dbo.backupset AS bs
)
SELECT
    d.name AS database_name,
    MAX(CASE WHEN bh.type = 'D' THEN bh.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN bh.type = 'I' THEN bh.backup_finish_date END) AS last_diff_backup,
    MAX(CASE WHEN bh.type = 'L' THEN bh.backup_finish_date END) AS last_log_backup
FROM sys.databases AS d
LEFT JOIN BackupHistory AS bh
    ON d.name = bh.database_name
   AND bh.rn = 1
GROUP BY d.name
ORDER BY d.name;



