/*
Script Name : Get-WaitStatistics
Category    : performance-troubleshooting
Purpose     : Top wait types since last SQL Server restart, filtered to actionable waits only.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH filtered_waits AS (
    SELECT
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms,
        wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
      AND wait_type NOT IN (
          -- Idle / background scheduler waits — not indicative of workload pressure
          'SLEEP_TASK',                     'SLEEP_SYSTEMTASK',
          'SLEEP_TEMPDBSTARTUP',            'SLEEP_DBSTARTUP',
          'SLEEP_DCOMSTARTUP',              'SLEEP_MASTERDBREADY',
          'SLEEP_MASTERMDREADY',            'SLEEP_MASTERUPGRADED',
          'SLEEP_MSDBSTARTUP',              'SNI_HTTP_ACCEPT',
          'DISPATCHER_QUEUE_SEMAPHORE',     'BROKER_TO_FLUSH',
          'BROKER_TASK_STOP',               'BROKER_EVENTHANDLER',
          'BROKER_RECEIVE_WAITFOR',         'CHECKPOINT_QUEUE',
          'DBMIRROR_EVENTS_QUEUE',          'DBMIRROR_WORKER_QUEUE',
          'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','SQLTRACE_BUFFER_FLUSH',
          'SQLTRACE_WAIT_ENTRIES',          'WAITFOR',
          'LAZYWRITER_SLEEP',               'LOGMGR_QUEUE',
          'ONDEMAND_TASK_QUEUE',            'REQUEST_FOR_DEADLOCK_SEARCH',
          'RESOURCE_QUEUE',                 'SERVER_IDLE_CHECK',
          'SP_SERVER_DIAGNOSTICS_SLEEP',    'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
          'XE_DISPATCHER_WAIT',             'XE_TIMER_EVENT',
          'HADR_WORK_QUEUE',                'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
          'HADR_CLUSAPI_CALL',              'HADR_NOTIFICATION_DEQUEUE',
          'FT_IFTS_SCHEDULER_IDLE_WAIT',    'FT_IFTSHC_MUTEX',
          'REPL_WORK_QUEUE',                'CLR_AUTO_EVENT',
          'CLR_MANUAL_EVENT',               'WAIT_XTP_COMPILE_WAIT'
      )
)
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(5,2)) AS pct_total_wait,
    CAST(wait_time_ms / NULLIF(waiting_tasks_count, 0) AS DECIMAL(10,0))              AS avg_wait_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    resource_wait_time_ms
FROM filtered_waits
ORDER BY wait_time_ms DESC;
