/*
Script Name : Get-BackupSizeTrend
Category    : backups
Purpose     : Monthly backup size trend per database over the last 12 months — an indirect proxy for data growth rate. Shrinking backups can indicate unexpected data loss; growing backups inform storage planning.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-size-trend/)
Requires    : msdb access (db_datareader on msdb or sysadmin)
*/
-- Blog: https://sqldba.blog/dba-scripts-get-backup-size-trend/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    database_name,
    CASE type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE type
    END                                                                 AS backup_type,
    CAST(YEAR(backup_finish_date) AS CHAR(4)) + '-' +
    RIGHT('0' + CAST(MONTH(backup_finish_date) AS VARCHAR(2)), 2)      AS year_month,
    COUNT(*)                                                            AS backup_count,
    CAST(AVG(backup_size)           / 1073741824.0 AS DECIMAL(10,3))   AS avg_size_gb,
    CAST(MAX(backup_size)           / 1073741824.0 AS DECIMAL(10,3))   AS max_size_gb,
    CAST(MIN(backup_size)           / 1073741824.0 AS DECIMAL(10,3))   AS min_size_gb,
    CAST(AVG(CASE WHEN compressed_backup_size > 0
                  THEN compressed_backup_size END)
                                    / 1073741824.0 AS DECIMAL(10,3))   AS avg_compressed_gb,
    CAST(AVG(CASE WHEN compressed_backup_size > 0 AND backup_size > 0
                  THEN CAST(compressed_backup_size AS FLOAT) / backup_size * 100
                  END) AS DECIMAL(5,1))                                AS avg_compression_pct
FROM msdb.dbo.backupset
WHERE backup_finish_date >= DATEADD(MONTH, -12, GETDATE())
  AND type IN ('D', 'I', 'L')
GROUP BY database_name, type, YEAR(backup_finish_date), MONTH(backup_finish_date)
ORDER BY database_name, backup_type, year_month;
