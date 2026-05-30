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
    j.name                                                          AS job_name,
    j.enabled,
    j.description,
    ISNULL(sp.name, '(unknown)')                                    AS owner_name,
    j.date_created,
    j.date_modified,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        ELSE 'Unknown'
    END                                                             AS last_run_outcome,
    js.last_run_date,
    js.last_run_time,
    js.last_run_duration
FROM msdb.dbo.sysjobs          AS j
LEFT JOIN sys.server_principals AS sp ON j.owner_sid = sp.sid
LEFT JOIN msdb.dbo.sysjobservers AS js ON j.job_id    = js.job_id
ORDER BY j.name;
