/*
Script Name : Generate-RestoreScript
Description : Returns Generate Restore Script for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Generate a restore script for all user databases.
-- Review file paths before executing in a DR or migration scenario.

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
RESTORE DATABASE [' + d.name + N'] FROM DISK = ''C:\SQLBackups\' + d.name + N'_FULL.bak''
WITH REPLACE, STATS = 5;
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;




