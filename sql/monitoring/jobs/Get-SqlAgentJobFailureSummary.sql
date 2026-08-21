/*
Script Name : Get-SqlAgentJobFailureSummary
Category    : configuration-and-environment
Purpose     : Show SQL Agent job failures from the last 7 days with readable timestamps and error messages.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-sql-agent-job-failure-summary/)
Requires    : db_datareader on msdb
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    j.name AS job_name,
    h.step_id,
    h.step_name,
    /* Inline yyyymmdd/HHmmss conversion - agent_datetime() is a scalar UDF that
       db_datareader cannot EXECUTE, so using it would break the stated Requires */
    CONVERT(DATETIME,
        STUFF(STUFF(CAST(h.run_date AS CHAR(8)), 7, 0, '-'), 5, 0, '-') + ' ' +
        STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':')
    ) AS run_datetime,
    CAST(h.run_duration / 10000 AS VARCHAR(4)) + 'h '
    + RIGHT('0' + CAST(h.run_duration / 100 % 100 AS VARCHAR(2)), 2) + 'm '
    + RIGHT('0' + CAST(h.run_duration % 100 AS VARCHAR(2)), 2) + 's' AS run_duration,
    h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON h.job_id = j.job_id
WHERE h.run_status = 0
  AND h.run_date >= CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -7, GETDATE()), 112))
ORDER BY h.instance_id DESC;
