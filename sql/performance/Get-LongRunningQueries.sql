/*
Script Name : Get-LongRunningQueries
Category    : performance-troubleshooting
Purpose     : Identify long-running queries with current wait state, CPU, and elapsed time.
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
    r.status,
    r.cpu_time,
    r.total_elapsed_time,
    r.logical_reads,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    t.text AS current_statement
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.status <> 'sleeping'
ORDER BY r.total_elapsed_time DESC;




