/*
Script Name : Get-DatabaseFilesDetail
Category    : storage-capacity-management
Purpose     : Show per-file details for all user databases: path, size, max size, growth settings.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    d.name                                                             AS database_name,
    d.state_desc                                                       AS db_state,
    d.recovery_model_desc                                              AS recovery_model,
    mf.file_id,
    mf.name                                                            AS logical_name,
    mf.type_desc                                                       AS file_type,
    LEFT(mf.physical_name, 1)                                         AS drive_letter,
    mf.physical_name                                                   AS physical_path,
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2))                      AS current_size_mb,
    CASE mf.max_size
        WHEN -1 THEN NULL
        WHEN  0 THEN CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2))
        ELSE        CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(12,2))
    END                                                                AS max_size_mb,
    CASE mf.is_percent_growth
        WHEN 1 THEN CAST(mf.growth AS VARCHAR(10)) + '%'
        ELSE        CAST(CAST(mf.growth * 8.0 / 1024 AS INT) AS VARCHAR(20)) + ' MB'
    END                                                                AS auto_growth,
    mf.is_percent_growth                                               AS growth_is_percent,
    mf.state_desc                                                      AS file_state
FROM sys.master_files  AS mf
INNER JOIN sys.databases AS d ON d.database_id = mf.database_id
WHERE d.database_id > 4
ORDER BY d.name, mf.type, mf.file_id;
