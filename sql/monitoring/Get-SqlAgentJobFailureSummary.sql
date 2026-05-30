/*
Script Name : Get-SqlAgentJobFailureSummary
Category    : configuration-and-environment
Purpose     : Show SQL Agent job failures from the last 7 days with readable timestamps and error messages.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    j.name                                                                      AS job_name,
    h.step_id,
    h.step_name,
    msdb.dbo.agent_datetime(h.run_date, h.run_time)                            AS run_datetime,
    CAST(h.run_duration / 10000 AS VARCHAR(4)) + 'h '
    + RIGHT('0' + CAST(h.run_duration / 100 % 100 AS VARCHAR(2)), 2) + 'm '
    + RIGHT('0' + CAST(h.run_duration % 100 AS VARCHAR(2)), 2) + 's'          AS run_duration,
    h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs        AS j  ON h.job_id = j.job_id
WHERE h.run_status = 0
  AND h.run_date  >= CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -7, GETDATE()), 112))
ORDER BY h.instance_id DESC;
