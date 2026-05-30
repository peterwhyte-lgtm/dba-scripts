/*
Script Name : Generate-BackupScript
Category    : backups-and-recovery
Purpose     : Generate a full backup script for all user databases for SSMS review.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
-- Copy output into SSMS, verify paths, then execute.
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- Configuration
DECLARE @BackupPath    nvarchar(260) = N'D:\SQL-Backups'; -- no trailing backslash
DECLARE @Compression   bit           = 1;                 -- 1 = WITH COMPRESSION
DECLARE @StatsInterval int           = 5;                 -- STATS = N progress reporting

-- Normalise: strip trailing backslash
IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);

-- Build WITH clause
DECLARE @WithClause nvarchar(200) = N'WITH ';
SET @WithClause += CASE WHEN @Compression   = 1 THEN N'COMPRESSION, ' ELSE N'' END;
SET @WithClause += N'STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + N';';

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
BACKUP DATABASE [' + d.name + N'] TO DISK = ''' + @BackupPath + N'\' + d.name + N'_FULL.bak''
' + @WithClause + N'
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;
