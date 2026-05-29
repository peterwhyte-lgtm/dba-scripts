-- TempDB health and hotspot summary.
-- Helps identify large tempdb consumers and growth pressure.

SET NOCOUNT ON;

SELECT
    DB_NAME(tsu.database_id) AS database_name,
    tsu.user_objects_alloc_page_count,
    tsu.user_objects_dealloc_page_count,
    tsu.internal_objects_alloc_page_count,
    tsu.internal_objects_dealloc_page_count,
    tsu.version_store_alloc_page_count,
    tsu.version_store_dealloc_page_count,
    tsu.unallocated_extent_page_count,
    tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count + tsu.version_store_alloc_page_count AS total_alloc_pages
FROM sys.dm_db_task_space_usage tsu
ORDER BY total_alloc_pages DESC;

PRINT '--- TempDB file sizes ---';

SELECT
    name,
    physical_name,
    size / 128.0 AS size_mb,
    growth / 128.0 AS growth_mb,
    is_percent_growth,
    max_size / 128.0 AS max_size_mb
FROM tempdb.sys.database_files
ORDER BY size_mb DESC;
