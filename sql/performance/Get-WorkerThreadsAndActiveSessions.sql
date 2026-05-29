/*
Script Name : Get-WorkerThreadsAndActiveSessions
Category    : performance-troubleshooting
Purpose     : Show current worker thread count and list active sessions with CPU and elapsed time.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    SUM(current_workers_count) AS current_worker_threads
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE';

SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    r.cpu_time,
    r.total_elapsed_time / 1000 AS elapsed_seconds
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r
    ON s.session_id = r.session_id
WHERE s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;



