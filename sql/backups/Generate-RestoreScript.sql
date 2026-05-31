/*
Script Name : Generate-RestoreScript
Category    : backups-and-recovery
Purpose     : Generate a RESTORE DATABASE script for all online user databases.
              Set @ts to the timestamp of the backup files you want to restore
              before executing. Review WITH MOVE if restoring to a different server.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

DECLARE @BackupPath    nvarchar(260) = N'D:\SQL-Backups';
DECLARE @WithReplace   bit           = 1;    -- 1 = WITH REPLACE
DECLARE @WithNoRecovery bit          = 0;    -- 1 = WITH NORECOVERY (log chain)
DECLARE @StatsInterval int           = 5;

IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);

DECLARE @WithClause nvarchar(200) = N'WITH ';
SET @WithClause += CASE WHEN @WithReplace    = 1 THEN N'REPLACE, '    ELSE N'' END;
SET @WithClause += CASE WHEN @WithNoRecovery = 1 THEN N'NORECOVERY, ' ELSE N'' END;
SET @WithClause += N'STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + N';';

DECLARE @cmd nvarchar(max) =
    N'-- RESTORE script — ' + @@SERVERNAME                                 + CHAR(13) + CHAR(10) +
    N'-- Path  : ' + @BackupPath                                            + CHAR(13) + CHAR(10) +
    N'-- Set @ts to the timestamp of the backup files to restore.'          + CHAR(13) + CHAR(10) +
    N'-- Review WITH MOVE if restoring to a different server or drive.'     + CHAR(13) + CHAR(10) +
                                                                              CHAR(13) + CHAR(10) +
    N'DECLARE @ts   varchar(15)  = ''yyyyMMdd_HHmmss''; -- replace with actual backup timestamp' + CHAR(13) + CHAR(10) +
    N'DECLARE @path nvarchar(500);'                                          + CHAR(13) + CHAR(10);

SELECT @cmd +=
    CHAR(13) + CHAR(10) +
    N'SET @path = ''' + @BackupPath + N'\' + d.name + N'_FULL_'' + @ts + ''.bak'';'    + CHAR(13) + CHAR(10) +
    N'RESTORE DATABASE [' + d.name + N'] FROM DISK = @path ' + @WithClause             + CHAR(13) + CHAR(10)
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state_desc  = N'ONLINE'
ORDER BY d.name;

IF @cmd IS NULL OR @cmd = N''
    SET @cmd = N'-- No online user databases found.' + CHAR(13) + CHAR(10);

SELECT @cmd AS script;
