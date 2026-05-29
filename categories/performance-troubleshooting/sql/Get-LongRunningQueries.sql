/*
Script Name : Get-LongRunningQueries
Description : Returns Long Running Queries for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Identify long-running queries and their current wait state
-- Run in SSMS or Azure Data Studio against the target instance.

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




