/*
Script Name : Get-ImplicitConversions
Category    : performance
Purpose     : Scans the plan cache for implicit conversion warnings. These cause index range
              scans instead of seeks and generate unnecessary CPU. Most common cause: VARCHAR
              column compared to NVARCHAR parameter, or INT column compared to VARCHAR.
              NOTE: scans plan XML — runs for 10–30 seconds on busy servers with large plan caches.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-implicit-conversions/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Medium
SET NOCOUNT ON;

DECLARE @top INT = 50; -- reduce if plan cache is very large

SELECT TOP (@top)
    qs.total_logical_reads AS total_logical_reads,
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    CAST(qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000.0 AS DECIMAL(10,2)) AS avg_cpu_ms,
    DB_NAME(qt.dbid) AS database_name,
    OBJECT_NAME(qt.objectid, qt.dbid) AS object_name,
    LEFT(qt.text, 500) AS query_text,
    qs.creation_time AS plan_cached_at,
    -- Extract the first PlanAffectingConvert expression from the plan XML
    CAST(qp.query_plan AS NVARCHAR(MAX)) AS query_plan_xml
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%PlanAffectingConvert%'
  AND qt.dbid IS NOT NULL
  AND qt.dbid > 4
ORDER BY qs.total_logical_reads DESC;
