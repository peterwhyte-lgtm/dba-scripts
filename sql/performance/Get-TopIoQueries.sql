/*
Script Name : Get-TopIoQueries
Category    : performance-troubleshooting
Purpose     : Top 20 queries by total logical reads since last restart — primary I/O pressure source.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT TOP 20
    DB_NAME(st.dbid)                                                        AS database_name,
    qs.execution_count,
    qs.total_logical_reads,
    CAST(qs.total_logical_reads / NULLIF(qs.execution_count, 0)
         AS BIGINT)                                                         AS avg_logical_reads,
    qs.total_physical_reads,
    CAST(qs.total_physical_reads / NULLIF(qs.execution_count, 0)
         AS BIGINT)                                                         AS avg_physical_reads,
    qs.total_logical_writes,
    CAST(qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000
         AS BIGINT)                                                         AS avg_cpu_ms,
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
ORDER BY qs.total_logical_reads DESC;
