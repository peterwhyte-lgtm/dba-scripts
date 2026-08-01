/*
Script Name : Generate-CollectorJob-DatabaseGrowth
Category    : collectors
Purpose     : Generates DDL to create the DBA - Collect Database Growth SQL Agent job.
              Creates the target database and a system-versioned (temporal) collector table
              if absent, then outputs T-SQL to install a recurring database file size MERGE job.
              Each run upserts current file sizes into DatabaseGrowthCurrent — SQL Server
              automatically records every change in the paired history table.
              Query DatabaseGrowthCurrent FOR SYSTEM_TIME BETWEEN to retrieve historical
              file sizes for trend analysis and growth forecasting.
              Edit parameters, review output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : sysadmin (to run generated DDL); VIEW ANY DATABASE, VIEW DATABASE STATE at job runtime
Notes       : Default interval: every 60 minutes. growth_status flags AT_LIMIT / NEAR_LIMIT / UNLIMITED.
              Requires SQL Server 2016 or later (temporal table support).
              If upgrading from the non-temporal version, drop collector.DatabaseGrowth manually first.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase  sysname       = N'DBAMonitor';
DECLARE @JobOwner        sysname       = N'sa';
DECLARE @CategoryName    nvarchar(128) = N'DBA Collectors';
DECLARE @IntervalMinutes int           = 60;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q       nchar(1)      = NCHAR(39);
DECLARE @crlf    nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl     nvarchar(max) = N'';
DECLARE @jobName sysname       = N'DBA - Collect Database Growth';
DECLARE @stepCmd nvarchar(max);

-- ── Step command (| = single-quote placeholder) ────────────────────────────────
SET @stepCmd = REPLACE(
N'SET NOCOUNT ON;
MERGE [<<DB>>].[collector].[DatabaseGrowthCurrent] AS target
USING (
    SELECT
        @@SERVERNAME                                                     AS server_name,
        d.name COLLATE DATABASE_DEFAULT                                  AS database_name,
        d.state_desc COLLATE DATABASE_DEFAULT                            AS database_state,
        d.recovery_model_desc COLLATE DATABASE_DEFAULT                   AS recovery_model_desc,
        mf.name COLLATE DATABASE_DEFAULT                                 AS logical_name,
        mf.physical_name,
        mf.type_desc                                                     AS file_type,
        CAST(mf.size * 8.0 / 1024 AS decimal(10,2))                     AS file_size_mb,
        CASE WHEN mf.max_size IN (-1, 268435456)
             THEN NULL
             ELSE CAST((mf.max_size - mf.size) * 8.0 / 1024 AS decimal(10,2))
             END                                                         AS space_to_limit_mb,
        CASE WHEN mf.is_percent_growth = 1
             THEN CAST(mf.growth AS varchar(10)) + |%|
             ELSE CAST(mf.growth * 8 / 1024 AS varchar(10)) + | MB|
             END                                                         AS autogrowth,
        mf.is_percent_growth,
        CASE WHEN mf.max_size IN (-1, 268435456)
             THEN NULL
             ELSE CAST(mf.max_size * 8.0 / 1024 AS decimal(10,2))
             END                                                         AS growth_limit_mb,
        CASE
            WHEN mf.max_size IN (-1, 268435456)                         THEN |UNLIMITED|
            WHEN mf.size >= mf.max_size                                 THEN |AT_LIMIT|
            WHEN (mf.max_size - mf.size) * 8.0 / 1024 < 1024
                 AND mf.max_size NOT IN (-1, 268435456)                 THEN |NEAR_LIMIT|
            ELSE |OK|
        END                                                              AS growth_status
    FROM sys.master_files mf
    JOIN sys.databases    d  ON d.database_id = mf.database_id
    WHERE d.state_desc = |ONLINE|
) AS source
ON  target.server_name   = source.server_name
AND target.database_name = source.database_name
AND target.logical_name  = source.logical_name
WHEN MATCHED AND (
    target.file_size_mb   <> source.file_size_mb   OR
    target.growth_status  <> source.growth_status  OR
    target.database_state <> source.database_state OR
    ISNULL(target.growth_limit_mb,    -1) <> ISNULL(source.growth_limit_mb,    -1) OR
    ISNULL(target.space_to_limit_mb,  -1) <> ISNULL(source.space_to_limit_mb,  -1)
) THEN UPDATE SET
    database_state      = source.database_state,
    recovery_model_desc = source.recovery_model_desc,
    physical_name       = source.physical_name,
    file_type           = source.file_type,
    file_size_mb        = source.file_size_mb,
    space_to_limit_mb   = source.space_to_limit_mb,
    autogrowth          = source.autogrowth,
    is_percent_growth   = source.is_percent_growth,
    growth_limit_mb     = source.growth_limit_mb,
    growth_status       = source.growth_status
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server_name, database_name, database_state, recovery_model_desc,
            logical_name, physical_name, file_type, file_size_mb,
            space_to_limit_mb, autogrowth, is_percent_growth,
            growth_limit_mb, growth_status)
    VALUES (source.server_name, source.database_name, source.database_state,
            source.recovery_model_desc, source.logical_name, source.physical_name,
            source.file_type, source.file_size_mb, source.space_to_limit_mb,
            source.autogrowth, source.is_percent_growth, source.growth_limit_mb,
            source.growth_status);'
, N'|', NCHAR(39));

SET @stepCmd = REPLACE(@stepCmd, N'<<DB>>', @TargetDatabase);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- ================================================================' + @crlf +
    N'-- Generated by Generate-CollectorJob-DatabaseGrowth.sql'            + @crlf +
    N'-- Server    : ' + @@SERVERNAME                                      + @crlf +
    N'-- Target DB : ' + @TargetDatabase                                   + @crlf +
    N'-- Generated : ' + CONVERT(nvarchar(20), GETDATE(), 120)             + @crlf +
    N'-- ================================================================' + @crlf + @crlf;

-- ── 1. Target database ────────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N' + @q + @TargetDatabase + @q + N')' + @crlf +
    N'    CREATE DATABASE [' + @TargetDatabase + N'];'                                               + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 2. Collector schema ───────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (SELECT 1 FROM [' + @TargetDatabase + N'].sys.schemas WHERE name = N' + @q + N'collector' + @q + N')' + @crlf +
    N'    EXEC [' + @TargetDatabase + N'].sys.sp_executesql N' + @q + N'CREATE SCHEMA collector' + @q + N';'              + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 3. DatabaseGrowthCurrent temporal table ───────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (' + @crlf +
    N'    SELECT 1 FROM [' + @TargetDatabase + N'].sys.objects o'                                                                    + @crlf +
    N'    JOIN [' + @TargetDatabase + N'].sys.schemas s ON s.schema_id = o.schema_id'                                                + @crlf +
    N'    WHERE o.name = N' + @q + N'DatabaseGrowthCurrent' + @q + N' AND s.name = N' + @q + N'collector' + @q + N')'              + @crlf +
    N'BEGIN' + @crlf +
    N'CREATE TABLE [' + @TargetDatabase + N'].[collector].[DatabaseGrowthCurrent] ('                  + @crlf +
    N'    server_name          nvarchar(128)  NOT NULL,'                                               + @crlf +
    N'    database_name        nvarchar(128)  NOT NULL,'                                               + @crlf +
    N'    logical_name         nvarchar(128)  NOT NULL,'                                               + @crlf +
    N'    database_state       nvarchar(60)   NULL,'                                                   + @crlf +
    N'    recovery_model_desc  nvarchar(60)   NULL,'                                                   + @crlf +
    N'    physical_name        nvarchar(260)  NULL,'                                                   + @crlf +
    N'    file_type            nvarchar(60)   NULL,'                                                   + @crlf +
    N'    file_size_mb         decimal(10,2)  NULL,'                                                   + @crlf +
    N'    space_to_limit_mb    decimal(10,2)  NULL,'                                                   + @crlf +
    N'    autogrowth           nvarchar(20)   NULL,'                                                   + @crlf +
    N'    is_percent_growth    bit            NULL,'                                                   + @crlf +
    N'    growth_limit_mb      decimal(10,2)  NULL,'                                                   + @crlf +
    N'    growth_status        nvarchar(20)   NULL,'                                                   + @crlf +
    N'    SysStartTime         datetime2(2)   GENERATED ALWAYS AS ROW START NOT NULL,'                + @crlf +
    N'    SysEndTime           datetime2(2)   GENERATED ALWAYS AS ROW END   NOT NULL,'                + @crlf +
    N'    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),'                                         + @crlf +
    N'    CONSTRAINT [PK_DatabaseGrowthCurrent]'                                                      + @crlf +
    N'        PRIMARY KEY (server_name, database_name, logical_name)'                                 + @crlf +
    N') WITH (SYSTEM_VERSIONING = ON ('                                                               + @crlf +
    N'    HISTORY_TABLE        = [collector].[DatabaseGrowthHistory],'                                + @crlf +
    N'    DATA_CONSISTENCY_CHECK = ON));'                                                              + @crlf +
    N'END' + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 4. Agent category ─────────────────────────────────────────────────────────
SET @ddl +=
    N'USE msdb;' + @crlf +
    N'GO' + @crlf + @crlf +
    N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N' + @q + @CategoryName + @q + N' AND category_class = 1)' + @crlf +
    N'    EXEC msdb.dbo.sp_add_category'                                                                                             + @crlf +
    N'        @class = N' + @q + N'JOB' + @q + N', @type = N' + @q + N'LOCAL' + @q + N', @name = N' + @q + @CategoryName + @q + N';' + @crlf +
    N'GO' + @crlf + @crlf;

-- ── 5. Job + step + schedule ──────────────────────────────────────────────────
SET @ddl +=
    N'-- Job: ' + @jobName + @crlf +
    N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N' + @q + @jobName + @q + N')' + @crlf +
    N'    EXEC msdb.dbo.sp_delete_job @job_name = N' + @q + @jobName + @q + N', @delete_unused_schedule = 1;' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_job'                                                    + @crlf +
    N'    @job_name         = N' + @q + @jobName + @q + N','                       + @crlf +
    N'    @enabled          = 1,'                                                   + @crlf +
    N'    @owner_login_name = N' + @q + @JobOwner + @q + N','                      + @crlf +
    N'    @category_name    = N' + @q + @CategoryName + @q + N';'                  + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_jobstep'                                                + @crlf +
    N'    @job_name          = N' + @q + @jobName + @q + N','                      + @crlf +
    N'    @step_id           = 1,'                                                  + @crlf +
    N'    @step_name         = N' + @q + N'Merge database file sizes' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N','                       + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N','                     + @crlf +
    N'    @command           = N' + @q + REPLACE(@stepCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 0,'                                                  + @crlf +
    N'    @on_success_action = 1,'                                                  + @crlf +
    N'    @on_fail_action    = 2;'                                                  + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_schedule'                                               + @crlf +
    N'    @schedule_name        = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N',' + @crlf +
    N'    @freq_type            = 4,'                                               + @crlf +
    N'    @freq_interval        = 1,'                                               + @crlf +
    N'    @freq_subday_type     = 4,'                                               + @crlf +
    N'    @freq_subday_interval = ' + CAST(@IntervalMinutes AS nvarchar(5)) + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_attach_schedule'                                            + @crlf +
    N'    @job_name      = N' + @q + @jobName + @q + N','                          + @crlf +
    N'    @schedule_name = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + @jobName + @q + N';'   + @crlf +
    N'GO' + @crlf;

SELECT @ddl AS ddl;
