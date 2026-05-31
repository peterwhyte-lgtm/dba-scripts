/*
Script Name : Generate-TLogBackupScript
Category    : backups-and-recovery
Purpose     : Generate a transaction log backup script for all online user databases
              in FULL or BULK_LOGGED recovery model. SIMPLE recovery databases are
              excluded — log backups are not supported for them.
              @ts in the generated script resolves at execution time so filenames
              include the backup timestamp, not the script generation timestamp.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

DECLARE @BackupPath    nvarchar(260) = N'D:\SQL-Backups';
DECLARE @Compression   bit           = 1;
DECLARE @StatsInterval int           = 5;

IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);

DECLARE @WithClause nvarchar(200) = N'WITH ';
SET @WithClause += CASE WHEN @Compression = 1 THEN N'COMPRESSION, ' ELSE N'' END;
SET @WithClause += N'STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + N';';

DECLARE @cmd nvarchar(max) =
    N'-- TRANSACTION LOG backup script — ' + @@SERVERNAME                  + CHAR(13) + CHAR(10) +
    N'-- Path  : ' + @BackupPath                                            + CHAR(13) + CHAR(10) +
    N'-- FULL and BULK_LOGGED databases only (SIMPLE excluded).'            + CHAR(13) + CHAR(10) +
    N'-- Verify path exists before executing.'                              + CHAR(13) + CHAR(10) +
                                                                              CHAR(13) + CHAR(10) +
    N'DECLARE @ts   varchar(15)  = FORMAT(GETDATE(), ''yyyyMMdd_HHmmss'');' + CHAR(13) + CHAR(10) +
    N'DECLARE @path nvarchar(500);'                                          + CHAR(13) + CHAR(10);

SELECT @cmd +=
    CHAR(13) + CHAR(10) +
    N'SET @path = ''' + @BackupPath + N'\' + d.name + N'_LOG_'' + @ts + ''.trn'';'    + CHAR(13) + CHAR(10) +
    N'BACKUP LOG [' + d.name + N'] TO DISK = @path ' + @WithClause                   + CHAR(13) + CHAR(10)
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.state_desc        = N'ONLINE'
  AND d.recovery_model_desc IN (N'FULL', N'BULK_LOGGED')
ORDER BY d.name;

IF @cmd IS NULL OR @cmd = N''
    SET @cmd = N'-- No eligible databases found. All online user databases may be in SIMPLE recovery.' + CHAR(13) + CHAR(10);

SELECT @cmd AS script;
