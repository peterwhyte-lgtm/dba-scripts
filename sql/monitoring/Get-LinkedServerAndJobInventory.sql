/*
Script Name : Get-LinkedServerAndJobInventory
Category    : configuration-and-environment
Purpose     : Inventory logins, linked servers, and SQL Agent jobs for pre-migration reviews.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, db_datareader on msdb
Notes       : Returns three result sets (logins, linked servers, jobs). Run in SSMS or
              use the individual focused scripts for CSV export.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    'LOGIN'           AS object_type,
    sp.name           AS name,
    sp.type_desc      AS detail,
    CAST(sp.is_disabled AS VARCHAR(5)) AS status
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.name;

SELECT
    'LINKED SERVER'           AS object_type,
    s.name                    AS name,
    s.product + ' / ' + s.provider AS detail,
    s.data_source             AS status
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;

SELECT
    'JOB'                     AS object_type,
    j.name                    AS name,
    ISNULL(sp.name, '(unknown)') AS detail,
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS status
FROM msdb.dbo.sysjobs          AS j
LEFT JOIN sys.server_principals AS sp ON j.owner_sid = sp.sid
ORDER BY j.name;
