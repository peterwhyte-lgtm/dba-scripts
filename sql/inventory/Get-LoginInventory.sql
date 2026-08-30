/*
Script Name : Get-LoginInventory
Category    : migration
Purpose     : Inventory server logins by type and status for migration and access review.
              Returns the logins a migration has to recreate: SQL logins, Windows logins and
              Windows groups. Deliberately EXCLUDES the engine's own principals (##certificate
              logins, NT AUTHORITY\*, NT SERVICE\*) because those are created by the install
              on the target, not migrated onto it.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-and-job-inventory/)
Requires    : VIEW ANY DEFINITION (or ALTER ANY LOGIN). A login without it sees only its own
              row in sys.server_principals, so the result looks empty rather than erroring.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SELECT
    sp.name AS login_name,
    sp.type_desc AS login_type,
    CASE WHEN sp.is_disabled = 1 THEN 'Disabled' ELSE 'Enabled' END AS status,
    sp.default_database_name,
    /* The SID is what makes a migrated SQL login match its database users on the target.
       Rendered as the 0x string you can paste straight into CREATE LOGIN ... WITH SID. */
    CONVERT(VARCHAR(256), sp.sid, 1) AS login_sid,
    sp.create_date,
    sp.modify_date
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.type_desc, sp.name;

