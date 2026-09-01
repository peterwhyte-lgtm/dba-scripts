/*
Script Name : Get-QueryStoreStatus
Category    : monitoring
Purpose     : Query Store enablement, fill ratio, capture mode, and health across all user databases.
              Surfaces databases where QS is off, full, or auto-switched to READ_ONLY.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-store-status/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #qs_status (
    database_name SYSNAME,
    db_state NVARCHAR(60),
    qs_state NVARCHAR(60),
    qs_desired_state NVARCHAR(60),
    capture_mode NVARCHAR(60),
    cleanup_mode NVARCHAR(60),
    current_storage_mb DECIMAL(10,2),
    max_storage_mb DECIMAL(10,2),
    fill_pct DECIMAL(5,1),
    stale_query_threshold_days INT,
    flush_interval_seconds INT,
    readonly_reason INT,
    status NVARCHAR(200)
);

DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state = 0
      AND compatibility_level >= 130; -- QS requires 2016+ compat

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #qs_status
        SELECT
            N' + QUOTENAME(@db, N'''') + N',
            N''' + (SELECT state_desc FROM sys.databases WHERE name = @db) + N''',
            actual_state_desc,
            desired_state_desc,
            query_capture_mode_desc,
            size_based_cleanup_mode_desc,
            CAST(current_storage_size_mb AS DECIMAL(10,2)),
            CAST(max_storage_size_mb AS DECIMAL(10,2)),
            CAST(100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5,1)),
            stale_query_threshold_days,
            flush_interval_seconds,
            readonly_reason,
            CASE
                WHEN actual_state_desc = ''OFF''
                    THEN ''WARN - Query Store not enabled''
                WHEN actual_state_desc = ''READ_ONLY'' AND readonly_reason <> 0
                    THEN ''WARN - auto-switched to READ_ONLY (check fill ratio)''
                WHEN 100.0 * current_storage_size_mb / NULLIF(max_storage_size_mb, 0) > 80
                    THEN ''WARN - fill > 80%; risk of auto READ_ONLY switch''
                WHEN desired_state_desc <> actual_state_desc
                    THEN ''WARN - desired/actual state mismatch''
                ELSE ''OK''
            END
        FROM ' + QUOTENAME(@db) + N'.sys.database_query_store_options;';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- QS catalog may not be visible if DB is inaccessible; skip silently
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Also surface user databases that are below compat 130 (QS not applicable)
INSERT INTO #qs_status (database_name, db_state, qs_state, status)
SELECT
    name,
    state_desc,
    'N/A',
    'INFO - compat level ' + CAST(compatibility_level AS VARCHAR(5)) + ' (< 130); Query Store not supported'
FROM sys.databases
WHERE database_id > 4
  AND state = 0
  AND compatibility_level < 130;

SELECT
    database_name,
    db_state,
    qs_state,
    qs_desired_state,
    capture_mode,
    cleanup_mode,
    current_storage_mb,
    max_storage_mb,
    fill_pct,
    stale_query_threshold_days,
    flush_interval_seconds,
    readonly_reason,
    status
FROM #qs_status
ORDER BY
    CASE WHEN status LIKE 'WARN%' THEN 1 WHEN status LIKE 'INFO%' THEN 2 ELSE 3 END,
    database_name;

DROP TABLE #qs_status;
