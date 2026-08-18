/*
Script Name : Generate-IndexMaintenanceJobs
Category    : maintenance
Purpose     : Generates SQL Agent DDL for:
              DBA - Index Maintenance   rebuilds/reorganizes fragmented indexes across
                                        all online user databases using LIMITED scan.
                                        Automatically uses ONLINE = ON on Enterprise/Developer;
                                        falls back to offline rebuild on Standard/Web edition.
              DBA - Statistics Update   runs sp_updatestats on every online user database
                                        (tables that had rows modified since last update only).
              Edit the parameters section, review the output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-index-maintenance-jobs/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
Notes       : Index maintenance runtime varies widely with database count and size.
              Schedule outside peak hours. On a busy 3 000-database estate, consider
              splitting the job across multiple days or server groups.
              Online rebuild requires Enterprise or Developer edition — detected at job runtime.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @FragReorgThreshold   decimal(5,1) = 10.0;   -- frag% >= this: REORGANIZE
DECLARE @FragRebuildThreshold decimal(5,1) = 30.0;   -- frag% >= this: REBUILD (overrides reorg)
DECLARE @MinPageCount         int          = 1000;   -- skip indexes smaller than this
DECLARE @MaintScheduleHour    tinyint      = 1;      -- hour (0-23) for weekly index job
DECLARE @StatsScheduleHour    tinyint      = 23;     -- hour (0-23) for weekly stats job
DECLARE @JobOwner             sysname      = N'sa';
DECLARE @CategoryName         nvarchar(128)= N'Database Maintenance';
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q              nchar(1)      = NCHAR(39);
DECLARE @crlf           nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl            nvarchar(max) = N'';
DECLARE @maintSchedTS   int           = @MaintScheduleHour * 10000;
DECLARE @statsSchedTS   int           = @StatsScheduleHour * 10000;

-- ── Step command: index rebuild / reorganize ──────────────────────────────────
-- Phase 1: collect all fragmented indexes across user databases into a temp table.
--   Uses USE [db] inside dynamic SQL so sys.dm_db_index_physical_stats and catalog
--   views run in the correct database context.
-- Phase 2: apply REBUILD or REORGANIZE for each collected index.
-- @CanOnline is detected from EngineEdition at job runtime, not at generation time.
DECLARE @idxCmd nvarchar(max) = REPLACE(
N'SET NOCOUNT ON;
DECLARE @MinPageCount   int           = <<MIN_PAGES>>;
DECLARE @ReorgPct       decimal(5,1)  = <<REORG_PCT>>;
DECLARE @RebuildPct     decimal(5,1)  = <<REBUILD_PCT>>;
DECLARE @CanOnline      bit           =
    CASE WHEN CAST(SERVERPROPERTY(N|EngineEdition|) AS int) IN (3, 6, 8) THEN 1 ELSE 0 END;

CREATE TABLE #idx (
    db          sysname      NOT NULL,
    schema_name sysname      NOT NULL,
    table_name  sysname      NOT NULL,
    index_name  sysname      NOT NULL,
    frag_pct    decimal(5,1) NOT NULL,
    pages       bigint       NOT NULL,
    action      varchar(10)  NOT NULL
);

DECLARE @db  sysname, @sql nvarchar(max);
DECLARE db_c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4 AND state_desc = N|ONLINE|
      AND is_read_only = 0 AND source_database_id IS NULL
    ORDER BY name;
OPEN db_c;
FETCH NEXT FROM db_c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N|USE | + QUOTENAME(@db) + N|;
INSERT INTO #idx (db, schema_name, table_name, index_name, frag_pct, pages, action)
SELECT DB_NAME(), s.name, t.name, i.name,
       ips.avg_fragmentation_in_percent, ips.page_count,
       CASE WHEN ips.avg_fragmentation_in_percent >= | + CAST(@RebuildPct AS nvarchar(10)) + N|
            THEN ||REBUILD|| ELSE ||REORGANIZE|| END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N||LIMITED||) ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables  t ON i.object_id   = t.object_id
JOIN sys.schemas s ON t.schema_id   = s.schema_id
WHERE ips.page_count >= | + CAST(@MinPageCount AS nvarchar(10)) + N|
  AND ips.avg_fragmentation_in_percent >= | + CAST(@ReorgPct AS nvarchar(10)) + N|
  AND i.name IS NOT NULL AND i.is_disabled = 0 AND t.is_ms_shipped = 0;|;
    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_c INTO @db;
END
CLOSE db_c;
DEALLOCATE db_c;

DECLARE @schema sysname, @table sysname, @index sysname, @action varchar(10);
DECLARE idx_c CURSOR LOCAL FAST_FORWARD FOR
    SELECT db, schema_name, table_name, index_name, action
    FROM #idx ORDER BY db, frag_pct DESC;
OPEN idx_c;
FETCH NEXT FROM idx_c INTO @db, @schema, @table, @index, @action;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @action = |REBUILD|
        SET @sql = N|USE [| + @db + N|]; ALTER INDEX | + QUOTENAME(@index)
            + N| ON | + QUOTENAME(@schema) + N|.| + QUOTENAME(@table)
            + CASE WHEN @CanOnline = 1
                   THEN N| REBUILD WITH (ONLINE = ON);|
                   ELSE N| REBUILD;|
              END;
    ELSE
        SET @sql = N|USE [| + @db + N|]; ALTER INDEX | + QUOTENAME(@index)
            + N| ON | + QUOTENAME(@schema) + N|.| + QUOTENAME(@table) + N| REORGANIZE;|;
    EXEC sp_executesql @sql;
    FETCH NEXT FROM idx_c INTO @db, @schema, @table, @index, @action;
END
CLOSE idx_c;
DEALLOCATE idx_c;

DROP TABLE #idx;'
, N'|', NCHAR(39));

-- Substitute threshold values (determined at generation time)
SET @idxCmd = REPLACE(@idxCmd, N'<<MIN_PAGES>>', CAST(@MinPageCount AS nvarchar(10)));
SET @idxCmd = REPLACE(@idxCmd, N'<<REORG_PCT>>',  CAST(@FragReorgThreshold AS nvarchar(10)));
SET @idxCmd = REPLACE(@idxCmd, N'<<REBUILD_PCT>>', CAST(@FragRebuildThreshold AS nvarchar(10)));

-- ── Step command: statistics update ──────────────────────────────────────────
DECLARE @statsCmd nvarchar(max) = REPLACE(
N'SET NOCOUNT ON;
DECLARE @db sysname, @sql nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4 AND state_desc = N|ONLINE| AND is_read_only = 0
    ORDER BY name;
OPEN c;
FETCH NEXT FROM c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N|USE [| + @db + N|]; EXEC sp_updatestats;|;
    EXEC sp_executesql @sql;
    FETCH NEXT FROM c INTO @db;
END
CLOSE c;
DEALLOCATE c;'
, N'|', NCHAR(39));

-- ═══════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- =================================================================' + @crlf +
    N'-- Generated by Generate-IndexMaintenanceJobs.sql' + @crlf +
    N'-- Server         : ' + @@SERVERNAME + @crlf +
    N'-- Reorg threshold: ' + CAST(@FragReorgThreshold AS nvarchar(10)) + N'%' + @crlf +
    N'-- Rebuild threshold: ' + CAST(@FragRebuildThreshold AS nvarchar(10)) + N'%' + @crlf +
    N'-- Min page count : ' + CAST(@MinPageCount AS nvarchar(10)) + @crlf +
    N'-- Generated      : ' + CONVERT(nvarchar(20), GETDATE(), 120) + @crlf +
    N'-- =================================================================' + @crlf +
    @crlf +
    N'USE msdb;' + @crlf +
    N'GO' + @crlf;

-- Category
SET @ddl +=
    @crlf +
    N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories' + @crlf +
    N'               WHERE name = N' + @q + @CategoryName + @q + N' AND category_class = 1)' + @crlf +
    N'    EXEC msdb.dbo.sp_add_category' + @crlf +
    N'        @class = N' + @q + N'JOB' + @q + N', @type = N' + @q + N'LOCAL' + @q
        + N', @name = N' + @q + @CategoryName + @q + N';' + @crlf +
    N'GO' + @crlf;

-- ── Job 1: DBA - Index Maintenance ───────────────────────────────────────────
SET @ddl +=
    @crlf +
    N'-- ==================================================================' + @crlf +
    N'-- Job: DBA - Index Maintenance' + @crlf +
    N'-- Schedule: weekly, Sunday at ' + CAST(@MaintScheduleHour AS nvarchar(2)) + N':00' + @crlf +
    N'-- ==================================================================' + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + N'DBA - Index Maintenance' + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job' + @crlf +
    N'        @job_name              = N' + @q + N'DBA - Index Maintenance' + @q + N',' + @crlf +
    N'        @delete_unused_schedule = 1;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_job' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Index Maintenance' + @q + N',' + @crlf +
    N'    @enabled           = 1,' + @crlf +
    N'    @owner_login_name  = N' + @q + @JobOwner + @q + N',' + @crlf +
    N'    @category_name     = N' + @q + @CategoryName + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobstep' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Index Maintenance' + @q + N',' + @crlf +
    N'    @step_id           = 1,' + @crlf +
    N'    @step_name         = N' + @q + N'Rebuild and reorganize fragmented indexes' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N',' + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N',' + @crlf +
    N'    @command           = N' + @q + REPLACE(@idxCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 0,' + @crlf +
    N'    @on_success_action = 1,' + @crlf +
    N'    @on_fail_action    = 2;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_schedule' + @crlf +
    N'    @schedule_name          = N' + @q + N'DBA - Index Maintenance Weekly Sun '
        + CAST(@MaintScheduleHour AS nvarchar(2)) + N':00' + @q + N',' + @crlf +
    N'    @freq_type              = 8,' + @crlf +
    N'    @freq_interval          = 1,' + @crlf +    -- 1 = Sunday
    N'    @freq_recurrence_factor = 1,' + @crlf +
    N'    @active_start_time      = ' + CAST(@maintSchedTS AS nvarchar(10)) + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_attach_schedule' + @crlf +
    N'    @job_name      = N' + @q + N'DBA - Index Maintenance' + @q + N',' + @crlf +
    N'    @schedule_name = N' + @q + N'DBA - Index Maintenance Weekly Sun '
        + CAST(@MaintScheduleHour AS nvarchar(2)) + N':00' + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + N'DBA - Index Maintenance' + @q + N';' + @crlf +
    N'GO' + @crlf;

-- ── Job 2: DBA - Statistics Update ───────────────────────────────────────────
SET @ddl +=
    @crlf +
    N'-- ==================================================================' + @crlf +
    N'-- Job: DBA - Statistics Update' + @crlf +
    N'-- Schedule: weekly, Saturday at ' + CAST(@StatsScheduleHour AS nvarchar(2)) + N':00' + @crlf +
    N'-- Note: sp_updatestats only updates stats where rows have changed.' + @crlf +
    N'-- ==================================================================' + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + N'DBA - Statistics Update' + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job' + @crlf +
    N'        @job_name              = N' + @q + N'DBA - Statistics Update' + @q + N',' + @crlf +
    N'        @delete_unused_schedule = 1;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_job' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Statistics Update' + @q + N',' + @crlf +
    N'    @enabled           = 1,' + @crlf +
    N'    @owner_login_name  = N' + @q + @JobOwner + @q + N',' + @crlf +
    N'    @category_name     = N' + @q + @CategoryName + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobstep' + @crlf +
    N'    @job_name          = N' + @q + N'DBA - Statistics Update' + @q + N',' + @crlf +
    N'    @step_id           = 1,' + @crlf +
    N'    @step_name         = N' + @q + N'Update statistics on all user databases' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N',' + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N',' + @crlf +
    N'    @command           = N' + @q + REPLACE(@statsCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 0,' + @crlf +
    N'    @on_success_action = 1,' + @crlf +
    N'    @on_fail_action    = 2;' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_schedule' + @crlf +
    N'    @schedule_name          = N' + @q + N'DBA - Statistics Update Weekly Sat '
        + CAST(@StatsScheduleHour AS nvarchar(2)) + N':00' + @q + N',' + @crlf +
    N'    @freq_type              = 8,' + @crlf +
    N'    @freq_interval          = 64,' + @crlf +   -- 64 = Saturday
    N'    @freq_recurrence_factor = 1,' + @crlf +
    N'    @active_start_time      = ' + CAST(@statsSchedTS AS nvarchar(10)) + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_attach_schedule' + @crlf +
    N'    @job_name      = N' + @q + N'DBA - Statistics Update' + @q + N',' + @crlf +
    N'    @schedule_name = N' + @q + N'DBA - Statistics Update Weekly Sat '
        + CAST(@StatsScheduleHour AS nvarchar(2)) + N':00' + @q + N';' + @crlf +
    @crlf +
    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + N'DBA - Statistics Update' + @q + N';' + @crlf +
    N'GO' + @crlf;

SELECT @ddl AS ddl;
