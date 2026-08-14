/*
Script Name : Get-SysadminMembers
Category    : security-and-permissions
Purpose     : List members of the sysadmin fixed server role — the focused privileged-access check (sysadmin only).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-sysadmin-members/)
Requires    : VIEW ANY DATABASE
HealthCheck : Yes
Related     : Get-ServerRoleMembers — same data across every fixed and user-defined server role (comprehensive audit)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

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





