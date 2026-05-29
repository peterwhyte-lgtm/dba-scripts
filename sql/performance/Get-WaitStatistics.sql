/*
Script Name : Get-WaitStatistics
Category    : performance-troubleshooting
Purpose     : Review instance wait statistics for performance triage.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE (or sysadmin for the full DMV view)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Top wait statistics for the current instance.
-- Useful for identifying bottlenecks during performance investigations.

SELECT
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;




