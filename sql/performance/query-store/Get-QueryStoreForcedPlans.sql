/*
Script Name : Get-QueryStoreForcedPlans
Category    : performance
Purpose     : Forced plans in Query Store with failure counts, plan age, forcing reason,
              and whether the forced plan is still the cheapest available option.
              A force_failure_count > 0 means QS is silently reverting to natural plans —
              queries you think are protected are not.
              Run in the context of the target database (-Database <dbname>).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-store-regressions-and-forced-plans/)
Requires    : VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-query-store-regressions-and-forced-plans/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

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
    WITH forced AS (
        SELECT
            p.query_id,
            p.plan_id AS forced_plan_id,
            p.force_failure_count,
            p.last_force_failure_reason_desc,
            p.plan_forcing_type_desc,
            p.last_execution_time,
            p.initial_compile_start_time AS plan_created,
            DATEDIFF(DAY, p.initial_compile_start_time, GETDATE()) AS plan_age_days,
            AVG(rs.avg_cpu_time) / 1000.0 AS forced_avg_cpu_ms,
            SUM(rs.count_executions) AS forced_exec_count
        FROM sys.query_store_plan AS p
        JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
        WHERE p.is_forced_plan = 1
        GROUP BY
            p.query_id, p.plan_id, p.force_failure_count,
            p.last_force_failure_reason_desc, p.plan_forcing_type_desc,
            p.last_execution_time, p.initial_compile_start_time
    ),
    best_plan AS (
        SELECT
            p.query_id,
            MIN(rs_agg.avg_cpu_ms) AS best_avg_cpu_ms
        FROM sys.query_store_plan AS p
        JOIN (
            SELECT plan_id, AVG(avg_cpu_time) / 1000.0 AS avg_cpu_ms
            FROM sys.query_store_runtime_stats
            GROUP BY plan_id
        ) AS rs_agg ON rs_agg.plan_id = p.plan_id
        GROUP BY p.query_id
    ),
    results AS (
        SELECT
            f.query_id,
            f.forced_plan_id,
            OBJECT_NAME(q.object_id) AS object_name,
            LEFT(qt.query_sql_text, 400) AS query_text,
            f.plan_forcing_type_desc,
            f.plan_age_days,
            f.force_failure_count,
            f.last_force_failure_reason_desc,
            f.last_execution_time,
            CAST(f.forced_avg_cpu_ms AS DECIMAL(10,2)) AS forced_avg_cpu_ms,
            CAST(bp.best_avg_cpu_ms AS DECIMAL(10,2)) AS best_available_avg_cpu_ms,
            CASE
                WHEN bp.best_avg_cpu_ms < f.forced_avg_cpu_ms * 0.8
                THEN CAST(CAST(100.0 * (f.forced_avg_cpu_ms - bp.best_avg_cpu_ms)
                         / NULLIF(bp.best_avg_cpu_ms, 0) AS INT) AS VARCHAR) +
                     '% cheaper plan available — consider unforcing and testing'
                ELSE 'OK — forced plan remains competitive'
            END AS plan_quality,
            CASE
                WHEN f.force_failure_count > 0
                THEN 'CRITICAL — force is FAILING (' + CAST(f.force_failure_count AS VARCHAR) +
                     ' failures, reason: ' + f.last_force_failure_reason_desc +
                     '); query is running without the forced plan'
                WHEN f.plan_age_days > 180
                THEN 'WARN — plan forced > 6 months ago; re-evaluate whether force is still needed'
                WHEN bp.best_avg_cpu_ms < f.forced_avg_cpu_ms * 0.8
                THEN 'WARN — cheaper plan now exists in QS; forced plan may be holding back performance'
                ELSE 'OK'
            END AS status
        FROM forced AS f
        JOIN sys.query_store_query AS q ON q.query_id = f.query_id
        JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
        JOIN best_plan AS bp ON bp.query_id = f.query_id
    )
    SELECT *
    FROM results
    ORDER BY
        CASE WHEN status LIKE 'CRITICAL%' THEN 1
             WHEN status LIKE 'WARN%' THEN 2
             ELSE 3 END,
        force_failure_count DESC,
        plan_age_days DESC;
END;
