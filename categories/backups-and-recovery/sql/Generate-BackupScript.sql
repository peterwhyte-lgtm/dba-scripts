/*
Script Name : Generate-BackupScript
Description : Returns Generate Backup Script for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Generate a full backup script for all user databases.
-- Copy into SSMS and adjust backup paths as needed.

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
BACKUP DATABASE [' + d.name + N'] TO DISK = ''C:\SQLBackups\' + d.name + N'_FULL.bak''
WITH COMPRESSION, STATS = 5;
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;




