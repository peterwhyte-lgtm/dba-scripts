/*
Script Name : Get-SysadminMembers
Description : Returns Sysadmin Members for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- List members of the sysadmin fixed server role.
-- Useful for audits and privilege review.

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




