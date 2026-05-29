/*
Script Name : Get-SqlAgentJobFailureSummary
Category    : configuration-and-environment
Purpose     : Review recent SQL Agent job failures with run dates, steps, and error messages.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    j.name AS job_name,
    h.instance_id,
    h.run_date,
    h.run_time,
    h.run_status,
    h.message,
    h.step_id,
    h.step_name
FROM msdb.dbo.sysjobhistory AS h
INNER JOIN msdb.dbo.sysjobs AS j
    ON h.job_id = j.job_id
WHERE h.run_status = 0
  AND h.run_date >= CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -7, GETDATE()), 112))
ORDER BY h.instance_id DESC;




