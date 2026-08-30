/*
Script Name : Get-SqlAgentJobOverview
Category    : configuration-and-environment
Purpose     : Show all SQL Agent jobs with enabled state, owner, and last run outcome.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-sql-agent-job-overview/)
Requires    : db_datareader on msdb
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    j.name AS job_name,
    j.enabled,
    j.description,
    ISNULL(sp.name, '(unknown)') AS owner_name,
    j.date_created,
    j.date_modified,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Unknown'
    END AS last_run_outcome,

    -- Last run timestamp (last_run_date is yyyymmdd int, last_run_time is HHmmss int;
    -- both are 0 for a job that has never run)
    CASE WHEN js.last_run_date = 0 OR js.last_run_date IS NULL THEN NULL
         /* Inline conversion - agent_datetime() is a scalar UDF that db_datareader
            cannot EXECUTE, so using it would break the stated Requires */
         ELSE CONVERT(DATETIME,
                  STUFF(STUFF(CAST(js.last_run_date AS CHAR(8)), 7, 0, '-'), 5, 0, '-') + ' ' +
                  STUFF(STUFF(RIGHT('000000' + CAST(js.last_run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':'))
    END AS last_run_at,

    -- Duration formatted as HH:MM:SS (last_run_duration is an HHMMSS-packed int)
    CASE WHEN js.last_run_date = 0 OR js.last_run_date IS NULL THEN NULL
         ELSE RIGHT('0' + CAST(js.last_run_duration / 10000 AS varchar(4)), 2) + ':'
            + RIGHT('0' + CAST((js.last_run_duration % 10000) / 100 AS varchar(2)), 2) + ':'
            + RIGHT('0' + CAST(js.last_run_duration % 100 AS varchar(2)), 2)
    END AS last_run_duration
FROM msdb.dbo.sysjobs AS j
LEFT JOIN sys.server_principals AS sp ON j.owner_sid = sp.sid
LEFT JOIN msdb.dbo.sysjobservers AS js ON j.job_id = js.job_id
ORDER BY j.name;
