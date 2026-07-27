/*
Script Name : Get-ServerRoleMembers
Category    : security-and-permissions
Purpose     : List members of every fixed and user-defined server role — the comprehensive server-privilege audit.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-sysadmin-members/)
Requires    : VIEW ANY DATABASE
Related     : Get-SysadminMembers — the sysadmin-only focused check (health-check member)
*/
-- Blog: https://sqldba.blog/dba-scripts-get-sysadmin-members/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    sr.name                                                     AS server_role,
    sp.name                                                     AS member_login,
    sp.type_desc                                                AS login_type,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date
FROM sys.server_role_members    AS srm
JOIN sys.server_principals       AS sr ON srm.role_principal_id   = sr.principal_id
JOIN sys.server_principals       AS sp ON srm.member_principal_id = sp.principal_id
WHERE sp.name NOT LIKE '##%'
ORDER BY sr.name, sp.name;
