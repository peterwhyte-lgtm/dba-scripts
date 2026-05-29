/*
Script Name : Generate-RestoreScript
Category    : backups-and-recovery
Purpose     : Generate a restore script for all user databases for DR and migration scenarios.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Review all file paths before executing in a DR or migration scenario.

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
RESTORE DATABASE [' + d.name + N'] FROM DISK = ''C:\SQLBackups\' + d.name + N'_FULL.bak''
WITH REPLACE, STATS = 5;
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;




