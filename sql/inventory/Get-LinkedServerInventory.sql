/*
Script Name : Get-LinkedServerInventory
Category    : migration
Purpose     : Inventory linked servers for migration and connectivity dependency mapping.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-linked-servers/)
Requires    : VIEW ANY DATABASE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-linked-servers/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
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

