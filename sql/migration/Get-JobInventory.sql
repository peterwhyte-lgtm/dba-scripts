/*
Script Name : Get-JobInventory
Category    : migration
Purpose     : Inventory SQL Agent jobs with owner for migration dependency checks.
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
    CASE WHEN j.enabled = 1 THEN 'Enabled' ELSE 'Disabled' END AS status,
    j.description,
    j.date_created,
    j.date_modified,
    ISNULL(sp.name, '(unknown)') AS owner_name,
    j.job_id
FROM msdb.dbo.sysjobs AS j
LEFT JOIN sys.server_principals AS sp
    ON j.owner_sid = sp.sid
ORDER BY j.name;

