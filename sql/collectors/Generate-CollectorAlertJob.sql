/*
Script Name : Generate-CollectorAlertJob
Category    : collectors
Purpose     : Generates DDL to create the DBA - Collector Alert SQL Agent job.
              The job queries [DBAMonitor].[collector].* tables, applies threshold
              checks, outputs findings, and RAISERRORs on any CRITICAL result
              (causing the step to fail and triggering Agent notification routing).
              Edit parameters, review output, then run on the target instance.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : sysadmin (to run generated DDL); SELECT on [DBAMonitor].[collector].* at job runtime
Notes       : Depends on the individual collector jobs already being installed and running.
              Thresholds match Invoke-CollectorAlert.ps1:
                wait-stats  PAGEIOLATCH_* >40% CRITICAL / >20% WARNING
                wait-stats  RESOURCE_SEMAPHORE >20% CRITICAL / >10% WARNING
                wait-stats  LCK_M_* >30% CRITICAL / >15% WARNING
                blocking    any event in last 2h WARNING; max wait >60s CRITICAL
                tempdb      version_store_mb >10000 CRITICAL / >2000 WARNING
                tempdb      free_mb <100 CRITICAL / <500 WARNING
                db-growth   AT_LIMIT CRITICAL / NEAR_LIMIT WARNING
                vlf-count   >10000 CRITICAL / >1000 WARNING
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase  sysname       = N'DBAMonitor';
DECLARE @JobOwner        sysname       = N'sa';
DECLARE @CategoryName    nvarchar(128) = N'DBA Collectors';
DECLARE @IntervalMinutes int           = 30;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @q       nchar(1)      = NCHAR(39);
DECLARE @crlf    nvarchar(2)   = CHAR(13) + CHAR(10);
DECLARE @ddl     nvarchar(max) = N'';
DECLARE @jobName sysname       = N'DBA - Collector Alert';
DECLARE @stepCmd nvarchar(max);

-- ── Step command (| = single-quote placeholder) ────────────────────────────────
SET @stepCmd = REPLACE(
N'SET NOCOUNT ON;
CREATE TABLE #findings (severity nvarchar(10), collector nvarchar(30), check_name nvarchar(60), detail nvarchar(500));

-- ── Wait-stats delta ──────────────────────────────────────────────────────────
DECLARE @ws_t1 datetime2, @ws_t2 datetime2, @ws_start1 datetime2, @ws_start2 datetime2;
DECLARE @ws_total bigint, @ws_pct decimal(5,1), @ws_int nvarchar(80);

SELECT TOP 1 @ws_t2 = collection_time FROM [<<DB>>].[collector].[WaitStats]
WHERE server_name = @@SERVERNAME ORDER BY collection_time DESC;
SELECT TOP 1 @ws_t1 = collection_time FROM [<<DB>>].[collector].[WaitStats]
WHERE server_name = @@SERVERNAME AND collection_time < @ws_t2 ORDER BY collection_time DESC;

IF @ws_t1 IS NOT NULL
BEGIN
    SELECT @ws_start1 = MIN(sqlserver_start_time) FROM [<<DB>>].[collector].[WaitStats]
    WHERE server_name = @@SERVERNAME AND collection_time = @ws_t1;
    SELECT @ws_start2 = MIN(sqlserver_start_time) FROM [<<DB>>].[collector].[WaitStats]
    WHERE server_name = @@SERVERNAME AND collection_time = @ws_t2;

    SET @ws_int = CONVERT(nvarchar(20), @ws_t1, 120) + N| -> | + CONVERT(nvarchar(20), @ws_t2, 120);

    IF @ws_start1 IS NOT NULL AND @ws_start1 = @ws_start2
    BEGIN
        CREATE TABLE #ws_deltas (wait_type nvarchar(60), delta_ms bigint);
        INSERT INTO #ws_deltas
        SELECT s2.wait_type, s2.wait_time_ms - s1.wait_time_ms
        FROM [<<DB>>].[collector].[WaitStats] s2
        JOIN [<<DB>>].[collector].[WaitStats] s1
            ON s1.server_name = s2.server_name AND s1.collection_time = @ws_t1 AND s1.wait_type = s2.wait_type
        WHERE s2.server_name = @@SERVERNAME AND s2.collection_time = @ws_t2 AND s2.wait_time_ms > s1.wait_time_ms;

        SELECT @ws_total = SUM(delta_ms) FROM #ws_deltas;

        IF ISNULL(@ws_total, 0) > 0
        BEGIN
            SELECT @ws_pct = CAST(ISNULL(SUM(delta_ms), 0) * 100.0 / @ws_total AS decimal(5,1))
            FROM #ws_deltas WHERE wait_type LIKE |PAGEIOLATCH_%|;
            IF ISNULL(@ws_pct, 0) > 20
                INSERT INTO #findings VALUES (CASE WHEN @ws_pct > 40 THEN |CRITICAL| ELSE |WARNING| END,
                    |wait-stats|, |PAGEIOLATCH_*|, |PAGEIOLATCH_* = | + CAST(@ws_pct AS nvarchar(10)) + |% - | + @ws_int);

            SELECT @ws_pct = CAST(ISNULL(SUM(delta_ms), 0) * 100.0 / @ws_total AS decimal(5,1))
            FROM #ws_deltas WHERE wait_type = |RESOURCE_SEMAPHORE|;
            IF ISNULL(@ws_pct, 0) > 10
                INSERT INTO #findings VALUES (CASE WHEN @ws_pct > 20 THEN |CRITICAL| ELSE |WARNING| END,
                    |wait-stats|, |RESOURCE_SEMAPHORE|, |RESOURCE_SEMAPHORE = | + CAST(@ws_pct AS nvarchar(10)) + |% - | + @ws_int);

            SELECT @ws_pct = CAST(ISNULL(SUM(delta_ms), 0) * 100.0 / @ws_total AS decimal(5,1))
            FROM #ws_deltas WHERE wait_type LIKE |LCK_M_%|;
            IF ISNULL(@ws_pct, 0) > 15
                INSERT INTO #findings VALUES (CASE WHEN @ws_pct > 30 THEN |CRITICAL| ELSE |WARNING| END,
                    |wait-stats|, |LCK_M_*|, |LCK_M_* = | + CAST(@ws_pct AS nvarchar(10)) + |% - | + @ws_int);
        END;
        DROP TABLE #ws_deltas;
    END
    ELSE
        INSERT INTO #findings VALUES (|WARNING|, |wait-stats|, |restart detected|,
            |sqlserver_start_time changed between snapshots - delta skipped|);
END;

-- ── Blocking ──────────────────────────────────────────────────────────────────
DECLARE @blk_count int, @blk_max_ms bigint;
SELECT @blk_count = COUNT(*), @blk_max_ms = MAX(wait_time_ms)
FROM [<<DB>>].[collector].[Blocking]
WHERE server_name = @@SERVERNAME AND collection_time >= DATEADD(HOUR, -2, GETDATE());
IF ISNULL(@blk_count, 0) > 0
    INSERT INTO #findings VALUES (
        CASE WHEN @blk_max_ms > 60000 THEN |CRITICAL| ELSE |WARNING| END,
        |blocking|, |blocking events|,
        CAST(@blk_count AS nvarchar(10)) + | event(s) in last 2h; max wait |
            + CAST(@blk_max_ms / 1000 AS nvarchar(10)) + |s|
    );

-- ── TempDB ───────────────────────────────────────────────────────────────────
DECLARE @latest_tdb datetime2;
SELECT @latest_tdb = MAX(collection_time) FROM [<<DB>>].[collector].[Tempdb] WHERE server_name = @@SERVERNAME;
IF @latest_tdb IS NOT NULL
BEGIN
    INSERT INTO #findings
    SELECT CASE WHEN version_store_mb > 10000 THEN |CRITICAL| ELSE |WARNING| END,
        |tempdb|, |version_store_mb|,
        file_name + |: version_store_mb = | + CAST(version_store_mb AS nvarchar(20)) + | MB|
    FROM [<<DB>>].[collector].[Tempdb]
    WHERE server_name = @@SERVERNAME AND collection_time = @latest_tdb
      AND row_type = |file| AND file_type = |ROWS| AND version_store_mb > 2000;

    INSERT INTO #findings
    SELECT CASE WHEN free_mb < 100 THEN |CRITICAL| ELSE |WARNING| END,
        |tempdb|, |free_mb|,
        file_name + |: free_mb = | + CAST(free_mb AS nvarchar(20)) + | MB|
    FROM [<<DB>>].[collector].[Tempdb]
    WHERE server_name = @@SERVERNAME AND collection_time = @latest_tdb
      AND row_type = |file| AND file_type = |ROWS| AND free_mb < 500;
END;

-- ── Database growth ───────────────────────────────────────────────────────────
-- DatabaseGrowthCurrent is a system-versioned temporal table: it holds exactly one
-- current row per key already, there is no collection_time column to filter on.
IF EXISTS (SELECT 1 FROM [<<DB>>].[collector].[DatabaseGrowthCurrent] WHERE server_name = @@SERVERNAME)
    INSERT INTO #findings
    SELECT CASE growth_status WHEN |AT_LIMIT| THEN |CRITICAL| ELSE |WARNING| END,
        |database-growth|, growth_status,
        |[| + database_name + |] | + logical_name + |: | + CAST(file_size_mb AS nvarchar(20)) + | MB|
        + CASE WHEN growth_limit_mb IS NOT NULL THEN | / | + CAST(growth_limit_mb AS nvarchar(20)) + | MB limit| ELSE || END
    FROM [<<DB>>].[collector].[DatabaseGrowthCurrent]
    WHERE server_name = @@SERVERNAME
      AND growth_status IN (|AT_LIMIT|, |NEAR_LIMIT|);

-- ── VLF count ─────────────────────────────────────────────────────────────────
-- Same story: VlfCountCurrent is system-versioned, already current, no collection_time.
IF EXISTS (SELECT 1 FROM [<<DB>>].[collector].[VlfCountCurrent] WHERE server_name = @@SERVERNAME)
    INSERT INTO #findings
    SELECT CASE WHEN vlf_count > 10000 THEN |CRITICAL| ELSE |WARNING| END,
        |vlf-count|, |vlf_count|,
        |[| + database_name + |] | + CAST(vlf_count AS nvarchar(10)) + | VLFs; reuse_wait: | + log_reuse_wait_desc
    FROM [<<DB>>].[collector].[VlfCountCurrent]
    WHERE server_name = @@SERVERNAME AND vlf_count > 1000;

-- ── Output ────────────────────────────────────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM #findings)
    PRINT |All checks passed.|;
ELSE
    SELECT severity, collector, check_name, detail
    FROM #findings
    ORDER BY CASE severity WHEN |CRITICAL| THEN 1 ELSE 2 END, collector;

IF EXISTS (SELECT 1 FROM #findings WHERE severity = |CRITICAL|)
    RAISERROR(|Collector alert: CRITICAL findings detected - review job step output.|, 16, 1);'
, N'|', NCHAR(39));

SET @stepCmd = REPLACE(@stepCmd, N'<<DB>>', @TargetDatabase);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DDL output
-- ═══════════════════════════════════════════════════════════════════════════════
SET @ddl =
    N'-- ================================================================' + @crlf +
    N'-- Generated by Generate-CollectorAlertJob.sql'                       + @crlf +
    N'-- Server    : ' + @@SERVERNAME                                       + @crlf +
    N'-- Target DB : ' + @TargetDatabase                                    + @crlf +
    N'-- Generated : ' + CONVERT(nvarchar(20), GETDATE(), 120)              + @crlf +
    N'-- ================================================================' + @crlf + @crlf;

-- ── Agent category ────────────────────────────────────────────────────────────
SET @ddl +=
    N'USE msdb;' + @crlf +
    N'GO' + @crlf + @crlf +
    N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N' + @q + @CategoryName + @q + N' AND category_class = 1)' + @crlf +
    N'    EXEC msdb.dbo.sp_add_category'                                                                                             + @crlf +
    N'        @class = N' + @q + N'JOB' + @q + N', @type = N' + @q + N'LOCAL' + @q + N', @name = N' + @q + @CategoryName + @q + N';' + @crlf +
    N'GO' + @crlf + @crlf;

-- ── Job + step + schedule ─────────────────────────────────────────────────────
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
    N'    @step_name         = N' + @q + N'Run collector threshold checks' + @q + N',' + @crlf +
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
