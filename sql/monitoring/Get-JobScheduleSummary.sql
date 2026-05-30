/*
Script Name : Get-JobScheduleSummary
Category    : configuration-and-environment
Purpose     : Show enabled SQL Agent jobs with their schedules and next scheduled run time.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    j.name                                                              AS job_name,
    sc.name                                                             AS schedule_name,
    CASE sc.freq_type
        WHEN 1   THEN 'Once'
        WHEN 4   THEN 'Daily'
        WHEN 8   THEN 'Weekly'
        WHEN 16  THEN 'Monthly'
        WHEN 32  THEN 'Monthly (relative)'
        WHEN 64  THEN 'On Agent start'
        WHEN 128 THEN 'When CPU idle'
        ELSE          CAST(sc.freq_type AS VARCHAR(10))
    END                                                                 AS freq_type,
    sc.freq_interval,
    STUFF(STUFF(RIGHT('000000' + CAST(sc.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
                                                                        AS scheduled_start_time,
    jsch.next_run_date,
    CASE jsch.next_run_date
        WHEN 0 THEN NULL
        ELSE STUFF(STUFF(RIGHT('000000' + CAST(jsch.next_run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
    END                                                                 AS next_run_time,
    CASE jss.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Cancelled'
        ELSE       'Unknown'
    END                                                                 AS last_outcome,
    jss.last_run_date,
    jss.last_run_duration
FROM msdb.dbo.sysjobs            AS j
JOIN msdb.dbo.sysjobschedules    AS jsch ON j.job_id          = jsch.job_id
JOIN msdb.dbo.sysschedules       AS sc   ON jsch.schedule_id  = sc.schedule_id
LEFT JOIN msdb.dbo.sysjobservers AS jss  ON j.job_id          = jss.job_id
WHERE j.enabled  = 1
  AND sc.enabled = 1
ORDER BY jsch.next_run_date, jsch.next_run_time;
