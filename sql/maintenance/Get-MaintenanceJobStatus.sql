/*
Script Name : Get-MaintenanceJobStatus
Category    : maintenance
Purpose     : Reports last run outcome, duration, and next scheduled run for all
              DBA maintenance jobs (any job whose name starts with 'DBA').
              Use after deploying the maintenance framework to confirm jobs are
              running on schedule and not failing silently.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : SQLAgentReaderRole or sysadmin
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    j.name                                                           AS job_name,
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END        AS status,

    -- Last run outcome
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
        ELSE        'Never run'
    END                                                              AS last_run_status,

    -- Last run timestamp (run_date is yyyymmdd int, run_time is HHmmss int)
    CASE WHEN h.run_date IS NULL THEN NULL
         ELSE msdb.dbo.agent_datetime(h.run_date, h.run_time)
    END                                                              AS last_run_at,

    -- Duration formatted as HH:MM:SS
    CASE WHEN h.run_duration IS NULL THEN NULL
         ELSE RIGHT('0' + CAST(h.run_duration / 10000 AS varchar(4)), 2) + ':'
            + RIGHT('0' + CAST((h.run_duration % 10000) / 100 AS varchar(2)), 2) + ':'
            + RIGHT('0' + CAST(h.run_duration % 100 AS varchar(2)), 2)
    END                                                              AS last_run_duration,

    -- First 200 chars of last outcome message (errors show here)
    LEFT(ISNULL(h.message, ''), 200)                                 AS last_message,

    -- Next scheduled run
    CASE WHEN sch.next_run_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(sch.next_run_date, sch.next_run_time)
    END                                                              AS next_run_at,

    j.date_created                                                   AS created_at

FROM msdb.dbo.sysjobs j

-- Most recent job-level outcome (step_id = 0 is the job-level summary row)
OUTER APPLY (
    SELECT TOP 1
        h.run_date, h.run_time, h.run_duration, h.run_status, h.message
    FROM msdb.dbo.sysjobhistory h
    WHERE h.job_id  = j.job_id
      AND h.step_id = 0
    ORDER BY h.run_date DESC, h.run_time DESC
) h

-- Next scheduled run from attached schedules
OUTER APPLY (
    SELECT TOP 1
        js.next_run_date, js.next_run_time
    FROM msdb.dbo.sysjobschedules js
    JOIN msdb.dbo.sysschedules    s  ON s.schedule_id = js.schedule_id
    WHERE js.job_id = j.job_id
      AND s.enabled = 1
      AND (js.next_run_date > 0 OR js.next_run_time > 0)
    ORDER BY js.next_run_date, js.next_run_time
) sch

WHERE j.name LIKE N'DBA %'  -- matches 'DBA - X' and 'DBA X' naming styles
ORDER BY j.name;
