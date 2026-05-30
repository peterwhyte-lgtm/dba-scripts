/*
Script Name : Get-SlowQueriesFromCache
Category    : performance-troubleshooting
Purpose     : Top 20 queries by average elapsed time from the plan cache — identifies habitually slow queries.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
Notes       : Covers cached plans since last restart or plan eviction. Complements
              Get-LongRunningQueries (live requests) and Get-TopCpuQueries (total CPU).
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT TOP 20
    DB_NAME(st.dbid)                                                        AS database_name,
    qs.execution_count,
    CAST(qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000.0
         AS DECIMAL(12,1))                                                  AS avg_elapsed_ms,
    CAST(qs.max_elapsed_time / 1000.0 AS DECIMAL(12,1))                    AS max_elapsed_ms,
    CAST(qs.total_elapsed_time        / 1000.0 AS DECIMAL(14,1))           AS total_elapsed_ms,
    CAST(qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000.0
         AS DECIMAL(12,1))                                                  AS avg_cpu_ms,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0)                 AS avg_logical_reads,
    qs.creation_time                                                        AS plan_cached,
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
              WHEN -1 THEN DATALENGTH(st.text)
              ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1
    )                                                                       AS statement_text
FROM sys.dm_exec_query_stats  AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE qs.execution_count > 1
ORDER BY qs.total_elapsed_time / NULLIF(qs.execution_count, 0) DESC;
