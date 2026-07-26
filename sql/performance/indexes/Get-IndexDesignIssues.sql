/*
Script Name : Get-IndexDesignIssues
Category    : performance
Purpose     : Tables with index design problems: excessive index count (write amplification),
              wide key columns (>900 bytes — approaching the 1700-byte row-store limit),
              and tables where Missing Index DMV has > 3 recommendations (optimizer giving up
              on existing index coverage). Complements Get-DuplicateIndexes.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-index-design-issues/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-index-design-issues/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #issues (
    database_name       SYSNAME,
    schema_name         SYSNAME,
    table_name          SYSNAME,
    issue_type          NVARCHAR(60),
    detail              NVARCHAR(500),
    metric_value        INT,
    status              NVARCHAR(400)
);

DECLARE @db  SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    -- Issue 1: Too many indexes per table (write amplification)
    INSERT INTO #issues
    SELECT
        N' + QUOTENAME(@db, N'''') + N',
        s.name,
        t.name,
        ''TOO_MANY_INDEXES'',
        CAST(COUNT(i.index_id) AS VARCHAR) + '' indexes on this table (> 20 harms INSERT/UPDATE/DELETE throughput)'',
        COUNT(i.index_id),
        CASE WHEN COUNT(i.index_id) > 30 THEN ''CRITICAL''
             WHEN COUNT(i.index_id) > 20 THEN ''WARN''
             ELSE ''INFO'' END
    FROM ' + QUOTENAME(@db) + N'.sys.indexes  i
    JOIN ' + QUOTENAME(@db) + N'.sys.tables   t ON t.object_id = i.object_id
    JOIN ' + QUOTENAME(@db) + N'.sys.schemas  s ON s.schema_id = t.schema_id
    WHERE i.type IN (1, 2) AND t.is_ms_shipped = 0 AND i.is_disabled = 0
    GROUP BY s.name, t.name
    HAVING COUNT(i.index_id) > 10;

    -- Issue 2: Wide key columns (row-store limit is 1700 bytes in SQL 2016+, 900 in older)
    INSERT INTO #issues
    SELECT
        N' + QUOTENAME(@db, N'''') + N',
        s.name,
        t.name,
        ''WIDE_KEY_COLUMNS'',
        i.name + '' — key width ~'' +
            CAST(SUM(CASE WHEN c.max_length = -1 THEN 900 ELSE c.max_length END) AS VARCHAR) +
            '' bytes (avoid keys > 900 bytes; > 1700 bytes will fail)'',
        SUM(CASE WHEN c.max_length = -1 THEN 900 ELSE c.max_length END),
        CASE
            WHEN SUM(CASE WHEN c.max_length = -1 THEN 900 ELSE c.max_length END) > 1700
            THEN ''CRITICAL''
            WHEN SUM(CASE WHEN c.max_length = -1 THEN 900 ELSE c.max_length END) > 900
            THEN ''WARN''
            ELSE ''INFO''
        END
    FROM ' + QUOTENAME(@db) + N'.sys.indexes         i
    JOIN ' + QUOTENAME(@db) + N'.sys.tables          t  ON t.object_id = i.object_id
    JOIN ' + QUOTENAME(@db) + N'.sys.schemas         s  ON s.schema_id = t.schema_id
    JOIN ' + QUOTENAME(@db) + N'.sys.index_columns   ic ON ic.object_id = i.object_id
                                AND ic.index_id = i.index_id
                                AND ic.is_included_column = 0
    JOIN ' + QUOTENAME(@db) + N'.sys.columns         c  ON c.object_id = ic.object_id
                                AND c.column_id = ic.column_id
    WHERE i.type IN (1, 2) AND t.is_ms_shipped = 0
    GROUP BY s.name, t.name, i.name
    HAVING SUM(CASE WHEN c.max_length = -1 THEN 900 ELSE c.max_length END) > 450;

    -- Issue 3: Tables with many Missing Index recommendations (index coverage severely lacking)
    INSERT INTO #issues
    SELECT
        N' + QUOTENAME(@db, N'''') + N',
        mi_details.schema_name,
        mi_details.table_name,
        ''MISSING_INDEX_FLOOD'',
        CAST(mi_details.missing_count AS VARCHAR) + '' missing index recommendations — index coverage likely poor; review before applying all'',
        mi_details.missing_count,
        CASE WHEN mi_details.missing_count >= 10 THEN ''WARN''
             ELSE ''INFO'' END
    FROM (
        SELECT
            OBJECT_SCHEMA_NAME(mid.object_id, DB_ID(N' + QUOTENAME(@db, N'''') + N'))  AS schema_name,
            OBJECT_NAME(mid.object_id, DB_ID(N' + QUOTENAME(@db, N'''') + N'))         AS table_name,
            COUNT(*) AS missing_count
        FROM sys.dm_db_missing_index_details mid
        WHERE mid.database_id = DB_ID(N' + QUOTENAME(@db, N'''') + N')
        GROUP BY mid.object_id
        HAVING COUNT(*) >= 5
    ) mi_details;';

    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    database_name,
    schema_name,
    table_name,
    issue_type,
    detail,
    metric_value,
    status
FROM #issues
ORDER BY
    CASE status WHEN 'CRITICAL' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END,
    database_name,
    schema_name,
    table_name,
    issue_type;

DROP TABLE #issues;
