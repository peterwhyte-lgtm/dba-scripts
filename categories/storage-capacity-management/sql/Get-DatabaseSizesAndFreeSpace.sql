/*
Script Name : Get-DatabaseSizesAndFreeSpace
Description : Returns database size and free-space details for all online user databases.
Use        : Capacity planning, growth reviews, and storage reporting.
*/

SET NOCOUNT ON;

;WITH file_stats AS (
    SELECT
        d.name AS database_name,
        SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size END) * 8.0 / 1024 AS data_size_mb,
        SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END) * 8.0 / 1024 AS log_size_mb,
        SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 AS data_free_mb,
        SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 AS log_free_mb
    FROM sys.databases AS d
    INNER JOIN sys.master_files AS mf
        ON d.database_id = mf.database_id
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE'
    GROUP BY d.name
)
SELECT
    database_name,
    ROUND(data_size_mb, 1) AS data_size_mb,
    ROUND(log_size_mb, 1) AS log_size_mb,
    ROUND(data_free_mb, 1) AS data_free_mb,
    ROUND(log_free_mb, 1) AS log_free_mb,
    ROUND(CASE WHEN data_size_mb > 0 THEN 100.0 * data_free_mb / data_size_mb ELSE NULL END, 2) AS data_free_percent,
    ROUND(CASE WHEN log_size_mb > 0 THEN 100.0 * log_free_mb / log_size_mb ELSE NULL END, 2) AS log_free_percent
FROM file_stats
ORDER BY data_size_mb + log_size_mb DESC;




