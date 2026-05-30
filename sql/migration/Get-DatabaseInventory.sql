/*
Script Name : Get-DatabaseInventory
Category    : migration
Purpose     : Inventory user databases for migration readiness — compatibility level, recovery model, state.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
SELECT
    d.name AS database_name,
    d.database_id,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    d.compatibility_level,
    d.is_read_only,
    d.is_auto_close_on,
    d.create_date,
    d.user_access_desc,
    d.collation_name
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY d.name;

