/*
Script Name : Get-DuplicateIndexes
Category    : performance
Purpose     : Exact duplicate and overlapping (prefix) indexes across all user databases.
              Duplicates waste storage and double/triple write overhead for every DML
              operation. Overlapping indexes (A's key columns are a left-prefix of B's)
              usually mean B makes A redundant. Combines with usage stats to flag duplicates
              that are also unused — the highest priority to remove.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-duplicate-indexes/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

CREATE TABLE #idx (
    database_name SYSNAME,
    schema_name SYSNAME,
    table_name SYSNAME,
    index_id INT,
    index_name SYSNAME,
    index_type NVARCHAR(60),
    is_unique BIT,
    is_primary_key BIT,
    is_disabled BIT,
    key_columns NVARCHAR(MAX),
    included_columns NVARCHAR(MAX),
    user_seeks BIGINT,
    user_scans BIGINT,
    user_lookups BIGINT,
    user_updates BIGINT
);

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    INSERT INTO #idx
    SELECT
        N' + QUOTENAME(@db, N'''') + N',
        s.name,
        t.name,
        i.index_id,
        i.name,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        i.is_disabled,
        -- Key columns in ordinal order (excluding included columns)
        STUFF((
            SELECT '','' + c2.name
            FROM ' + QUOTENAME(@db) + N'.sys.index_columns ic2
            JOIN ' + QUOTENAME(@db) + N'.sys.columns c2
                ON c2.object_id = ic2.object_id AND c2.column_id = ic2.column_id
            WHERE ic2.object_id = i.object_id
              AND ic2.index_id = i.index_id
              AND ic2.is_included_column = 0
            ORDER BY ic2.key_ordinal
            FOR XML PATH(''''), TYPE
        ).value(''.'', ''NVARCHAR(MAX)''), 1, 1, ''''),
        -- Included columns (order-independent, alphabetical for comparison)
        STUFF((
            SELECT '','' + c3.name
            FROM ' + QUOTENAME(@db) + N'.sys.index_columns ic3
            JOIN ' + QUOTENAME(@db) + N'.sys.columns c3
                ON c3.object_id = ic3.object_id AND c3.column_id = ic3.column_id
            WHERE ic3.object_id = i.object_id
              AND ic3.index_id = i.index_id
              AND ic3.is_included_column = 1
            ORDER BY c3.name
            FOR XML PATH(''''), TYPE
        ).value(''.'', ''NVARCHAR(MAX)''), 1, 1, ''''),
        ISNULL(us.user_seeks, 0),
        ISNULL(us.user_scans, 0),
        ISNULL(us.user_lookups, 0),
        ISNULL(us.user_updates, 0)
    FROM ' + QUOTENAME(@db) + N'.sys.indexes i
    JOIN ' + QUOTENAME(@db) + N'.sys.tables t ON t.object_id = i.object_id
    JOIN ' + QUOTENAME(@db) + N'.sys.schemas s ON s.schema_id = t.schema_id
    LEFT JOIN sys.dm_db_index_usage_stats us
        ON us.database_id = DB_ID(N' + QUOTENAME(@db, N'''') + N')
        AND us.object_id = i.object_id
        AND us.index_id = i.index_id
    WHERE i.type IN (1, 2) -- clustered + nonclustered only
      AND t.is_ms_shipped = 0
      AND i.is_hypothetical = 0;';

    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Exact duplicates: same table, same key columns (order matters), different index
SELECT
    'EXACT_DUPLICATE' AS duplicate_type,
    a.database_name,
    a.schema_name,
    a.table_name,
    a.index_name AS index_a,
    a.index_type AS type_a,
    a.is_unique AS unique_a,
    a.is_primary_key AS pk_a,
    b.index_name AS index_b,
    b.index_type AS type_b,
    b.is_unique AS unique_b,
    b.is_primary_key AS pk_b,
    a.key_columns,
    a.included_columns AS included_a,
    b.included_columns AS included_b,
    a.user_seeks + a.user_scans + a.user_lookups AS reads_a,
    a.user_updates AS writes_a,
    b.user_seeks + b.user_scans + b.user_lookups AS reads_b,
    b.user_updates AS writes_b,
    CASE
        WHEN (a.user_seeks + a.user_scans + a.user_lookups = 0)
         AND (b.user_seeks + b.user_scans + b.user_lookups = 0)
        THEN 'DROP - both unused; keep the one that is a PK/unique constraint if applicable'
        WHEN (b.user_seeks + b.user_scans + b.user_lookups = 0)
         AND b.is_primary_key = 0
        THEN 'DROP index_b - unused duplicate; index_a is being used'
        WHEN (a.user_seeks + a.user_scans + a.user_lookups = 0)
         AND a.is_primary_key = 0
        THEN 'DROP index_a - unused duplicate; index_b is being used'
        ELSE 'REVIEW - both used; keep the one that enforces a constraint; DROP the other'
    END AS recommendation
FROM #idx AS a
JOIN #idx AS b
    ON b.database_name = a.database_name
    AND b.schema_name = a.schema_name
    AND b.table_name = a.table_name
    AND b.index_id > a.index_id
    AND b.key_columns = a.key_columns

UNION ALL

-- Overlapping: index_b's key columns are a left-prefix of index_a's key columns
-- (index_b is made redundant by index_a for seek purposes)
SELECT
    'PREFIX_OVERLAP',
    a.database_name,
    a.schema_name,
    a.table_name,
    a.index_name,
    a.index_type,
    a.is_unique,
    a.is_primary_key,
    b.index_name,
    b.index_type,
    b.is_unique,
    b.is_primary_key,
    'A keys: ' + a.key_columns + ' | B keys: ' + b.key_columns,
    a.included_columns,
    b.included_columns,
    a.user_seeks + a.user_scans + a.user_lookups,
    a.user_updates,
    b.user_seeks + b.user_scans + b.user_lookups,
    b.user_updates,
    CASE
        WHEN b.is_primary_key = 1 OR b.is_unique = 1
        THEN 'KEEP index_b - it enforces a constraint; consider expanding it to cover index_a''s columns'
        WHEN (b.user_seeks + b.user_scans + b.user_lookups = 0)
        THEN 'DROP index_b - unused and made redundant by the wider index_a'
        ELSE 'REVIEW - index_b is used but index_a covers its key columns; consider merging'
    END
FROM #idx AS a
JOIN #idx AS b
    ON b.database_name = a.database_name
    AND b.schema_name = a.schema_name
    AND b.table_name = a.table_name
    AND b.index_id <> a.index_id
    AND b.is_primary_key = 0
    -- B is a prefix of A: A's key list starts with B's key list followed by a comma
    AND a.key_columns LIKE b.key_columns + ',%'

ORDER BY
    database_name, schema_name, table_name, duplicate_type, index_a;

DROP TABLE #idx;
