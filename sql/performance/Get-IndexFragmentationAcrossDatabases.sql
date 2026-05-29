/*
Script Name : Get-IndexFragmentationAcrossDatabases
Category    : performance-troubleshooting
Purpose     : Check index fragmentation details across all user databases for maintenance planning.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Medium
Requires    : VIEW DATABASE STATE on each target database
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Medium — scans all user databases; run during off-peak hours on busy instances

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
SELECT
    DB_NAME() AS database_name,
    s.name AS schema_name,
    o.name AS table_name,
    i.name AS index_name,
    ROUND(ips.avg_fragmentation_in_percent, 2) AS avg_fragmentation_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') AS ips
INNER JOIN sys.indexes AS i
    ON ips.object_id = i.object_id
   AND ips.index_id = i.index_id
INNER JOIN sys.objects AS o
    ON i.object_id = o.object_id
INNER JOIN sys.schemas AS s
    ON o.schema_id = s.schema_id
WHERE o.is_ms_shipped = 0
  AND ips.page_count > 0
  AND ips.alloc_unit_type_desc <> ''INTERNAL''
  AND ips.avg_fragmentation_in_percent >= 5.0
ORDER BY ips.avg_fragmentation_in_percent DESC;
'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;

IF LEN(@sql) > 0
BEGIN
    EXEC sys.sp_executesql @sql;
END
ELSE
BEGIN
    PRINT 'No online user databases were found for fragmentation review.';
END



