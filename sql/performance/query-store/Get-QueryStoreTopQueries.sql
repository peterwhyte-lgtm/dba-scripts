/*
Script Name : Get-QueryStoreTopQueries
Category    : performance
Purpose     : Top queries from Query Store by CPU, duration, execution count, or plan regressions.
              Change @sort_by at the top to switch modes. Must run in the context of the target
              database — change the database in SSMS or pass -Database <dbname> via the PS wrapper.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-store-top-queries/)
Requires    : VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-query-store-top-queries/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @top INT = 25;
DECLARE @hours INT = 24; -- look-back window in hours (0 = all history)
DECLARE @sort_by VARCHAR(20) = 'cpu'; -- cpu | duration | executions | regressions
DECLARE @min_executions INT = 5; -- filter queries with fewer executions (reduces noise)

-- Guard: return informational row if Query Store is not enabled on this database
IF ISNULL((SELECT actual_state_desc FROM sys.database_query_store_options), 'OFF')
   NOT IN ('READ_WRITE', 'READ_ONLY')
BEGIN
    SELECT
        DB_NAME() AS current_database,
        ISNULL(
            (SELECT actual_state_desc FROM sys.database_query_store_options),
            'OFF'
        ) AS query_store_status,
        'Enable: ALTER DATABASE [' + DB_NAME() + '] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE)' AS action;
END
ELSE
BEGIN
    WITH
    agg AS (
        SELECT
            q.query_id,
            OBJECT_NAME(q.object_id) AS object_name,
            LEFT(qt.query_sql_text, 500) AS query_text,
            p.plan_id,
            p.is_forced_plan,
            p.last_execution_time,
            SUM(rs.count_executions) AS execution_count,
            CAST(AVG(rs.avg_duration) / 1000.0 AS DECIMAL(14,2)) AS avg_duration_ms,
            CAST(MAX(rs.max_duration) / 1000.0 AS DECIMAL(14,2)) AS max_duration_ms,
            CAST(AVG(rs.avg_cpu_time) / 1000.0 AS DECIMAL(14,2)) AS avg_cpu_ms,
            CAST(MAX(rs.max_cpu_time) / 1000.0 AS DECIMAL(14,2)) AS max_cpu_ms,
            CAST(AVG(rs.avg_logical_io_reads) AS DECIMAL(14,2)) AS avg_logical_reads,
            CAST(AVG(rs.avg_rowcount) AS DECIMAL(14,2)) AS avg_rows,
            COUNT(*) OVER (PARTITION BY q.query_id) AS plan_count
        FROM sys.query_store_runtime_stats rs
        JOIN sys.query_store_runtime_stats_interval ri ON rs.runtime_stats_interval_id = ri.runtime_stats_interval_id
        JOIN sys.query_store_plan p ON rs.plan_id = p.plan_id
        JOIN sys.query_store_query q ON p.query_id = q.query_id
        JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
        WHERE (@hours = 0 OR ri.start_time >= DATEADD(HOUR, -@hours, GETUTCDATE()))
          AND q.is_internal_query = 0
        GROUP BY
            q.query_id, q.object_id, qt.query_sql_text,
            p.plan_id, p.is_forced_plan, p.last_execution_time
    ),
    with_best AS (
        -- Attach the best avg_cpu_ms seen for this query across all its plans
        SELECT
            a.*,
            MIN(a.avg_cpu_ms) OVER (PARTITION BY a.query_id) AS best_avg_cpu_ms
        FROM agg a
    ),
    latest_plan AS (
        -- For each query keep only its most-recently-used plan; compute regression factor
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY query_id ORDER BY last_execution_time DESC) AS plan_rank,
            CAST(
                CASE WHEN best_avg_cpu_ms > 0
                     THEN avg_cpu_ms / best_avg_cpu_ms
                     ELSE 1.0
                END AS DECIMAL(10,2)
            ) AS cpu_regression_factor
        FROM with_best
    )
    SELECT TOP (@top)
        lp.query_id,
        lp.plan_id,
        lp.object_name,
        lp.plan_count,
        lp.avg_cpu_ms,
        lp.max_cpu_ms,
        lp.avg_duration_ms,
        lp.max_duration_ms,
        lp.execution_count,
        lp.avg_logical_reads,
        lp.avg_rows,
        lp.is_forced_plan,
        lp.cpu_regression_factor,
        CASE
            WHEN lp.cpu_regression_factor > 2.0 AND lp.plan_count > 1 THEN 'REGRESSED'
            WHEN lp.is_forced_plan = 1 THEN 'PLAN_FORCED'
            WHEN lp.plan_count > 1 THEN 'MULTI_PLAN'
            ELSE 'OK'
        END AS plan_status,
        lp.last_execution_time,
        lp.query_text
    FROM latest_plan lp
    WHERE lp.plan_rank = 1
      AND lp.execution_count >= @min_executions
      AND (
            @sort_by <> 'regressions'
            OR (lp.plan_count > 1 AND lp.cpu_regression_factor > 1.5)
          )
    ORDER BY
        CASE @sort_by
            WHEN 'cpu' THEN lp.avg_cpu_ms
            WHEN 'duration' THEN lp.avg_duration_ms
            WHEN 'executions' THEN CAST(lp.execution_count AS DECIMAL(14,2))
            WHEN 'regressions' THEN lp.cpu_regression_factor
            ELSE lp.avg_cpu_ms
        END DESC;
END;
