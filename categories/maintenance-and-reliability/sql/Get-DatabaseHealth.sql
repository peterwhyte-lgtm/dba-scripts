/*
Script Name : Get-DatabaseHealth
Description : Returns a compact health summary for user databases.
Use        : Maintenance reviews, upgrade checks, and operational triage.
*/

SELECT
    d.name AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    d.user_access_desc,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    ROUND(CAST(SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)), 1) AS data_size_mb,
    ROUND(CAST(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)), 1) AS log_size_mb
FROM sys.databases AS d
LEFT JOIN sys.master_files AS mf
    ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY
    d.name,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    d.user_access_desc,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on
ORDER BY d.name;




