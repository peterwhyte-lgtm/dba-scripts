/*
Script Name : Get-ActiveRequestsWithPlan
Category    : diagnostics
Purpose     : Point-in-time snapshot of all active requests with XML execution
              plans. Same columns as Get-ActiveRequests.sql with the addition of
              query_plan from sys.dm_exec_query_plan. Use the PowerShell wrapper
              to extract plans to individual XML files for SSMS analysis.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    r.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id)                                                               AS database_name,
    r.status,
    r.wait_type,
    r.wait_time                                                                          AS wait_time_ms,
    r.blocking_session_id,
    r.cpu_time                                                                           AS cpu_time_ms,
    r.logical_reads,
    r.writes,
    r.total_elapsed_time                                                                 AS total_elapsed_time_ms,
    CAST(
        (ISNULL(su.user_objects_alloc_page_count,     0) +
         ISNULL(su.internal_objects_alloc_page_count, 0)) * 8
    AS BIGINT)                                                                           AS tempdb_allocations_kb,
    CAST(
        (ISNULL(su.user_objects_alloc_page_count,      0) - ISNULL(su.user_objects_dealloc_page_count,      0) +
         ISNULL(su.internal_objects_alloc_page_count,  0) - ISNULL(su.internal_objects_dealloc_page_count,  0)) * 8
    AS BIGINT)                                                                           AS tempdb_current_kb,
    SUBSTRING(
        ISNULL(qt.text, ''),
        (ISNULL(r.statement_start_offset, 0) / 2) + 1,
        CASE
            WHEN ISNULL(r.statement_end_offset, -1) = -1
                THEN LEN(ISNULL(qt.text, ''))
            ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1
        END
    )                                                                                    AS sql_text,
    CAST(qp.query_plan AS NVARCHAR(MAX))                                                 AS query_plan
FROM      sys.dm_exec_requests                      AS r
JOIN      sys.dm_exec_sessions                      AS s   ON s.session_id  = r.session_id
LEFT JOIN sys.dm_db_session_space_usage             AS su  ON su.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle)      AS qt
OUTER APPLY sys.dm_exec_query_plan(
    CASE WHEN r.plan_handle <> 0x0000000000000000000000000000000000000000
         THEN r.plan_handle END
)                                                   AS qp
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID
ORDER BY
    CASE
        WHEN EXISTS (SELECT 1 FROM sys.dm_exec_requests r2 WHERE r2.blocking_session_id = r.session_id)
            THEN 0  -- head blocker: blocking others, not blocked itself
        WHEN r.blocking_session_id > 0 THEN 1  -- victim: waiting on a blocker
        ELSE 2
    END,
    r.total_elapsed_time DESC;
