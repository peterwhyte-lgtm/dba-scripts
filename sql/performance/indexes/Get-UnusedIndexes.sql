/*
Script Name : Get-UnusedIndexes
Category    : performance
Purpose     : Identifies indexes with zero read activity but non-zero write overhead
              since the last SQL Server restart. These indexes slow every INSERT,
              UPDATE, and DELETE on the table without benefiting any query.
              Run in the context of the database you want to audit.
              SCOPE: the filter is type_desc <> 'HEAP', so CLUSTERED indexes are
              included as well as non-clustered. Read the type_desc column before
              acting on drop_statement: DROP INDEX against a clustered index is valid
              T-SQL and converts the table to a heap.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-unused-indexes/)
Requires    : VIEW SERVER STATE, VIEW DATABASE STATE
Notes       : Usage stats reset on SQL Server restart, so run only after several days
              of representative workload to avoid false positives.
              Do NOT drop without checking all environments. A zero-read index on
              PROD may be critical for a month-end report or a rarely-run job.
              PKs and unique constraints are excluded (structural, cannot be dropped).
              Review write_count vs total_reads ratio. Drop candidates: write_count
              high, total_reads = 0, and size_mb large.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
-- SCOPE:CurrentDatabase

SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc,
    i.is_unique,
    ISNULL(s.user_seeks, 0) AS seeks,
    ISNULL(s.user_scans, 0) AS scans,
    ISNULL(s.user_lookups, 0) AS lookups,
    ISNULL(s.user_seeks,0) + ISNULL(s.user_scans,0)
        + ISNULL(s.user_lookups,0) AS total_reads,
    ISNULL(s.user_updates, 0) AS write_count,
    ISNULL(p.rows, 0) AS table_rows,
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10,2)) AS size_mb,
    'DROP INDEX ' + QUOTENAME(i.name)
        + ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(i.object_id))
        + '.' + QUOTENAME(OBJECT_NAME(i.object_id)) + ';' AS drop_statement
FROM sys.indexes i
JOIN sys.tables t
    ON i.object_id = t.object_id
JOIN sys.partitions p
    ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a
    ON p.partition_id = a.container_id
LEFT JOIN sys.dm_db_index_usage_stats s
    ON s.object_id = i.object_id
    AND s.index_id = i.index_id
    AND s.database_id = DB_ID()
WHERE i.type_desc <> 'HEAP'
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND t.is_ms_shipped = 0
  AND ISNULL(s.user_seeks,0) + ISNULL(s.user_scans,0) + ISNULL(s.user_lookups,0) = 0
  AND ISNULL(s.user_updates, 0) > 0
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, i.is_unique,
         s.user_seeks, s.user_scans, s.user_lookups, s.user_updates, p.rows
ORDER BY write_count DESC, size_mb DESC;
