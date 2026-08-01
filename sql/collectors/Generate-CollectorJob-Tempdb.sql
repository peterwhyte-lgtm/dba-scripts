/*
Script Name : Generate-CollectorJob-Tempdb
Category    : collectors
Purpose     : Generates DDL to create the DBA - Collect TempDB SQL Agent job.
              Creates the target database and collector.Tempdb table if absent,
              then outputs T-SQL to install a recurring TempDB space snapshot job.
              Captures file-level space (row_type = 'file') and top session consumers
              (row_type = 'session') in a single table using the row_type discriminator.
              Edit parameters, review output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : sysadmin (to run generated DDL); VIEW SERVER STATE, VIEW DATABASE STATE at job runtime
Notes       : Default interval: every 10 minutes.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase  sysname       = N'DBAMonitor';   -- created if absent
DECLARE @JobOwner        sysname       = N'sa';
DECLARE @CategoryName    nvarchar(128) = N'DBA Collectors';
DECLARE @IntervalMinutes int           = 10;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q       nchar(1)      = NCHAR(39);
DECLARE @crlf    nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl     nvarchar(max) = N'';
DECLARE @jobName sysname       = N'DBA - Collect TempDB';
DECLARE @stepCmd nvarchar(max);

-- ── Step command (| = single-quote placeholder) ────────────────────────────────
SET @stepCmd = REPLACE(
N'SET NOCOUNT ON;
INSERT INTO [<<DB>>].[collector].[Tempdb]
    (server_name, collection_time, row_type, file_name, physical_name, file_type,
     file_size_mb, total_allocated_mb, free_mb, user_objects_mb, internal_objects_mb,
     version_store_mb, mixed_extents_mb, session_id, login_name, host_name,
     program_name, session_user_objects_mb, session_internal_objects_mb)
SELECT
    @@SERVERNAME                                                            AS server_name,
    GETDATE()                                                               AS collection_time,
    |file|                                                                  AS row_type,
    f.name                                                                  AS file_name,
    f.physical_name,
    f.type_desc                                                             AS file_type,
    CAST(f.size * 8.0 / 1024 AS decimal(10,2))                             AS file_size_mb,
    CAST(fu.total_page_count                   * 8.0 / 1024 AS decimal(10,2)) AS total_allocated_mb,
    CAST(fu.unallocated_extent_page_count      * 8.0 / 1024 AS decimal(10,2)) AS free_mb,
    CAST(fu.user_object_reserved_page_count    * 8.0 / 1024 AS decimal(10,2)) AS user_objects_mb,
    CAST(fu.internal_object_reserved_page_count * 8.0 / 1024 AS decimal(10,2)) AS internal_objects_mb,
    CAST(fu.version_store_reserved_page_count  * 8.0 / 1024 AS decimal(10,2)) AS version_store_mb,
    CAST(fu.mixed_extent_page_count            * 8.0 / 1024 AS decimal(10,2)) AS mixed_extents_mb,
    NULL AS session_id,
    NULL AS login_name,
    NULL AS host_name,
    NULL AS program_name,
    NULL AS session_user_objects_mb,
    NULL AS session_internal_objects_mb
FROM tempdb.sys.dm_db_file_space_usage fu
JOIN tempdb.sys.database_files f ON f.file_id = fu.file_id

UNION ALL

SELECT
    server_name, collection_time, row_type, file_name, physical_name, file_type,
    file_size_mb, total_allocated_mb, free_mb, user_objects_mb, internal_objects_mb,
    version_store_mb, mixed_extents_mb, session_id, login_name, host_name,
    program_name, session_user_objects_mb, session_internal_objects_mb
FROM (
    SELECT TOP 10
        @@SERVERNAME                                                                                        AS server_name,
        GETDATE()                                                                                            AS collection_time,
        |session|                                                                                            AS row_type,
        NULL AS file_name, NULL AS physical_name, NULL AS file_type, NULL AS file_size_mb,
        NULL AS total_allocated_mb, NULL AS free_mb, NULL AS user_objects_mb,
        NULL AS internal_objects_mb, NULL AS version_store_mb, NULL AS mixed_extents_mb,
        su.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        CAST((su.user_objects_alloc_page_count - su.user_objects_dealloc_page_count) * 8.0 / 1024 AS decimal(10,2))     AS session_user_objects_mb,
        CAST((su.internal_objects_alloc_page_count - su.internal_objects_dealloc_page_count) * 8.0 / 1024 AS decimal(10,2)) AS session_internal_objects_mb
    FROM sys.dm_db_session_space_usage su
    JOIN sys.dm_exec_sessions s ON s.session_id = su.session_id
    WHERE su.session_id > 50
      AND (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) > 0
    ORDER BY (su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count) DESC
) AS top_sessions;'
, N'|', NCHAR(39));

SET @stepCmd = REPLACE(@stepCmd, N'<<DB>>', @TargetDatabase);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- ================================================================' + @crlf +
    N'-- Generated by Generate-CollectorJob-Tempdb.sql'                    + @crlf +
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

-- ── 3. Tempdb table ───────────────────────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (' + @crlf +
    N'    SELECT 1 FROM [' + @TargetDatabase + N'].sys.objects o'                                                        + @crlf +
    N'    JOIN [' + @TargetDatabase + N'].sys.schemas s ON s.schema_id = o.schema_id'                                    + @crlf +
    N'    WHERE o.name = N' + @q + N'Tempdb' + @q + N' AND s.name = N' + @q + N'collector' + @q + N')'                 + @crlf +
    N'CREATE TABLE [' + @TargetDatabase + N'].[collector].[Tempdb] ('                                                    + @crlf +
    N'    id                          bigint IDENTITY(1,1) PRIMARY KEY,'                                                  + @crlf +
    N'    server_name                 nvarchar(128) NOT NULL,'                                                             + @crlf +
    N'    collection_time             datetime2     NOT NULL,'                                                             + @crlf +
    N'    row_type                    nvarchar(10),'                                                                       + @crlf +
    N'    file_name                   nvarchar(128),'                                                                      + @crlf +
    N'    physical_name               nvarchar(260),'                                                                      + @crlf +
    N'    file_type                   nvarchar(60),'                                                                       + @crlf +
    N'    file_size_mb                decimal(10,2),'                                                                      + @crlf +
    N'    total_allocated_mb          decimal(10,2),'                                                                      + @crlf +
    N'    free_mb                     decimal(10,2),'                                                                      + @crlf +
    N'    user_objects_mb             decimal(10,2),'                                                                      + @crlf +
    N'    internal_objects_mb         decimal(10,2),'                                                                      + @crlf +
    N'    version_store_mb            decimal(10,2),'                                                                      + @crlf +
    N'    mixed_extents_mb            decimal(10,2),'                                                                      + @crlf +
    N'    session_id                  int,'                                                                                 + @crlf +
    N'    login_name                  nvarchar(128),'                                                                      + @crlf +
    N'    host_name                   nvarchar(128),'                                                                      + @crlf +
    N'    program_name                nvarchar(128),'                                                                      + @crlf +
    N'    session_user_objects_mb     decimal(10,2),'                                                                      + @crlf +
    N'    session_internal_objects_mb decimal(10,2)'                                                                       + @crlf +
    N');'                                                                                                                  + @crlf +
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
    N'    @step_name         = N' + @q + N'Snapshot TempDB space usage' + @q + N',' + @crlf +
    N'    @subsystem         = N' + @q + N'TSQL' + @q + N','                       + @crlf +
    N'    @database_name     = N' + @q + N'master' + @q + N','                     + @crlf +
    N'    @command           = N' + @q + REPLACE(@stepCmd, @q, @q + @q) + @q + N',' + @crlf +
    N'    @retry_attempts    = 0,'                                                  + @crlf +
    N'    @on_success_action = 1,'                                                  + @crlf +
    N'    @on_fail_action    = 2;'                                                  + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_schedule'                                               + @crlf +
    N'    @schedule_name        = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N',' + @crlf +
    N'    @freq_type            = 4,'                                               + @crlf +   -- daily recurring
    N'    @freq_interval        = 1,'                                               + @crlf +
    N'    @freq_subday_type     = 4,'                                               + @crlf +   -- minutes
    N'    @freq_subday_interval = ' + CAST(@IntervalMinutes AS nvarchar(5)) + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_attach_schedule'                                            + @crlf +
    N'    @job_name      = N' + @q + @jobName + @q + N','                          + @crlf +
    N'    @schedule_name = N' + @q + @jobName + N' Every ' + CAST(@IntervalMinutes AS nvarchar(5)) + N'min' + @q + N';' + @crlf + @crlf +

    N'EXEC msdb.dbo.sp_add_jobserver @job_name = N' + @q + @jobName + @q + N';'   + @crlf +
    N'GO' + @crlf;

SELECT @ddl AS ddl;
