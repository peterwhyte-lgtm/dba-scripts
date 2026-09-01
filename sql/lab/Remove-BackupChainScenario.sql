/*
Script Name : Remove-BackupChainScenario
Category    : lab
Purpose     : Remove the database and msdb backup history created by
              Create-BackupChainScenario.sql, and prove both are gone.
Author      : Peter Whyte (https://sqldba.blog/sql-server-differential-vs-log-backup/)
Requires    : sysadmin on the same LAB instance.
*/
-- SAFE:WritesData
-- IMPACT:High
--
-- Deletes the msdb history FIRST. Dropping a database does not remove its backupset rows, so
-- skipping this leaves nine fictional backups in msdb that a later chain audit would read as
-- real history for a database that no longer exists.

SET NOCOUNT ON;
USE master;
GO

EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'zzchain_db';

IF DB_ID('zzchain_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzchain_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzchain_db;
END
GO

SELECT COUNT(*) AS zzchain_databases_left FROM sys.databases        WHERE name LIKE 'zzchain%';
SELECT COUNT(*) AS zzchain_history_left   FROM msdb.dbo.backupset   WHERE database_name LIKE 'zzchain%';
