/*
Script Name : Get-TableSizes
Category    : performance
Purpose     : Largest tables across all online user databases by total size (data + index).
              Essential for getting to know a new instance — identifies the major data consumers
              and tables most likely to impact I/O, backup times, and index maintenance windows.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-table-sizes/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @top_per_db INT = 20;  -- top N tables per database

CREATE TABLE #table_sizes (
    database_name    SYSNAME,
    schema_name      SYSNAME,
    table_name       SYSNAME,
    row_count        BIGINT,
    data_size_mb     DECIMAL(12,2),
    index_size_mb    DECIMAL(12,2),
    total_size_mb    DECIMAL(12,2),
    has_heap         BIT
);

DECLARE @db   SYSNAME;
DECLARE @sql  NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  database_id > 4
      AND  state = 0
      AND  user_access = 0;  -- MULTI_USER only

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #table_sizes
        SELECT TOP (' + CAST(@top_per_db AS NVARCHAR(10)) + N')
            N' + QUOTENAME(@db, N'''') + N',
            s.name,
            t.name,
            -- row_count only from the heap/clustered partitions, or every index recounts the rows
            SUM(CASE WHEN ps.index_id <= 1 THEN ps.row_count ELSE 0 END),
            -- data = in-row + LOB + row-overflow pages of the heap/clustered index (sp_spaceused style)
            CAST(SUM(CASE WHEN ps.index_id <= 1
                          THEN ps.in_row_data_page_count + ps.lob_used_page_count
                               + ps.row_overflow_used_page_count
                          ELSE 0 END) * 8.0 / 1024 AS DECIMAL(12,2)),
            -- index = everything else that is in use, including nonclustered indexes
            CAST((SUM(ps.used_page_count)
                  - SUM(CASE WHEN ps.index_id <= 1
                             THEN ps.in_row_data_page_count + ps.lob_used_page_count
                                  + ps.row_overflow_used_page_count
                             ELSE 0 END)) * 8.0 / 1024 AS DECIMAL(12,2)),
            CAST(SUM(ps.reserved_page_count) * 8.0 / 1024 AS DECIMAL(12,2)),
            MAX(CASE WHEN i.type = 0 THEN 1 ELSE 0 END)
        FROM ' + QUOTENAME(@db) + N'.sys.dm_db_partition_stats ps
        JOIN ' + QUOTENAME(@db) + N'.sys.tables  t ON t.object_id = ps.object_id
        JOIN ' + QUOTENAME(@db) + N'.sys.schemas s ON s.schema_id = t.schema_id
        JOIN ' + QUOTENAME(@db) + N'.sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
        WHERE t.is_ms_shipped = 0
        GROUP BY s.name, t.name
        ORDER BY SUM(ps.reserved_page_count) DESC;';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Skip databases that become unavailable mid-run
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    database_name,
    schema_name,
    table_name,
    row_count,
    data_size_mb,
    index_size_mb,
    total_size_mb,
    CASE has_heap WHEN 1 THEN 'Yes — no clustered index' ELSE 'No' END AS is_heap
FROM #table_sizes
ORDER BY total_size_mb DESC;

DROP TABLE #table_sizes;
