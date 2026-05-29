/*
Script Name : Get-DatabaseHealth
Description : Returns Database Health for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Quick production health check for a database
SELECT
    DB_NAME() AS DatabaseName,
    CAST(SUM(CASE WHEN type_desc = 'ROWS' THEN size END) * 8. / 1024 AS DECIMAL(10,2)) AS DataSizeGB,
    CAST(SUM(CASE WHEN type_desc = 'LOG' THEN size END) * 8. / 1024 AS DECIMAL(10,2)) AS LogSizeGB,
    MAX(CASE WHEN name = 'log_reuse_wait_desc' THEN value END) AS LogReuseWait,
    MAX(CASE WHEN name = 'recovery_model_desc' THEN value END) AS RecoveryModel
FROM sys.database_files;

SELECT
    name,
    state_desc,
    user_access_desc,
    is_read_only,
    is_auto_close_on,
    recovery_model_desc
FROM sys.databases
WHERE database_id > 4;




