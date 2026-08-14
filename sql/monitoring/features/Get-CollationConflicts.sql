/*
Script Name : Get-CollationConflicts
Category    : monitoring
Purpose     : Databases whose collation differs from the server collation — a common source of implicit conversion errors and failed JOIN operations.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-collation-conflicts-and-cross-database-dependencies/)
Requires    : VIEW ANY DATABASE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @server_collation NVARCHAR(128) = CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));

SELECT
    @server_collation AS server_collation,
    d.name AS database_name,
    d.collation_name AS database_collation,
    CASE WHEN d.collation_name <> @server_collation
         THEN 'MISMATCH' ELSE 'OK' END AS collation_status,
    d.state_desc,
    d.recovery_model_desc,
    d.database_id
FROM sys.databases d
WHERE d.state_desc = 'ONLINE'
ORDER BY
    CASE WHEN d.collation_name <> @server_collation THEN 0 ELSE 1 END,
    d.name;
