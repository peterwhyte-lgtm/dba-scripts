/*
Script Name : Generate-BackupJobs
Category    : maintenance
Purpose     : Generates SQL Agent DDL to create three scheduled maintenance jobs:
              DBA - Backup - FULL     daily full backup of all online user databases
              DBA - Backup - LOG      transaction log backups on a short interval (default 15 min)
              DBA - Backup - Cleanup  removes old backup files based on retention policy
              Edit the parameters section, review the output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-maintenance-jobs/)
Requires    : VIEW ANY DATABASE
Notes       : Output requires sysadmin or SQLAgentOperatorRole on the target instance.
              The backup root path must exist on the SQL Server host before jobs first run.
              Log backup job skips SIMPLE recovery model databases automatically.
              Cleanup step uses the PowerShell subsystem — SQL Agent service account needs
              delete rights on the backup folder.
              On AGs: use @FullBackupPreference to avoid full backups on the wrong replica;
              this script backs up whatever instance it runs on.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @BackupRootPath    nvarchar(260) = N'D:\SQLBackups';
DECLARE @FullRetentionDays int           = 14;      -- full backup files older than this are deleted
DECLARE @LogRetentionHours int           = 48;      -- log backup files older than this are deleted
DECLARE @FullScheduleHour  tinyint       = 2;       -- 0-23 — hour for the daily full backup
DECLARE @LogIntervalMins   tinyint       = 15;      -- log backup frequency in minutes
DECLARE @JobOwner          sysname       = N'sa';
DECLARE @CategoryName      nvarchar(128) = N'Database Maintenance';
-- ─────────────────────────────────────────────────────────────────────────────

IF RIGHT(@BackupRootPath, 1) = N'\'
    SET @BackupRootPath = LEFT(@BackupRootPath, LEN(@BackupRootPath) - 1);

DECLARE @q              nchar(1)      = NCHAR(39);
DECLARE @crlf           nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl            nvarchar(max) = N'';
DECLARE @fullScheduleTS int           = @FullScheduleHour * 10000;
DECLARE @logRetentionDays int         = CEILING(CAST(@LogRetentionHours AS float) / 24.0);

-- ── Step command: FULL backup ─────────────────────────────────────────────────
-- Cursor over all online, writeable, non-snapshot user databases.
-- Uses NCHAR(39) inside the step for path quoting — avoids nested string escaping.
DECLARE @fullCmd nvarchar(max) = REPLACE(
N'SET NOCOUNT ON;
DECLARE @db sysname, @path nvarchar(500), @sql nvarchar(max), @q nchar(1);
SET @q = NCHAR(39);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4 AND state_desc = N|ONLINE|
      AND is_read_only = 0 AND source_database_id IS NULL
    ORDER BY name;
OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @path = N|<<ROOT>>\| + @db + N|_FULL_|
        + REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(20), GETDATE(), 120),
          N|-|, N||), N| |, N|_|), N|:|, N||) + N|.bak|;
    SET @sql = N|BACKUP DATABASE [| + @db + N|] TO DISK = |
        + @q + @path + @q + N| WITH COMPRESSION, CHECKSUM, INIT, STATS = 10;|;
    EXEC sp_executesql @sql;
    FETCH NEXT FROM c INTO @db;
END
CLOSE c;
DEALLOCATE c;'
, N'|', NCHAR(39));
SET @fullCmd = REPLACE(@fullCmd, N'<<ROOT>>', @BackupRootPath);

-- ── Step command: LOG backup ──────────────────────────────────────────────────
DECLARE @logCmd nvarchar(max) = REPLACE(
N'SET NOCOUNT ON;
DECLARE @db sysname, @path nvarchar(500), @sql nvarchar(max), @q nchar(1);
SET @q = NCHAR(39);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4 AND state_desc = N|ONLINE|
      AND is_read_only = 0 AND source_database_id IS NULL
      AND recovery_model_desc IN (N|FULL|, N|BULK_LOGGED|)
    ORDER BY name;
OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @path = N|<<ROOT>>\| + @db + N|_LOG_|
        + REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(20), GETDATE(), 120),
          N|-|, N||), N| |, N|_|), N|:|, N||) + N|.trn|;
    SET @sql = N|BACKUP LOG [| + @db + N|] TO DISK = |
        + @q + @path + @q + N| WITH COMPRESSION, CHECKSUM, NOINIT, STATS = 10;|;
    EXEC sp_executesql @sql;
    FETCH NEXT FROM c INTO @db;
END
CLOSE c;
DEALLOCATE c;'
, N'|', NCHAR(39));
SET @logCmd = REPLACE(@logCmd, N'<<ROOT>>', @BackupRootPath);

-- ── Step command: Cleanup (PowerShell subsystem) ──────────────────────────────
-- Runs as a real PowerShell script (not CmdExec), so multi-line commands and
-- pipes execute exactly as written — no shell-quoting/chaining pitfalls to
-- work around. (CmdExec + forfiles.exe was tried first: SQL Agent's CmdExec
-- subsystem does not wrap the command in a shell, so forfiles' own multi-line
-- form only ran its first line, and neither redirection (2>nul) nor chaining
-- (&) were interpreted — both were passed through as literal, invalid
-- forfiles arguments. PowerShell avoids the whole class of problem.)
DECLARE @cleanCmd nvarchar(max) =
    N'Get-ChildItem -Path ' + @q + @BackupRootPath + @q + N' -Filter ' + @q + N'*_FULL_*.bak' + @q
    + N' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-'
    + CAST(@FullRetentionDays AS nvarchar(5)) + N') } | Remove-Item -Force' + @crlf
    + N'Get-ChildItem -Path ' + @q + @BackupRootPath + @q + N' -Filter ' + @q + N'*_LOG_*.trn' + @q
    + N' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-'
    + CAST(@logRetentionDays AS nvarchar(5)) + N') } | Remove-Item -Force';

-- ═══════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- =================================================================' + @crlf +
    N'-- Generated by Generate-BackupJobs.sql' + @crlf +
    N'-- Server       : ' + @@SERVERNAME + @crlf +
    N'-- Backup root  : ' + @BackupRootPath + @crlf +
    N'-- Full backup  : daily at ' + CAST(@FullScheduleHour AS nvarchar(2)) + N':00, kept '
        + CAST(@FullRetentionDays AS nvarchar(5)) + N' days' + @crlf +
    N'-- Log backup   : every ' + CAST(@LogIntervalMins AS nvarchar(5)) + N' min, kept '
        + CAST(@LogRetentionHours AS nvarchar(5)) + N' hours' + @crlf +
    N'-- Generated    : ' + CONVERT(nvarchar(20), GETDATE(), 120) + @crlf +
    N'-- =================================================================' + @crlf +
    @crlf +
    N'USE msdb;' + @crlf +
    N'GO' + @crlf;

-- Job category
SET @ddl +=
    @crlf +
    N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories' + @crlf +
    N'               WHERE name = N' + @q + @CategoryName + @q + N' AND category_class = 1)' + @crlf +
    N'    EXEC msdb.dbo.sp_add_category' + @crlf +
    N'        @class = N' + @q + N'JOB' + @q + N',' + @crlf +
    N'        @type  = N' + @q + N'LOCAL' + @q + N',' + @crlf +
    N'        @name  = N' + @q + @CategoryName + @q + N';' + @crlf +
    N'GO' + @crlf;

-- ── Job 1: DBA - Backup - FULL ────────────────────────────────────────────────
SET @ddl +=
    @crlf +
    N'-- ==================================================================' + @crlf +
    N'-- Job: DBA - Backup - FULL' + @crlf +
    N'-- ==================================================================' + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + N'DBA - Backup - FULL' + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job' + @crlf +
    N'        @job_name              = N' + @q + N'DBA - Backup - FULL' + @q + N',' + @crlf +
    N'        @delete_unused_schedule = 1;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_job' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - FULL' + @q + N',' + @crlf +
    N'    @enabled           = 1,' + @crlf +
    N'    @owner_login_name  = N' + @q + @JobOwner + @q + N',' + @crlf +
    N'    @category_name     = N' + @q + @CategoryName + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobstep' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - FULL' + @q + N',' + @crlf +
    N'    @step_id           = 1,' + @crlf +
    N'    @step_name         = N' + @q + N'Back up all user databases' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N',' + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N',' + @crlf +
    N'    @command           = N' + @q + REPLACE(@fullCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 1,' + @crlf +
    N'    @retry_interval    = 5,' + @crlf +
    N'    @on_success_action = 1,' + @crlf +
    N'    @on_fail_action    = 2;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_schedule' + @crlf +
    N'    @schedule_name        = N' + @q + N'DBA - Full Backup Daily '
        + CAST(@FullScheduleHour AS nvarchar(2)) + N':00' + @q + N',' + @crlf +
    N'    @freq_type            = 4,' + @crlf +
    N'    @freq_interval        = 1,' + @crlf +
    N'    @freq_subday_type     = 1,' + @crlf +
    N'    @freq_subday_interval = 0,' + @crlf +
    N'    @active_start_time    = ' + CAST(@fullScheduleTS AS nvarchar(10)) + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_attach_schedule' + @crlf +
    N'    @job_name      = N' + @q + N'DBA - Backup - FULL' + @q + N',' + @crlf +
    N'    @schedule_name = N' + @q + N'DBA - Full Backup Daily '
        + CAST(@FullScheduleHour AS nvarchar(2)) + N':00' + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + N'DBA - Backup - FULL' + @q + N';' + @crlf +
    N'GO' + @crlf;

-- ── Job 2: DBA - Backup - LOG ─────────────────────────────────────────────────
SET @ddl +=
    @crlf +
    N'-- ==================================================================' + @crlf +
    N'-- Job: DBA - Backup - LOG  (every ' + CAST(@LogIntervalMins AS nvarchar(5)) + N' minutes)' + @crlf +
    N'-- ==================================================================' + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + N'DBA - Backup - LOG' + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job' + @crlf +
    N'        @job_name              = N' + @q + N'DBA - Backup - LOG' + @q + N',' + @crlf +
    N'        @delete_unused_schedule = 1;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_job' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - LOG' + @q + N',' + @crlf +
    N'    @enabled           = 1,' + @crlf +
    N'    @owner_login_name  = N' + @q + @JobOwner + @q + N',' + @crlf +
    N'    @category_name     = N' + @q + @CategoryName + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobstep' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - LOG' + @q + N',' + @crlf +
    N'    @step_id           = 1,' + @crlf +
    N'    @step_name         = N' + @q + N'Back up transaction logs (FULL and BULK_LOGGED only)' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N',' + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N',' + @crlf +
    N'    @command           = N' + @q + REPLACE(@logCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 1,' + @crlf +
    N'    @retry_interval    = 2,' + @crlf +
    N'    @on_success_action = 1,' + @crlf +
    N'    @on_fail_action    = 2;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_schedule' + @crlf +
    N'    @schedule_name        = N' + @q + N'DBA - Log Backup Every '
        + CAST(@LogIntervalMins AS nvarchar(5)) + N' Min' + @q + N',' + @crlf +
    N'    @freq_type            = 4,' + @crlf +
    N'    @freq_interval        = 1,' + @crlf +
    N'    @freq_subday_type     = 4,' + @crlf +
    N'    @freq_subday_interval = ' + CAST(@LogIntervalMins AS nvarchar(5)) + N',' + @crlf +
    N'    @active_start_time    = 0;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_attach_schedule' + @crlf +
    N'    @job_name      = N' + @q + N'DBA - Backup - LOG' + @q + N',' + @crlf +
    N'    @schedule_name = N' + @q + N'DBA - Log Backup Every '
        + CAST(@LogIntervalMins AS nvarchar(5)) + N' Min' + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + N'DBA - Backup - LOG' + @q + N';' + @crlf +
    N'GO' + @crlf;

-- ── Job 3: DBA - Backup - Cleanup ─────────────────────────────────────────────
SET @ddl +=
    @crlf +
    N'-- ==================================================================' + @crlf +
    N'-- Job: DBA - Backup - Cleanup' + @crlf +
    N'-- Requires: SQL Agent service account has delete access to backup folder.' + @crlf +
    N'-- ==================================================================' + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + N'DBA - Backup - Cleanup' + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job' + @crlf +
    N'        @job_name              = N' + @q + N'DBA - Backup - Cleanup' + @q + N',' + @crlf +
    N'        @delete_unused_schedule = 1;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_job' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - Cleanup' + @q + N',' + @crlf +
    N'    @enabled           = 1,' + @crlf +
    N'    @owner_login_name  = N' + @q + @JobOwner + @q + N',' + @crlf +
    N'    @category_name     = N' + @q + @CategoryName + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobstep' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Backup - Cleanup' + @q + N',' + @crlf +
    N'    @step_id           = 1,' + @crlf +
    N'    @step_name         = N' + @q + N'Delete old backup files' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'PowerShell' + @q + N',' + @crlf +
    N'    @command           = N' + @q + REPLACE(@cleanCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @on_success_action = 1,' + @crlf +
    N'    @on_fail_action    = 2;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_schedule' + @crlf +
    N'    @schedule_name        = N' + @q + N'DBA - Backup Cleanup Daily '
        + CAST((@FullScheduleHour + 1) % 24 AS nvarchar(2)) + N':00' + @q + N',' + @crlf +
    N'    @freq_type            = 4,' + @crlf +
    N'    @freq_interval        = 1,' + @crlf +
    N'    @freq_subday_type     = 1,' + @crlf +
    N'    @freq_subday_interval = 0,' + @crlf +
    N'    @active_start_time    = ' + CAST(((@FullScheduleHour + 1) % 24) * 10000 AS nvarchar(10)) + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_attach_schedule' + @crlf +
    N'    @job_name      = N' + @q + N'DBA - Backup - Cleanup' + @q + N',' + @crlf +
    N'    @schedule_name = N' + @q + N'DBA - Backup Cleanup Daily '
        + CAST((@FullScheduleHour + 1) % 24 AS nvarchar(2)) + N':00' + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + N'DBA - Backup - Cleanup' + @q + N';' + @crlf +
    N'GO' + @crlf;

SELECT @ddl AS ddl;
