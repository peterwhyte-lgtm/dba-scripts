/*
Script Name : Get-UserPermissionsAudit
Category    : security-and-permissions
Purpose     : Audit SQL Server logins and their types for permission reviews.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low


USE master;
GO

SELECT
    sp.name AS login_name,
    sp.type_desc AS login_type,
    sp.is_disabled
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
ORDER BY sp.name;




