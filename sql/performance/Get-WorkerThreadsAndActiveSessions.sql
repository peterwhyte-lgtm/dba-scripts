/*
Script Name : Get-WorkerThreadsAndActiveSessions
Category    : performance-troubleshooting
Purpose     : Active user sessions with CPU, elapsed time, and current worker thread pool usage.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- Get SQL worker threads
SELECT 
    SUM(current_workers_count) AS current_worker_threads
FROM sys.dm_os_schedulers;
