/*
Script Name : Get-TempdbUsage
Category    : maintenance-and-reliability
Purpose     : Show TempDB file sizes, free space, and allocation breakdown per file.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    df.file_id,
    df.name                                                                 AS logical_name,
    df.type_desc                                                            AS file_type,
    df.physical_name,
    CAST(df.size * 8.0 / 1024 AS DECIMAL(10,2))                           AS size_mb,
    CASE df.max_size
        WHEN -1 THEN NULL
        ELSE CAST(df.max_size * 8.0 / 1024 AS DECIMAL(10,2))
    END                                                                     AS max_size_mb,
    CASE df.is_percent_growth
        WHEN 1 THEN CAST(df.growth AS VARCHAR(10)) + '%'
        ELSE        CAST(CAST(df.growth * 8.0 / 1024 AS INT) AS VARCHAR(20)) + ' MB'
    END                                                                     AS auto_growth,
    CAST(fs.unallocated_extent_page_count * 8.0 / 1024 AS DECIMAL(10,2))  AS free_mb,
    CAST((df.size - fs.unallocated_extent_page_count) * 8.0 / 1024
         AS DECIMAL(10,2))                                                  AS used_mb,
    CAST(fs.user_object_reserved_page_count * 8.0 / 1024 AS DECIMAL(10,2))    AS user_objects_mb,
    CAST(fs.internal_object_reserved_page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS internal_objects_mb,
    CAST(fs.version_store_reserved_page_count * 8.0 / 1024 AS DECIMAL(10,2))  AS version_store_mb,
    CAST(100.0 * (df.size - fs.unallocated_extent_page_count) / NULLIF(df.size, 0)
         AS DECIMAL(5,2))                                                   AS pct_used
FROM tempdb.sys.database_files          AS df
LEFT JOIN tempdb.sys.dm_db_file_space_usage AS fs ON df.file_id = fs.file_id
ORDER BY df.type, df.file_id;
