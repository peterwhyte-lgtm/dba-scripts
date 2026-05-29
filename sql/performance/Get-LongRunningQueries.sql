/*
Script Name : Get-LongRunningQueries
Category    : performance-troubleshooting
Purpose     : Active requests with elapsed and wait details — ordered by elapsed time descending.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;

SELECT
    r.session_id,
    s.host_name,
    s.program_name,
    s.login_name,
    DB_NAME(r.database_id) AS database_name,
    r.status,
    r.command,
    r.cpu_time AS cpu_time_ms,
    r.total_elapsed_time / 1000.0 AS elapsed_time_seconds,
    r.reads,
    r.writes,
    r.logical_reads,
    r.wait_type,
    r.wait_time / 1000.0 AS wait_time_seconds,
    r.blocking_session_id,
    SUBSTRING(
        st.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
              WHEN -1 THEN DATALENGTH(st.text)
              ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    ) AS statement_text
FROM sys.dm_exec_requests r
INNER JOIN sys.dm_exec_sessions s
    ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;
