/*
Script Name : Generate-CollectorJob-AgHealth
Category    : collectors
Purpose     : Generates DDL to create the DBA - Collect AG Health SQL Agent job.
              Creates the target database and a system-versioned (temporal) collector table
              if absent, then outputs T-SQL to install a recurring AG replica state MERGE job.
              Each run upserts current replica and database synchronization state — SQL Server
              automatically records every change in the paired history table, capturing exactly
              when replicas became disconnected, unsynchronized, or changed role.
              On instances with no AG configured, a NO_AG sentinel row is inserted once
              so the job always succeeds and the table remains queryable.
              Edit parameters, review output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : sysadmin (to run generated DDL); VIEW SERVER STATE at job runtime
Notes       : Default interval: every 5 minutes. Requires SQL Server 2016+ (temporal support).
              History is written only when state/health/connected columns change — lag metrics
              (queue sizes, timing) are not tracked in history to avoid noise.
              Filter WHERE ag_name <> 'NO_AG' when querying production replica data.
              If upgrading from the non-temporal version, drop collector.AgHealth manually first.
              PK is NONCLUSTERED deliberately: the four key columns are all identifiers
              (sysname, nvarchar(128)), so the key is 1024 bytes. That exceeds SQL Server's
              900-byte CLUSTERED index key limit but fits the 1700-byte nonclustered limit.
              Narrowing the columns instead would truncate legal 128-character identifiers.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase  sysname       = N'DBAMonitor';
DECLARE @JobOwner        sysname       = N'sa';
DECLARE @CategoryName    nvarchar(128) = N'DBA Collectors';
DECLARE @IntervalMinutes int           = 5;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q       nchar(1)      = NCHAR(39);
DECLARE @crlf    nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl     nvarchar(max) = N'';
DECLARE @jobName sysname       = N'DBA - Collect AG Health';
DECLARE @stepCmd nvarchar(max);

-- ── Step command (| = single-quote placeholder) ────────────────────────────────
SET @stepCmd = REPLACE(
N'SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    MERGE [<<DB>>].[collector].[AgHealthCurrent] AS target
    USING (SELECT @@SERVERNAME, |NO_AG|, ||, ||)
          AS source(server_name, ag_name, replica_server_name, database_name)
    ON  target.server_name         = source.server_name
    AND target.ag_name             = source.ag_name
    AND target.replica_server_name = source.replica_server_name
    AND target.database_name       = source.database_name
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (server_name, ag_name, replica_server_name, database_name)
        VALUES (source.server_name, source.ag_name,
                source.replica_server_name, source.database_name);
    RETURN;
END

MERGE [<<DB>>].[collector].[AgHealthCurrent] AS target
USING (
    SELECT
        @@SERVERNAME                                                    AS server_name,
        ag.name                                                         AS ag_name,
        ar.replica_server_name,
        ISNULL(adb.database_name, ||)                                   AS database_name,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc,
        ars.last_connect_error_description,
        drs.synchronization_state_desc                                  AS db_synchronization_state_desc,
        drs.synchronization_health_desc                                 AS db_synchronization_health_desc,
        drs.log_send_queue_size                                         AS log_send_queue_kb,
        drs.log_send_rate                                               AS log_send_rate_kb_s,
        drs.redo_queue_size                                             AS redo_queue_kb,
        drs.redo_rate                                                   AS redo_rate_kb_s,
        drs.last_sent_time,
        drs.last_received_time,
        drs.last_hardened_time,
        drs.last_redone_time,
        drs.last_commit_time
    FROM sys.availability_groups                     ag
    JOIN sys.availability_replicas                   ar  ON ar.group_id    = ag.group_id
    JOIN sys.dm_hadr_availability_replica_states     ars ON ars.replica_id = ar.replica_id
    LEFT JOIN sys.dm_hadr_database_replica_states    drs ON drs.replica_id = ars.replica_id
    LEFT JOIN sys.availability_databases_cluster     adb ON adb.group_id   = ag.group_id
                                                        AND adb.group_database_id = drs.group_database_id
) AS source
ON  target.server_name         = source.server_name
AND target.ag_name             = source.ag_name
AND target.replica_server_name = source.replica_server_name
AND target.database_name       = source.database_name
WHEN MATCHED AND (
    ISNULL(target.role_desc,                      |_|) <> ISNULL(source.role_desc,                      |_|) OR
    ISNULL(target.operational_state_desc,         |_|) <> ISNULL(source.operational_state_desc,         |_|) OR
    ISNULL(target.connected_state_desc,           |_|) <> ISNULL(source.connected_state_desc,           |_|) OR
    ISNULL(target.synchronization_health_desc,    |_|) <> ISNULL(source.synchronization_health_desc,    |_|) OR
    ISNULL(target.db_synchronization_state_desc,  |_|) <> ISNULL(source.db_synchronization_state_desc,  |_|) OR
    ISNULL(target.db_synchronization_health_desc, |_|) <> ISNULL(source.db_synchronization_health_desc, |_|)
) THEN UPDATE SET
    role_desc                      = source.role_desc,
    operational_state_desc         = source.operational_state_desc,
    connected_state_desc           = source.connected_state_desc,
    synchronization_health_desc    = source.synchronization_health_desc,
    last_connect_error_description = source.last_connect_error_description,
    db_synchronization_state_desc  = source.db_synchronization_state_desc,
    db_synchronization_health_desc = source.db_synchronization_health_desc,
    log_send_queue_kb              = source.log_send_queue_kb,
    log_send_rate_kb_s             = source.log_send_rate_kb_s,
    redo_queue_kb                  = source.redo_queue_kb,
    redo_rate_kb_s                 = source.redo_rate_kb_s,
    last_sent_time                 = source.last_sent_time,
    last_received_time             = source.last_received_time,
    last_hardened_time             = source.last_hardened_time,
    last_redone_time               = source.last_redone_time,
    last_commit_time               = source.last_commit_time
WHEN NOT MATCHED BY TARGET THEN
    INSERT (server_name, ag_name, replica_server_name, database_name,
            role_desc, operational_state_desc, connected_state_desc,
            synchronization_health_desc, last_connect_error_description,
            db_synchronization_state_desc, db_synchronization_health_desc,
            log_send_queue_kb, log_send_rate_kb_s,
            redo_queue_kb, redo_rate_kb_s,
            last_sent_time, last_received_time, last_hardened_time,
            last_redone_time, last_commit_time)
    VALUES (source.server_name, source.ag_name, source.replica_server_name,
            source.database_name, source.role_desc, source.operational_state_desc,
            source.connected_state_desc, source.synchronization_health_desc,
            source.last_connect_error_description, source.db_synchronization_state_desc,
            source.db_synchronization_health_desc, source.log_send_queue_kb,
            source.log_send_rate_kb_s, source.redo_queue_kb, source.redo_rate_kb_s,
            source.last_sent_time, source.last_received_time, source.last_hardened_time,
            source.last_redone_time, source.last_commit_time);'
, N'|', NCHAR(39));

SET @stepCmd = REPLACE(@stepCmd, N'<<DB>>', @TargetDatabase);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- ================================================================' + @crlf +
    N'-- Generated by Generate-CollectorJob-AgHealth.sql'                  + @crlf +
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

-- ── 3. AgHealthCurrent temporal table ─────────────────────────────────────────
SET @ddl +=
    N'IF NOT EXISTS (' + @crlf +
    N'    SELECT 1 FROM [' + @TargetDatabase + N'].sys.objects o'                                                              + @crlf +
    N'    JOIN [' + @TargetDatabase + N'].sys.schemas s ON s.schema_id = o.schema_id'                                          + @crlf +
    N'    WHERE o.name = N' + @q + N'AgHealthCurrent' + @q + N' AND s.name = N' + @q + N'collector' + @q + N')'              + @crlf +
    N'BEGIN' + @crlf +
    N'CREATE TABLE [' + @TargetDatabase + N'].[collector].[AgHealthCurrent] ('                 + @crlf +
    N'    server_name                      nvarchar(128)  NOT NULL,'                           + @crlf +
    N'    ag_name                          nvarchar(128)  NOT NULL,'                           + @crlf +
    N'    replica_server_name              nvarchar(128)  NOT NULL,'                           + @crlf +
    N'    database_name                    nvarchar(128)  NOT NULL,'                           + @crlf +
    N'    role_desc                        nvarchar(60)   NULL,'                               + @crlf +
    N'    operational_state_desc           nvarchar(60)   NULL,'                               + @crlf +
    N'    connected_state_desc             nvarchar(60)   NULL,'                               + @crlf +
    N'    synchronization_health_desc      nvarchar(60)   NULL,'                               + @crlf +
    N'    last_connect_error_description   nvarchar(1024) NULL,'                               + @crlf +
    N'    db_synchronization_state_desc    nvarchar(60)   NULL,'                               + @crlf +
    N'    db_synchronization_health_desc   nvarchar(60)   NULL,'                               + @crlf +
    N'    log_send_queue_kb                bigint         NULL,'                               + @crlf +
    N'    log_send_rate_kb_s               bigint         NULL,'                               + @crlf +
    N'    redo_queue_kb                    bigint         NULL,'                               + @crlf +
    N'    redo_rate_kb_s                   bigint         NULL,'                               + @crlf +
    N'    last_sent_time                   datetime2      NULL,'                               + @crlf +
    N'    last_received_time               datetime2      NULL,'                               + @crlf +
    N'    last_hardened_time               datetime2      NULL,'                               + @crlf +
    N'    last_redone_time                 datetime2      NULL,'                               + @crlf +
    N'    last_commit_time                 datetime2      NULL,'                               + @crlf +
    N'    SysStartTime                     datetime2(2)   GENERATED ALWAYS AS ROW START NOT NULL,' + @crlf +
    N'    SysEndTime                       datetime2(2)   GENERATED ALWAYS AS ROW END   NOT NULL,' + @crlf +
    N'    PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),'                                 + @crlf +
    N'    CONSTRAINT [PK_AgHealthCurrent]'                                                    + @crlf +
    N'        PRIMARY KEY NONCLUSTERED (server_name, ag_name, replica_server_name, database_name)'         + @crlf +
    N') WITH (SYSTEM_VERSIONING = ON ('                                                       + @crlf +
    N'    HISTORY_TABLE        = [collector].[AgHealthHistory],'                              + @crlf +
    N'    DATA_CONSISTENCY_CHECK = ON));'                                                      + @crlf +
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
    N'    @step_name         = N' + @q + N'Merge AG replica state' + @q + N','     + @crlf +
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
