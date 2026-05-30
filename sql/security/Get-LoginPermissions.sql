/*
Script Name : Get-LoginPermissions
Category    : security-and-permissions
Purpose     : Show explicit server-level permissions granted or denied to logins.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    sp.name                                                     AS grantee,
    sp.type_desc                                                AS grantee_type,
    perm.state_desc                                             AS grant_state,
    perm.permission_name,
    perm.class_desc                                             AS object_class,
    ISNULL(obj.name, 'SERVER')                                  AS object_name
FROM sys.server_permissions AS perm
JOIN sys.server_principals   AS sp  ON perm.grantee_principal_id = sp.principal_id
LEFT JOIN sys.server_principals AS obj ON perm.major_id          = obj.principal_id
WHERE sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
  AND perm.state_desc <> 'GRANT'  -- keep GRANT_WITH_GRANT_OPTION, DENY; exclude plain inherited GRANTs
ORDER BY sp.name, perm.permission_name;
