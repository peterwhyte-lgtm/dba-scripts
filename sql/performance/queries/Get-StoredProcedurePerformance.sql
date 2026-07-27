/*
Script Name : Get-StoredProcedurePerformance
Category    : performance
Purpose     : Stored procedures from the plan cache ranked by total elapsed time — shows execution count, average and max duration, CPU, and logical reads. Resets on SQL Server restart or plan eviction.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT TOP 50
    DB_NAME(ps.database_id)                                             AS database_name,
    OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)                  AS schema_name,
    OBJECT_NAME(ps.object_id, ps.database_id)                         AS proc_name,
    ps.execution_count,
    ps.total_elapsed_time   / 1000 / ps.execution_count               AS avg_ms,
    ps.max_elapsed_time     / 1000                                     AS max_ms,
    ps.min_elapsed_time     / 1000                                     AS min_ms,
    ps.total_worker_time    / 1000 / ps.execution_count               AS avg_cpu_ms,
    ps.total_logical_reads        / ps.execution_count                 AS avg_logical_reads,
    ps.total_logical_writes       / ps.execution_count                 AS avg_logical_writes,
    ps.total_physical_reads       / ps.execution_count                 AS avg_physical_reads,
    /* Raw totals for sorting */
    ps.total_elapsed_time   / 1000                                     AS total_elapsed_ms,
    ps.total_worker_time    / 1000                                     AS total_cpu_ms,
    CONVERT(VARCHAR(16), ps.last_execution_time, 120)                  AS last_execution_at,
    CONVERT(VARCHAR(16), ps.cached_time,         120)                  AS plan_cached_at
FROM sys.dm_exec_procedure_stats ps
WHERE ps.database_id > 4                /* user databases only */
  AND OBJECT_NAME(ps.object_id, ps.database_id) IS NOT NULL
ORDER BY ps.total_elapsed_time DESC;
