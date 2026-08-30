/*
Script Name : Get-JobScheduleSummary
Category    : configuration-and-environment
Purpose     : Show enabled SQL Agent jobs with their schedules and next scheduled run time.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-job-schedules-and-duration-trends/)
Requires    : db_datareader on msdb
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    j.name AS job_name,
    sc.name AS schedule_name,
    CASE sc.freq_type
        WHEN 1 THEN 'Once'
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
        WHEN 32 THEN 'Monthly (relative)'
        WHEN 64 THEN 'On Agent start'
        WHEN 128 THEN 'When CPU idle'
        ELSE CAST(sc.freq_type AS VARCHAR(10))
    END AS freq_type,
    sc.freq_interval,
    STUFF(STUFF(RIGHT('000000' + CAST(sc.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS scheduled_start_time,

    /* msdb stores these as yyyymmdd + HHmmss integers; return real datetimes so the output
       reads without decoding (matches Get-JobDurationTrends on the same page) */
    CASE WHEN jsch.next_run_date = 0 THEN NULL
         ELSE CONVERT(DATETIME,
                  STUFF(STUFF(CAST(jsch.next_run_date AS CHAR(8)), 7, 0, '-'), 5, 0, '-') + ' ' +
                  STUFF(STUFF(RIGHT('000000' + CAST(jsch.next_run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':'))
    END AS next_run_at,

    CASE jss.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Unknown'
    END AS last_outcome,

    CASE WHEN jss.last_run_date IS NULL OR jss.last_run_date = 0 THEN NULL
         ELSE CONVERT(DATETIME,
                  STUFF(STUFF(CAST(jss.last_run_date AS CHAR(8)), 7, 0, '-'), 5, 0, '-') + ' ' +
                  STUFF(STUFF(RIGHT('000000' + CAST(jss.last_run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':'))
    END AS last_run_at,

    /* packed HHMMSS integer -> HH:MM:SS */
    CASE WHEN jss.last_run_date IS NULL OR jss.last_run_date = 0 THEN NULL
         ELSE RIGHT('0' + CAST(jss.last_run_duration / 10000 AS varchar(4)), 2) + ':'
            + RIGHT('0' + CAST((jss.last_run_duration % 10000) / 100 AS varchar(2)), 2) + ':'
            + RIGHT('0' + CAST(jss.last_run_duration % 100 AS varchar(2)), 2)
    END AS last_run_duration
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobschedules AS jsch ON j.job_id = jsch.job_id
JOIN msdb.dbo.sysschedules AS sc ON jsch.schedule_id = sc.schedule_id
LEFT JOIN msdb.dbo.sysjobservers AS jss ON j.job_id = jss.job_id
WHERE j.enabled = 1
  AND sc.enabled = 1
ORDER BY jsch.next_run_date, jsch.next_run_time;
