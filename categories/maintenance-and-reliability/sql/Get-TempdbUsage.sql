/*
Script Name : Get-TempdbUsage
Description : Returns Tempdb Usage for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Review TempDB file sizes and usage for capacity and contention checks.
-- Helpful during performance incidents and growth planning.

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




