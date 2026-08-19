/*
Script Name : Get-QueryStoreRegressions
Category    : performance
Purpose     : Queries that regressed in the last 24 hours vs their 7-day average CPU/duration.
              Uses Query Store time-bucketed runtime stats to detect "what changed today"
              — queries running >2x slower or using >2x more CPU than their recent baseline.
              Run in the context of the target database (-Database <dbname>).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-store-regressions-and-forced-plans/)
Requires    : VIEW DATABASE STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @regression_factor DECIMAL(5,2) = 2.0;
DECLARE @min_executions INT = 5;
DECLARE @recent_hours INT = 24;
DECLARE @baseline_days INT = 7;

IF ISNULL((SELECT actual_state_desc FROM sys.database_query_store_options), 'OFF')
   NOT IN ('READ_WRITE', 'READ_ONLY')
BEGIN
    SELECT
        DB_NAME() AS current_database,
        ISNULL((SELECT actual_state_desc FROM sys.database_query_store_options), 'OFF') AS query_store_status,
        'Enable: ALTER DATABASE [' + DB_NAME() + '] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE)' AS action;
END
ELSE
BEGIN
    WITH recent_window AS (
        SELECT
            p.query_id,
            SUM(rs.count_executions) AS exec_count,
            AVG(rs.avg_cpu_time) / 1000.0 AS avg_cpu_ms,
            AVG(rs.avg_duration) / 1000.0 AS avg_duration_ms,
            AVG(rs.avg_logical_io_reads) AS avg_logical_reads,
            MAX(rs.max_cpu_time) / 1000.0 AS max_cpu_ms
        FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_runtime_stats_interval AS ri ON ri.runtime_stats_interval_id = rs.runtime_stats_interval_id
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
        WHERE ri.start_time >= DATEADD(HOUR, -@recent_hours, GETUTCDATE())
          AND p.is_forced_plan = 0
        GROUP BY p.query_id
        HAVING SUM(rs.count_executions) >= @min_executions
    ),
    baseline_window AS (
        SELECT
            p.query_id,
            SUM(rs.count_executions) AS exec_count,
            AVG(rs.avg_cpu_time) / 1000.0 AS avg_cpu_ms,
            AVG(rs.avg_duration) / 1000.0 AS avg_duration_ms,
            AVG(rs.avg_logical_io_reads) AS avg_logical_reads
        FROM sys.query_store_runtime_stats AS rs
        JOIN sys.query_store_runtime_stats_interval AS ri ON ri.runtime_stats_interval_id = rs.runtime_stats_interval_id
        JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
        WHERE ri.start_time >= DATEADD(DAY, -@baseline_days, GETUTCDATE())
          AND ri.start_time < DATEADD(HOUR, -@recent_hours, GETUTCDATE())
        GROUP BY p.query_id
        HAVING SUM(rs.count_executions) >= @min_executions
    ),
    -- Materialise results so ORDER BY can reference aliases
    regressed AS (
        SELECT
            rw.query_id,
            OBJECT_NAME(q.object_id) AS object_name,
            CAST(rw.avg_cpu_ms AS DECIMAL(10,2)) AS recent_avg_cpu_ms,
            CAST(rw.avg_duration_ms AS DECIMAL(10,2)) AS recent_avg_duration_ms,
            CAST(rw.avg_logical_reads AS DECIMAL(10,0)) AS recent_avg_logical_reads,
            rw.exec_count AS recent_exec_count,
            CAST(bw.avg_cpu_ms AS DECIMAL(10,2)) AS baseline_avg_cpu_ms,
            CAST(bw.avg_duration_ms AS DECIMAL(10,2)) AS baseline_avg_duration_ms,
            CAST(bw.avg_logical_reads AS DECIMAL(10,0)) AS baseline_avg_logical_reads,
            bw.exec_count AS baseline_exec_count,
            CAST(rw.avg_cpu_ms / NULLIF(bw.avg_cpu_ms, 0) AS DECIMAL(6,2)) AS cpu_regression_factor,
            CAST(rw.avg_duration_ms / NULLIF(bw.avg_duration_ms, 0) AS DECIMAL(6,2)) AS duration_regression_factor,
            (SELECT COUNT(DISTINCT plan_id) FROM sys.query_store_plan
             WHERE query_id = rw.query_id) AS total_plan_count,
            CASE
                WHEN rw.avg_cpu_ms > bw.avg_cpu_ms * (@regression_factor * 2)
                THEN 'CRITICAL - CPU ' +
                     CAST(CAST(rw.avg_cpu_ms / NULLIF(bw.avg_cpu_ms, 0) AS INT) AS VARCHAR) +
                     'x baseline; likely plan regression or stats change'
                WHEN rw.avg_duration_ms > bw.avg_duration_ms * (@regression_factor * 2)
                THEN 'CRITICAL - duration ' +
                     CAST(CAST(rw.avg_duration_ms / NULLIF(bw.avg_duration_ms, 0) AS INT) AS VARCHAR) +
                     'x baseline'
                WHEN rw.avg_cpu_ms > bw.avg_cpu_ms * @regression_factor
                THEN 'WARN - CPU ' +
                     CAST(CAST(rw.avg_cpu_ms / NULLIF(bw.avg_cpu_ms, 0) AS DECIMAL(4,1)) AS VARCHAR) +
                     'x baseline'
                WHEN rw.avg_duration_ms > bw.avg_duration_ms * @regression_factor
                THEN 'WARN - duration ' +
                     CAST(CAST(rw.avg_duration_ms / NULLIF(bw.avg_duration_ms, 0) AS DECIMAL(4,1)) AS VARCHAR) +
                     'x baseline'
                ELSE 'INFO'
            END AS regression_status,
            LEFT(qt.query_sql_text, 400) AS query_text
        FROM recent_window AS rw
        JOIN baseline_window AS bw ON bw.query_id = rw.query_id
        JOIN sys.query_store_query AS q ON q.query_id = rw.query_id
        JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
        WHERE rw.avg_cpu_ms > bw.avg_cpu_ms * @regression_factor
           OR rw.avg_duration_ms > bw.avg_duration_ms * @regression_factor
    )
    SELECT *
    FROM regressed
    ORDER BY
        CASE WHEN regression_status LIKE 'CRITICAL%' THEN 1
             WHEN regression_status LIKE 'WARN%' THEN 2
             ELSE 3 END,
        cpu_regression_factor DESC;
END;
