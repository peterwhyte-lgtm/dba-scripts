/*
Script Name : Generate-RestoreScript
Category    : backups-and-recovery
Purpose     : Generate a restore script for all user databases for DR and migration scenarios.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
-- Review all file paths before executing in a DR or migration scenario.
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- Configuration
DECLARE @BackupPath    nvarchar(260) = N'D:\SQL-Backups'; -- no trailing backslash; must match backup destination
DECLARE @WithReplace   bit           = 1;                 -- 1 = WITH REPLACE (overwrites existing database)
DECLARE @WithNoRecovery bit          = 0;                 -- 1 = WITH NORECOVERY (leave DB in restoring for log chain)
DECLARE @StatsInterval int           = 5;                 -- STATS = N progress reporting

-- Normalise: strip trailing backslash
IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);

-- Build WITH clause
DECLARE @WithClause nvarchar(200) = N'WITH ';
SET @WithClause += CASE WHEN @WithReplace    = 1 THEN N'REPLACE, '    ELSE N'' END;
SET @WithClause += CASE WHEN @WithNoRecovery = 1 THEN N'NORECOVERY, ' ELSE N'' END;
SET @WithClause += N'STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + N';';

DECLARE @cmd nvarchar(max) = N'';

SELECT @cmd += N'
RESTORE DATABASE [' + d.name + N'] FROM DISK = ''' + @BackupPath + N'\' + d.name + N'_FULL.bak''
' + @WithClause + N'
'
FROM sys.databases d
WHERE d.database_id > 4;

PRINT @cmd;
