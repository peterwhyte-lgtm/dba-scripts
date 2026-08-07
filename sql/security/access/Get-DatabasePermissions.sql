/*
Script Name : Get-DatabasePermissions
Category    : security
Purpose     : Returns all explicit object- and schema-level GRANT/DENY permissions in the
              current database. Shows grantee, permission, object, and grantor. Run in the
              context of each user database — does not iterate across databases.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/)
Requires    : VIEW DATABASE STATE or membership in db_securityadmin
              Run against each target database: -Database YourDatabase
*/
-- Blog: https://sqldba.blog/dba-scripts-get-permissions-and-role-membership/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: sys.database_permissions covers three major classes here:
    DATABASE — server-level db-scoped permissions (CONNECT, etc.)
    OBJECT_OR_COLUMN — explicit table/view/proc/function grants
    SCHEMA — schema-level grants that cascade to all objects in the schema
  Column-level permissions (minor_id > 0) are included with the column name resolved.
  Built-in principals (public, sys, INFORMATION_SCHEMA, guest) are excluded.
*/

SELECT
    grantee.name AS grantee_name,
    grantee.type_desc AS grantee_type,
    dp.permission_name,
    dp.state_desc, -- GRANT | GRANT_WITH_GRANT_OPTION | DENY
    dp.class_desc, -- DATABASE | OBJECT_OR_COLUMN | SCHEMA
    CASE dp.class_desc
        WHEN 'SCHEMA' THEN SCHEMA_NAME(dp.major_id)
        WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_SCHEMA_NAME(dp.major_id)
        ELSE NULL
    END AS schema_name,
    CASE dp.class_desc
        WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(dp.major_id)
        ELSE NULL
    END AS object_name,
    CASE dp.class_desc
        WHEN 'OBJECT_OR_COLUMN' THEN o.type_desc
        ELSE NULL
    END AS object_type,
    CASE
        WHEN dp.minor_id > 0 THEN COL_NAME(dp.major_id, dp.minor_id)
        ELSE NULL
    END AS column_name,
    SUSER_SNAME(grantor.sid) AS grantor_name
FROM sys.database_permissions dp
JOIN sys.database_principals grantee
    ON grantee.principal_id = dp.grantee_principal_id
JOIN sys.database_principals grantor
    ON grantor.principal_id = dp.grantor_principal_id
LEFT JOIN sys.objects o
    ON o.object_id = dp.major_id
WHERE dp.class_desc IN ('OBJECT_OR_COLUMN', 'SCHEMA', 'DATABASE')
  AND grantee.name NOT IN ('public', 'sys', 'INFORMATION_SCHEMA', 'guest', 'dbo')
  AND grantee.type NOT IN ('R') -- roles shown separately via Get-DatabaseRoleMembers
ORDER BY
    grantee.name,
    dp.class_desc,
    schema_name,
    object_name,
    dp.permission_name;
