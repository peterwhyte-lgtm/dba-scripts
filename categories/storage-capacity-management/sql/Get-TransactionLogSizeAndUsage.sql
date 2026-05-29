/*
Script Name : Transaction Log Size and Usage by Database
Description : Returns Transaction Log Size And Usage for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    d.name AS database_name,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END) * 8. / 1024 AS DECIMAL(18,2)) AS log_size_gb,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END) * 8. / 1024 -
         SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8. / 1024 AS DECIMAL(18,2)) AS log_used_gb,
    CAST(100.0 * SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) / NULLIF(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END), 0) AS DECIMAL(5,2)) AS log_used_percent
FROM sys.master_files AS mf
JOIN sys.databases AS d
    ON mf.database_id = d.database_id
GROUP BY d.name
ORDER BY log_size_gb DESC;



