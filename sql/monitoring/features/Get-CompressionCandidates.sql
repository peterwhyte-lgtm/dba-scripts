/*
Script Name : Get-CompressionCandidates
Category    : monitoring
Purpose     : Largest uncompressed tables and heaps in the current database, ordered by reserved space — identifies the best candidates for row or page compression.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-compression-candidates/)
Requires    : VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-compression-candidates/
-- SAFE:ReadOnly
-- IMPACT:Low
-- SCOPE:CurrentDatabase
SET NOCOUNT ON;

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    i.type_desc AS index_type,
    p.data_compression_desc AS current_compression,
    CAST(SUM(ps.reserved_page_count) * 8.0 / 1024 AS DECIMAL(10,2)) AS reserved_mb,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(10,2)) AS used_mb,
    SUM(ps.row_count) AS row_count,
    COUNT(DISTINCT p.partition_number) AS partition_count
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.indexes i ON i.object_id = t.object_id
                            AND i.type IN (0, 1) /* heaps (0) and clustered indexes (1) only */
JOIN sys.partitions p ON p.object_id = i.object_id
                            AND p.index_id = i.index_id
JOIN sys.dm_db_partition_stats ps
                            ON ps.object_id = t.object_id
                            AND ps.index_id = i.index_id
                            AND ps.partition_number = p.partition_number
WHERE p.data_compression_desc = 'NONE'
GROUP BY s.name, t.name, i.type_desc, p.data_compression_desc
ORDER BY reserved_mb DESC;
