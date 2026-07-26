/*
Script Name : Get-DatabaseSizesAndFreeSpace
Category    : storage-capacity-management
Purpose     : Data and log file sizes with used and free space for all online user databases.
              Uses dynamic SQL so FILEPROPERTY runs inside each database's own context,
              where it correctly reports allocated vs used pages.
              The original CTE approach querying sys.master_files from master caused
              FILEPROPERTY to return NULL for other databases' files.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/)
Requires    : VIEW ANY DATABASE
HealthCheck : Yes
*/
-- Blog: https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #sizes (
    database_name  sysname        NOT NULL,
    data_size_mb   DECIMAL(18,1)  NOT NULL,
    data_used_mb   DECIMAL(18,1)  NOT NULL,
    log_size_mb    DECIMAL(18,1)  NOT NULL,
    log_used_mb    DECIMAL(18,1)  NOT NULL
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #sizes (database_name, data_size_mb, data_used_mb, log_size_mb, log_used_mb)
SELECT
    DB_NAME(),
    CAST(ROUND(SUM(CASE WHEN type = 0 THEN size * 8.0 / 1024 ELSE 0 END), 1) AS DECIMAL(18,1)),
    CAST(ROUND(SUM(CASE WHEN type = 0
        THEN ISNULL(FILEPROPERTY(name, ''SpaceUsed''), size) * 8.0 / 1024
        ELSE 0 END), 1) AS DECIMAL(18,1)),
    CAST(ROUND(SUM(CASE WHEN type = 1 THEN size * 8.0 / 1024 ELSE 0 END), 1) AS DECIMAL(18,1)),
    CAST(ROUND(SUM(CASE WHEN type = 1
        THEN ISNULL(FILEPROPERTY(name, ''SpaceUsed''), size) * 8.0 / 1024
        ELSE 0 END), 1) AS DECIMAL(18,1))
FROM sys.database_files;
'
FROM sys.databases
WHERE state_desc  = 'ONLINE'
  AND database_id > 4;

IF LEN(@sql) > 0
    EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    data_size_mb,
    CAST(ROUND(data_size_mb - data_used_mb, 1) AS DECIMAL(18,1))                   AS data_free_mb,
    CAST(ROUND(CASE WHEN data_size_mb > 0
        THEN 100.0 * (data_size_mb - data_used_mb) / data_size_mb
        ELSE NULL END, 1) AS DECIMAL(5,1))                                          AS data_free_pct,
    log_size_mb,
    CAST(ROUND(log_size_mb - log_used_mb, 1) AS DECIMAL(18,1))                     AS log_free_mb,
    CAST(ROUND(CASE WHEN log_size_mb > 0
        THEN 100.0 * (log_size_mb - log_used_mb) / log_size_mb
        ELSE NULL END, 1) AS DECIMAL(5,1))                                          AS log_free_pct
FROM   #sizes
ORDER BY data_size_mb + log_size_mb DESC;

DROP TABLE #sizes;
