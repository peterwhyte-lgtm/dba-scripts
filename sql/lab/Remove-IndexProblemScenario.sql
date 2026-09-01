/*
Script Name : Remove-IndexProblemScenario
Category    : lab
Purpose     : Remove everything Create-IndexProblemScenario.sql created, and prove it is gone.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-duplicate-indexes/)
Requires    : sysadmin on the same LAB instance.
*/
-- SAFE:WritesData
-- IMPACT:High
--
-- Drops the zzidx_db database and nothing else. Dropping the database also clears its entries
-- from sys.dm_db_missing_index_details, so the MISSING_INDEX_FLOOD rows the scenario created
-- do not linger in the DMV afterwards. The final count must be 0.

SET NOCOUNT ON;
USE master;
GO

IF DB_ID('zzidx_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzidx_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzidx_db;
END
GO

SELECT COUNT(*) AS zzidx_databases_left FROM sys.databases WHERE name LIKE 'zzidx%';
SELECT COUNT(*) AS missing_index_rows_left
FROM sys.dm_db_missing_index_details WHERE database_id = DB_ID('zzidx_db');
