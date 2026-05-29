/*
Script Name : Get-BlockingSessions
Category    : performance-troubleshooting
Purpose     : Summarize current blocking sessions and blocked requests with wait types and timing.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time / 1000 AS wait_seconds,
    r.cpu_time,
    r.logical_reads,
    r.row_count,
    t.text AS current_statement
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND (r.blocking_session_id <> 0 OR r.wait_type IS NOT NULL)
ORDER BY r.wait_time DESC;




