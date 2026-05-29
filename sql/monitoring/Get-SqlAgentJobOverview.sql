/*
Script Name : Get-SqlAgentJobOverview
Category    : configuration-and-environment
Purpose     : Show all SQL Agent jobs with enabled state, owner, and last run outcome.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    j.name,
    j.enabled,
    j.description,
    s.name AS owner_name,
    j.date_created,
    j.date_modified,
    js.last_run_outcome,
    js.last_run_date,
    js.last_run_time
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.syslogins s ON j.owner_sid = s.sid
LEFT JOIN msdb.dbo.sysjobservers js ON j.job_id = js.job_id
ORDER BY j.name;




