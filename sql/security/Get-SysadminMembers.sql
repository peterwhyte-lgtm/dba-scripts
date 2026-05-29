/*
Script Name : Get-SysadminMembers
Category    : security-and-permissions
Purpose     : List members of the sysadmin fixed server role for audits and privilege review.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    sp.name AS login_name,
    sp.type_desc,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date
FROM sys.server_principals sp
JOIN sys.server_role_members srm ON sp.principal_id = srm.member_principal_id
JOIN sys.server_principals sr ON srm.role_principal_id = sr.principal_id
WHERE sr.name = 'sysadmin'
ORDER BY sp.name;





