/*
Script Name : Get-DatabaseSizesAndFreeSpace
Category    : storage-capacity-management
Purpose     : Show data and log file sizes with free space for all online user databases.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH file_stats AS (
    SELECT
        d.name                                                                          AS database_name,
        SUM(CASE WHEN mf.type_desc = 'ROWS'
            THEN mf.size END) * 8.0 / 1024                                             AS data_size_mb,
        SUM(CASE WHEN mf.type_desc = 'LOG'
            THEN mf.size END) * 8.0 / 1024                                             AS log_size_mb,
        SUM(CASE WHEN mf.type_desc = 'ROWS'
            THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024       AS data_free_mb,
        SUM(CASE WHEN mf.type_desc = 'LOG'
            THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024       AS log_free_mb
    FROM sys.databases    AS d
    JOIN sys.master_files AS mf ON d.database_id = mf.database_id
    WHERE d.database_id > 4
      AND d.state_desc   = 'ONLINE'
    GROUP BY d.name
)
SELECT
    database_name,
    CAST(ROUND(data_size_mb, 1) AS DECIMAL(18,1))                                      AS data_size_mb,
    CAST(ROUND(log_size_mb,  1) AS DECIMAL(18,1))                                      AS log_size_mb,
    CAST(ROUND(data_free_mb, 1) AS DECIMAL(18,1))                                      AS data_free_mb,
    CAST(ROUND(log_free_mb,  1) AS DECIMAL(18,1))                                      AS log_free_mb,
    CAST(ROUND(CASE WHEN data_size_mb > 0
        THEN 100.0 * data_free_mb / data_size_mb ELSE NULL END, 1) AS DECIMAL(5,1))   AS data_free_pct,
    CAST(ROUND(CASE WHEN log_size_mb > 0
        THEN 100.0 * log_free_mb  / log_size_mb  ELSE NULL END, 1) AS DECIMAL(5,1))   AS log_free_pct
FROM file_stats
ORDER BY data_size_mb + log_size_mb DESC;
