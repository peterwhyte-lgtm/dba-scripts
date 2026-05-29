/*
Script Name : Check Index Fragmentation Across All Databases
Description : Returns Index Fragmentation Across Databases for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SET NOCOUNT ON;

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
SELECT
    DB_NAME() AS database_name,
    s.name AS schema_name,
    o.name AS table_name,
    i.name AS index_name,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
JOIN sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.objects AS o ON i.object_id = o.object_id
JOIN sys.schemas AS s ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ips.alloc_unit_type_desc <> ''INTERNAL'';
';

EXEC sp_executesql @sql;



