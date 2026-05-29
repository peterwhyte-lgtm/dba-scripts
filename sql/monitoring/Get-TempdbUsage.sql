/*
Script Name : Get-TempdbUsage
Category    : maintenance-and-reliability
Purpose     : Review TempDB file sizes and usage for capacity checks and contention analysis.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    name,
    physical_name,
    size / 128 AS size_mb,
    max_size / 128 AS max_size_mb,
    growth / 128 AS growth_mb,
    is_percent_growth
FROM tempdb.sys.database_files;

SELECT
    SUM(user_object_reserved_page_count) * 8 AS user_object_mb,
    SUM(internal_object_reserved_page_count) * 8 AS internal_object_mb,
    SUM(version_store_reserved_page_count) * 8 AS version_store_mb
FROM tempdb.sys.dm_db_file_space_usage;





