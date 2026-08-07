/*
Script Name : Get-StatisticsHealth
Category    : performance
Purpose     : Identifies stale, low-sample, and never-updated statistics in the current database.
              Returns the UPDATE STATISTICS command per row for direct copy-paste remediation.
              Run in the context of the target user database.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-statistics-health/)
Requires    : VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-statistics-health/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
-- SCOPE:CurrentDatabase
-- Fixes : the update_statement column contains the ready-to-run UPDATE STATISTICS command

DECLARE @show_all BIT = 0; -- 0 = stale / unhealthy only | 1 = all statistics
DECLARE @min_rows INT = 100; -- skip tables below this row count (reduces noise from tiny tables)
DECLARE @stale_days INT = 30; -- AGED threshold: flag stats not updated in this many days when
                                -- modification_counter > 0 (stats exist but are being ignored)

-- Dynamic update threshold (SQL 2016+ compat 130+): SQRT(1000 * rows)
-- Legacy threshold was 20% of row count — dynamic is more conservative on large tables.

WITH stats_health AS (
    SELECT
        OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,
        OBJECT_NAME(s.object_id) AS table_name,
        s.name AS stat_name,
        c.name AS leading_column,
        CASE
            WHEN s.auto_created = 0 AND s.user_created = 0 THEN 1
            ELSE 0
        END AS is_index_stat,
        s.auto_created,
        s.has_filter AS is_filtered,
        s.filter_definition,
        s.is_incremental,
        sp.rows,
        sp.rows_sampled,
        CAST(sp.rows_sampled * 100.0
             / NULLIF(sp.rows, 0) AS DECIMAL(5,1)) AS sample_pct,
        sp.modification_counter,
        CAST(sp.modification_counter * 100.0
             / NULLIF(sp.rows, 0) AS DECIMAL(5,1)) AS modification_pct,
        CAST(SQRT(1000.0 * NULLIF(sp.rows, 0)) AS BIGINT) AS dynamic_update_threshold,
        sp.last_updated,
        DATEDIFF(DAY, sp.last_updated, GETDATE()) AS days_since_update,
        CASE
            WHEN sp.last_updated IS NULL
                THEN 'NEVER_UPDATED'
            WHEN sp.modification_counter >= SQRT(1000.0 * NULLIF(sp.rows, 0))
                THEN 'STALE_THRESHOLD_MET'
            WHEN sp.rows > 10000
             AND sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) < 10
                THEN 'LOW_SAMPLE_RATE'
            WHEN sp.modification_counter * 100.0 / NULLIF(sp.rows, 0) > 10
                THEN 'APPROACHING_STALE'
            WHEN sp.modification_counter > 0
             AND DATEDIFF(DAY, sp.last_updated, GETDATE()) > @stale_days
                THEN 'AGED'
            ELSE 'OK'
        END AS health_status,
        'UPDATE STATISTICS ['
            + OBJECT_SCHEMA_NAME(s.object_id) + '].['
            + OBJECT_NAME(s.object_id) + '] ['
            + s.name + '] WITH FULLSCAN;' AS update_statement
    FROM sys.stats s
    OUTER APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
    JOIN sys.objects o
        ON s.object_id = o.object_id
        AND o.type = 'U'
    LEFT JOIN sys.stats_columns sc
        ON sc.object_id = s.object_id
        AND sc.stats_id = s.stats_id
        AND sc.stats_column_id = 1
    LEFT JOIN sys.columns c
        ON c.object_id = sc.object_id
        AND c.column_id = sc.column_id
    WHERE ISNULL(sp.rows, 0) >= @min_rows
)
SELECT
    schema_name,
    table_name,
    stat_name,
    leading_column,
    is_index_stat,
    auto_created,
    is_filtered,
    filter_definition,
    is_incremental,
    rows,
    rows_sampled,
    sample_pct,
    modification_counter,
    modification_pct,
    dynamic_update_threshold,
    last_updated,
    days_since_update,
    health_status,
    update_statement
FROM stats_health
WHERE @show_all = 1
   OR health_status <> 'OK'
ORDER BY
    CASE health_status
        WHEN 'NEVER_UPDATED' THEN 1
        WHEN 'STALE_THRESHOLD_MET' THEN 2
        WHEN 'LOW_SAMPLE_RATE' THEN 3
        WHEN 'APPROACHING_STALE' THEN 4
        WHEN 'AGED' THEN 5
        ELSE 6
    END,
    modification_counter DESC,
    schema_name,
    table_name;
