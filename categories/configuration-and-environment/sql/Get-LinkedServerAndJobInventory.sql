/*
Script Name : Get-LinkedServerAndJobInventory
Description : Returns Linked Server And Job Inventory for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Migration-oriented review script for logins, linked servers, and SQL Agent jobs.
-- IMPORTANT: Passwords are not scripted by SQL Server metadata and must be handled separately.
-- Use this to inventory objects before moving them to another instance.

SELECT 'LOGINS' AS object_type, name, type_desc, is_disabled
FROM sys.server_principals
WHERE type IN ('S','U','G')
  AND name NOT LIKE '##%'
  AND name NOT LIKE 'NT AUTHORITY%'
  AND name NOT LIKE 'NT SERVICE%'
ORDER BY name;

SELECT 'LINKED SERVERS' AS object_type, name, product, provider, data_source
FROM sys.servers
WHERE is_linked = 1
ORDER BY name;

SELECT 'JOBS' AS object_type, j.name, s.name AS job_owner, j.enabled
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.syslogins s ON j.owner_sid = s.sid
ORDER BY j.name;




