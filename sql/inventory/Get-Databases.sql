/*
Script Name : Get-Databases
Category    : monitoring
Purpose     : Lists all databases with key properties and allocated file sizes.
              Reads from system metadata only — fast, no per-database scan.
              Data and log sizes reflect allocated file space, not space used.
              Run Get-DatabaseSizesAndFreeSpace for used vs free breakdown.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/)
Requires    : VIEW ANY DATABASE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    d.name                                                                          AS database_name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc                                                           AS recovery_model,
    d.compatibility_level,
    CAST(d.create_date AS DATE)                                                     AS create_date,
    SUSER_SNAME(d.owner_sid) COLLATE DATABASE_DEFAULT                               AS owner,
    CASE d.is_auto_shrink_on WHEN 1 THEN 'YES' ELSE 'NO' END                       AS auto_shrink,
    CASE d.is_auto_close_on  WHEN 1 THEN 'YES' ELSE 'NO' END                       AS auto_close,
    CAST(ROUND(SUM(CASE WHEN mf.type = 0 THEN mf.size * 8.0 / 1024 ELSE 0 END), 1)
         AS DECIMAL(18,1))                                                          AS data_size_mb,
    CAST(ROUND(SUM(CASE WHEN mf.type = 1 THEN mf.size * 8.0 / 1024 ELSE 0 END), 1)
         AS DECIMAL(18,1))                                                          AS log_size_mb,
    CAST(ROUND(SUM(mf.size * 8.0 / 1024), 1)
         AS DECIMAL(18,1))                                                          AS total_size_mb
FROM sys.databases d
LEFT JOIN sys.master_files mf ON d.database_id = mf.database_id
GROUP BY
    d.name, d.database_id, d.state_desc, d.recovery_model_desc,
    d.compatibility_level, d.create_date, d.owner_sid,
    d.is_auto_shrink_on, d.is_auto_close_on
ORDER BY total_size_mb DESC;
