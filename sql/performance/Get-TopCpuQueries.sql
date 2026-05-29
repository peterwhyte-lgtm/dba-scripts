/*
Script Name : Get-TopCpuQueries
Category    : performance-troubleshooting
Purpose     : List top 20 CPU-consuming queries with execution counts and timing metrics.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT TOP (20)
    DB_NAME(st.dbid) AS database_name,
    qs.execution_count,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000 AS avg_cpu_ms,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
              ((CASE qs.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset
                END - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
ORDER BY qs.total_worker_time DESC;



