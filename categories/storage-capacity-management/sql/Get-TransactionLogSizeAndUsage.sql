/*
Script Name : Transaction Log Size and Usage by Database
Description : Returns transaction log size, used space, and percent used for each database.
Use        : Log growth reviews, maintenance planning, and DR readiness checks.
*/

SELECT
    d.name AS database_name,
    ROUND(CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)), 1) AS log_size_mb,
    ROUND(CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 AS DECIMAL(18,2)), 1) AS log_used_mb,
    ROUND(CAST(100.0 * SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END)
        / NULLIF(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END), 0) AS DECIMAL(5,2)), 2) AS log_used_percent
FROM sys.master_files AS mf
INNER JOIN sys.databases AS d
    ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name
ORDER BY log_size_mb DESC;



