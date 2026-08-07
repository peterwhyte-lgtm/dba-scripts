/*
Script Name : Get-TempDbFileBalance
Category    : monitoring
Purpose     : TempDB data file configuration — checks for size imbalance, growth mismatches, percent-based growth, and file count vs CPU count.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-temp-db-usage-and-file-balance/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-temp-db-usage-and-file-balance/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH files AS (
    SELECT
        file_id,
        type_desc,
        name AS file_name,
        physical_name,
        CAST(size * 8.0 / 1024 AS DECIMAL(10,1)) AS size_mb,
        CASE WHEN max_size = -1 THEN -1
             ELSE CAST(max_size * 8.0 / 1024 AS DECIMAL(10,1)) END AS max_size_mb,
        growth,
        is_percent_growth
    FROM sys.master_files
    WHERE database_id = 2
),
data_stats AS (
    SELECT
        COUNT(*) AS data_file_count,
        MIN(CASE WHEN type_desc = 'ROWS' THEN size_mb END) AS min_data_size_mb,
        MAX(CASE WHEN type_desc = 'ROWS' THEN size_mb END) AS max_data_size_mb,
        MIN(CASE WHEN type_desc = 'ROWS' THEN growth END) AS min_growth,
        MAX(CASE WHEN type_desc = 'ROWS' THEN growth END) AS max_growth,
        MAX(CASE WHEN type_desc = 'ROWS' AND is_percent_growth = 1
                 THEN 1 ELSE 0 END) AS any_pct_growth
    FROM files
    WHERE type_desc = 'ROWS'
),
cpu AS (
    SELECT
        cpu_count AS logical_cpus,
        CASE WHEN cpu_count >= 8 THEN 8 ELSE cpu_count END AS recommended_files
    FROM sys.dm_os_sys_info
)
SELECT
    f.type_desc AS file_type,
    f.file_id,
    f.file_name,
    f.physical_name,
    f.size_mb,
    CASE WHEN f.max_size_mb = -1 THEN 'Unlimited'
         ELSE CAST(f.max_size_mb AS VARCHAR(20)) + ' MB' END AS max_size,
    CASE WHEN f.is_percent_growth = 1
         THEN CAST(f.growth AS VARCHAR(10)) + '%'
         ELSE CAST(CAST(f.growth * 8.0 / 1024 AS DECIMAL(10,0)) AS VARCHAR(10)) + ' MB' END AS autogrowth,
    f.is_percent_growth,
    c.logical_cpus,
    c.recommended_files,
    s.data_file_count,
    CASE WHEN f.type_desc = 'ROWS' AND s.data_file_count < c.recommended_files THEN 'TOO_FEW'
         WHEN f.type_desc = 'ROWS' AND s.data_file_count > c.recommended_files THEN 'EXCESS'
         ELSE 'OK' END AS file_count_check,
    CASE WHEN f.type_desc = 'ROWS' AND s.min_data_size_mb <> s.max_data_size_mb THEN 'IMBALANCED'
         ELSE 'OK' END AS size_balance,
    CASE WHEN f.type_desc = 'ROWS' AND s.min_growth <> s.max_growth THEN 'IMBALANCED'
         WHEN f.type_desc = 'ROWS' AND s.any_pct_growth = 1 THEN 'PCT_GROWTH'
         ELSE 'OK' END AS growth_balance
FROM files f
CROSS JOIN data_stats s
CROSS JOIN cpu c
ORDER BY f.type_desc DESC, f.file_id;
