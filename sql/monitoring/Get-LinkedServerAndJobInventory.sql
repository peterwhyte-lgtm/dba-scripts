/*
Script Name : Get-LinkedServerAndJobInventory
Category    : configuration-and-environment
Purpose     : Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Migration-oriented review: logins, linked servers, and SQL Agent jobs.
-- Passwords are not scripted by SQL Server metadata and must be handled separately.

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




