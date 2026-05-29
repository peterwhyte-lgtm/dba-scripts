/*
Script Name : Get-SqlAgentJobOverview
Description : Returns Sql Agent Job Overview for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Review SQL Agent jobs, enabled state, and last run outcome.
-- Useful for operational health checks and incident review.

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




