/*
Script Name : Get-LoginInventory
Category    : migration
Purpose     : Inventory server logins by type and status for migration and access review.
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
    sp.type_desc AS login_type,
    CASE WHEN sp.is_disabled = 1 THEN 'Disabled' ELSE 'Enabled' END AS status,
    sp.default_database_name,
    sp.create_date,
    sp.modify_date
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY%'
  AND sp.name NOT LIKE 'NT SERVICE%'
ORDER BY sp.type_desc, sp.name;

