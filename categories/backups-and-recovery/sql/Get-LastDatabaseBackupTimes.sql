/*
Script Name : Show Last Backups on All Databases
Description : Returns Last Database Backup Times for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS last_differential_backup,
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS last_log_backup
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;



