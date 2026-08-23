/*
Script Name : Get-WorkerThreadsAndActiveSessions
Category    : performance-troubleshooting
Purpose     : Active user sessions with CPU, elapsed time, and current worker thread pool usage.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-worker-threads-and-active-sessions/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- Worker thread pool usage vs the configured maximum, alongside session/request counts.
-- A pool near max_worker_threads means THREADPOOL starvation is close.
SELECT
    (SELECT max_workers_count FROM sys.dm_os_sys_info)                       AS max_worker_threads,
    SUM(s.current_workers_count)                                            AS current_worker_threads,
    CAST(100.0 * SUM(s.current_workers_count)
         / NULLIF((SELECT max_workers_count FROM sys.dm_os_sys_info), 0)
         AS DECIMAL(5,1))                                                   AS pct_worker_threads_used,
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1)   AS user_sessions,
    (SELECT COUNT(*)
     FROM sys.dm_exec_requests r
     JOIN sys.dm_exec_sessions es ON r.session_id = es.session_id
     WHERE es.is_user_process = 1)                                          AS active_user_requests,
    (SELECT ISNULL(SUM(pending_disk_io_count), 0)
     FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE')             AS pending_disk_io
FROM sys.dm_os_schedulers s;
