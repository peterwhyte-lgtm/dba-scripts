/*
Script Name : Get-LinkedServerInventory
Category    : migration
Purpose     : Inventory linked servers for migration and connectivity dependency mapping.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
SELECT
    s.name AS linked_server_name,
    s.product,
    s.provider,
    s.data_source,
    s.location,
    s.catalog,
    CASE WHEN s.is_linked = 1 THEN 'Linked' ELSE 'Local' END AS status
FROM sys.servers AS s
WHERE s.is_linked = 1
ORDER BY s.name;

