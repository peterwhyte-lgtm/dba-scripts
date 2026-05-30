/*
Script Name : Get-UserPermissionsAudit
Category    : security-and-permissions
Purpose     : List all SQL Server logins by type and disabled state for permissions review.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    sp.name                                                             AS login_name,
    sp.type_desc                                                        AS login_type,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.type_desc, sp.name;
