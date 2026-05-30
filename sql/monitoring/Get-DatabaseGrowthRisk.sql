/*
Script Name : Get-DatabaseGrowthRisk
Category    : storage-capacity-management
Purpose     : Flag databases approaching their configured file size limits.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH db_sizes AS (
    SELECT
        d.name                                                                          AS database_name,
        CAST(SUM(CASE WHEN mf.type_desc = 'ROWS'
            THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2))                          AS data_mb,
        CAST(SUM(CASE WHEN mf.type_desc = 'LOG'
            THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2))                          AS log_mb,
        CAST(SUM(CASE WHEN mf.max_size = -1 THEN 0
            ELSE mf.max_size * 8.0 / 1024 END) AS DECIMAL(18,2))                      AS growth_limit_mb
    FROM sys.databases    AS d
    LEFT JOIN sys.master_files AS mf ON d.database_id = mf.database_id
    WHERE d.database_id > 4
    GROUP BY d.name
)
SELECT
    database_name,
    data_mb,
    log_mb,
    CAST(data_mb + log_mb AS DECIMAL(18,2))                                            AS total_mb,
    growth_limit_mb,
    CASE
        WHEN growth_limit_mb = 0                            THEN 'UNLIMITED'
        WHEN data_mb + log_mb >= growth_limit_mb            THEN 'AT_LIMIT'
        WHEN data_mb + log_mb >= growth_limit_mb * 0.85    THEN 'NEAR_LIMIT'
        ELSE                                                     'OK'
    END                                                                                 AS growth_status
FROM db_sizes
ORDER BY total_mb DESC;
