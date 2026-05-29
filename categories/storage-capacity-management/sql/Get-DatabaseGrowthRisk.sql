-- DBA growth-risk summary for storage and capacity planning.
-- Useful for weekly reviews, migrations, and capacity trend checks.

SET NOCOUNT ON;

;WITH db_sizes AS (
    SELECT
        d.name AS database_name,
        CAST(SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS data_mb,
        CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS log_mb,
        CAST(SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) +
        CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS total_mb,
        CAST(SUM(CASE WHEN mf.max_size = -1 THEN 0 ELSE mf.max_size * 8.0 / 1024 END) AS DECIMAL(18,2)) AS growth_limit_mb
    FROM sys.databases d
    LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
    GROUP BY d.name
)
SELECT
    database_name,
    data_mb,
    log_mb,
    total_mb,
    growth_limit_mb,
    CASE
        WHEN growth_limit_mb = 0 THEN 'UNLIMITED'
        WHEN total_mb >= growth_limit_mb THEN 'AT_LIMIT'
        WHEN total_mb >= growth_limit_mb * 0.85 THEN 'NEAR_LIMIT'
        ELSE 'OK'
    END AS growth_status
FROM db_sizes
WHERE database_name NOT IN ('master', 'model', 'msdb', 'tempdb')
ORDER BY total_mb DESC;
