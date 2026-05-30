/*
Script Name : Get-TransactionLogSizeAndUsage
Category    : storage-capacity-management
Purpose     : Show transaction log size, used space, free space, and percent used per database.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    d.name                                                                              AS database_name,
    d.recovery_model_desc,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG'
        THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,1))                              AS log_size_mb,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG'
        THEN FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 AS DECIMAL(18,1))  AS log_used_mb,
    CAST(SUM(CASE WHEN mf.type_desc = 'LOG'
        THEN mf.size - FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024
        AS DECIMAL(18,1))                                                               AS log_free_mb,
    CAST(100.0 *
        SUM(CASE WHEN mf.type_desc = 'LOG' THEN FILEPROPERTY(mf.name, 'SpaceUsed') END)
        / NULLIF(SUM(CASE WHEN mf.type_desc = 'LOG' THEN mf.size END), 0)
        AS DECIMAL(5,1))                                                                AS log_used_pct
FROM sys.master_files AS mf
JOIN sys.databases     AS d  ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY log_size_mb DESC;
