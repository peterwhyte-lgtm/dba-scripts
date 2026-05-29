/*
Script Name : Generate-BackupScript
Category    : backups-and-recovery
Purpose     : Generate a full backup script for all user databases for SSMS review.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Copy output into SSMS and adjust backup paths before running.

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
BACKUP DATABASE [' + d.name + N'] TO DISK = ''C:\SQLBackups\' + d.name + N'_FULL.bak''
WITH COMPRESSION, STATS = 5;
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;




