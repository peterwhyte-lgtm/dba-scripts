/*
Script Name : Generate-RestoreWithMoveScript
Category    : migration
Purpose     : Generate RESTORE DATABASE scripts with WITH MOVE for all online user databases.
              Run on SOURCE server. Supply the backup path and path prefix mappings for
              data and log files before executing the output on TARGET.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-restore-with-move-script/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Reads file layout from source server's sys.master_files to generate WITH MOVE
  clauses. Path prefixes are replaced using @OldDataRoot→@NewDataRoot and
  @OldLogRoot→@NewLogRoot substitutions. Adjust these four variables before running.

  If source and target have IDENTICAL drive layouts, use Generate-RestoreScript.sql instead
  (no WITH MOVE needed). Use this script when drive letters or folder paths differ.

  After running the output on the target:
    1. Verify all databases are ONLINE: SELECT name, state_desc FROM sys.databases WHERE database_id > 4
    2. Run Fix-OrphanedUsers.sql to re-map database users to logins
    3. Run Get-PostMigrationValidation.sql on both servers and compare
*/

-- ── Adjust these four variables ───────────────────────────────────────────────
DECLARE @BackupPath    nvarchar(260) = N'\\BACKUP-SERVER\SQL-Backups';  -- UNC or local path to .bak files
DECLARE @OldDataRoot   nvarchar(260) = N'E:\SQLData';                   -- data path prefix on SOURCE
DECLARE @NewDataRoot   nvarchar(260) = N'D:\SQLData';                   -- data path prefix on TARGET
DECLARE @OldLogRoot    nvarchar(260) = N'L:\SQLLogs';                   -- log path prefix on SOURCE
DECLARE @NewLogRoot    nvarchar(260) = N'L:\SQLLogs';                   -- log path prefix on TARGET
DECLARE @StatsInterval int           = 5;
DECLARE @WithReplace   bit           = 1;   -- 1 = WITH REPLACE (overwrites existing databases on target)
DECLARE @WithRecovery  bit           = 1;   -- 0 = NORECOVERY (leave in restoring state for diff/log chain)
-- ─────────────────────────────────────────────────────────────────────────────

IF RIGHT(@BackupPath, 1) = N'\' SET @BackupPath = LEFT(@BackupPath, LEN(@BackupPath) - 1);
IF RIGHT(@OldDataRoot, 1) = N'\' SET @OldDataRoot = LEFT(@OldDataRoot, LEN(@OldDataRoot) - 1);
IF RIGHT(@NewDataRoot, 1) = N'\' SET @NewDataRoot = LEFT(@NewDataRoot, LEN(@NewDataRoot) - 1);
IF RIGHT(@OldLogRoot, 1) = N'\' SET @OldLogRoot = LEFT(@OldLogRoot, LEN(@OldLogRoot) - 1);
IF RIGHT(@NewLogRoot, 1) = N'\' SET @NewLogRoot = LEFT(@NewLogRoot, LEN(@NewLogRoot) - 1);

DECLARE @cmd   nvarchar(max);
DECLARE @block nvarchar(max);
DECLARE @crlf  nchar(2)  = CHAR(13) + CHAR(10);

SET @cmd =
    N'-- ================================================================' + @crlf +
    N'-- RESTORE with MOVE script' + @crlf +
    N'-- Source  : ' + @@SERVERNAME + @crlf +
    N'-- Generated: ' + CONVERT(nvarchar(30), GETDATE(), 120) + @crlf +
    N'-- Backup path : ' + @BackupPath + @crlf +
    N'-- Data : ' + @OldDataRoot + N' → ' + @NewDataRoot + @crlf +
    N'-- Logs : ' + @OldLogRoot  + N' → ' + @NewLogRoot  + @crlf +
    N'-- ================================================================' + @crlf +
    N'-- Set @ts to the actual timestamp of your backup files.' + @crlf +
    N'DECLARE @ts varchar(15) = ''yyyyMMdd_HHmmss''; -- REPLACE WITH ACTUAL TIMESTAMP' + @crlf +
    N'DECLARE @path nvarchar(500);' + @crlf;

-- One block per database using file layout from sys.master_files
DECLARE @dbname       nvarchar(128);
DECLARE @logical_name nvarchar(128);
DECLARE @old_path     nvarchar(260);
DECLARE @new_path     nvarchar(260);
DECLARE @file_type    nvarchar(60);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT d.name
    FROM sys.databases d
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
    ORDER BY d.name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Build the WITH MOVE clause for this database
    SET @block = N'';

    DECLARE file_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT mf.name, mf.physical_name, mf.type_desc
        FROM sys.master_files mf
        INNER JOIN sys.databases d ON mf.database_id = d.database_id
        WHERE d.name = @dbname
        ORDER BY mf.file_id;

    OPEN file_cur;
    FETCH NEXT FROM file_cur INTO @logical_name, @old_path, @file_type;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Replace old path prefix with new path prefix.
        -- Only when the source path actually STARTS with the configured prefix.
        -- If it does not, the prefix arithmetic below would chop a fixed number of
        -- characters off an unrelated path and produce a plausible-looking but wrong
        -- target (E:\SQLData against a real D:\MSSQL\DATA\x.mdf yields
        -- D:\SQLDataATA\x.mdf). Fall back to the UNCHANGED source path instead: the
        -- restore then either works, because the layout already matches, or fails
        -- loudly on a path that does not exist. It never silently invents one.
        SET @new_path = CASE
            WHEN @file_type = 'LOG' AND LEFT(@old_path, LEN(@OldLogRoot)) = @OldLogRoot
                THEN @NewLogRoot  + SUBSTRING(@old_path, LEN(@OldLogRoot)  + 1, LEN(@old_path))
            WHEN @file_type <> 'LOG' AND LEFT(@old_path, LEN(@OldDataRoot)) = @OldDataRoot
                THEN @NewDataRoot + SUBSTRING(@old_path, LEN(@OldDataRoot) + 1, LEN(@old_path))
            ELSE @old_path
        END;

        SET @block = @block
            + CASE
                WHEN @file_type = 'LOG' AND LEFT(@old_path, LEN(@OldLogRoot)) <> @OldLogRoot
                    THEN N'       -- WARNING: source path does not start with @OldLogRoot (''' + @OldLogRoot + N'''), so NO remap was applied. The MOVE below still points at the SOURCE path. Set @OldLogRoot to match, or edit this line by hand.' + @crlf
                WHEN @file_type <> 'LOG' AND LEFT(@old_path, LEN(@OldDataRoot)) <> @OldDataRoot
                    THEN N'       -- WARNING: source path does not start with @OldDataRoot (''' + @OldDataRoot + N'''), so NO remap was applied. The MOVE below still points at the SOURCE path. Set @OldDataRoot to match, or edit this line by hand.' + @crlf
                ELSE N''
              END
            + N'       ,MOVE N''' + REPLACE(@logical_name, N'''', N'''''') + N''' TO N''' + REPLACE(@new_path, N'''', N'''''') + N'''' + @crlf;

        FETCH NEXT FROM file_cur INTO @logical_name, @old_path, @file_type;
    END

    CLOSE file_cur;
    DEALLOCATE file_cur;

    -- Assemble the full RESTORE statement
    SET @cmd = @cmd + @crlf
        + N'SET @path = ''' + @BackupPath + N'\' + @dbname + N'_FULL_'' + @ts + ''.bak'';' + @crlf
        + N'RESTORE DATABASE [' + @dbname + N'] FROM DISK = @path' + @crlf
        + N'    WITH' + @crlf
        + CASE WHEN @WithReplace   = 1 THEN N'         REPLACE,' + @crlf  ELSE N'' END
        + CASE WHEN @WithRecovery  = 0 THEN N'         NORECOVERY,' + @crlf ELSE N'' END
        + N'         STATS = ' + CAST(@StatsInterval AS nvarchar(3)) + @crlf
        + @block
        + N';' + @crlf;

    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT @cmd AS script;
