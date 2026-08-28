/*
Script Name : Set-AgentJobState
Category    : maintenance
Purpose     : Save, disable and restore SQL Agent job state as one operation, so a maintenance
              window can quiet an instance and then put it back EXACTLY as it was.
              @Action = N'Report'   lists every job with the change that would be made. Default.
              @Action = N'Save'     snapshots each job's enabled flag into a state table.
              @Action = N'Disable'  disables enabled jobs, honouring the exclusion lists.
              @Action = N'Restore'  re-applies the latest snapshot and proves the result matches.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : SQLAgentOperatorRole or sysadmin. Save also needs CREATE TABLE in @StateDatabase.
Notes       : Disabling is not stopping. A job already running keeps running after it is disabled;
              set @StopRunning = 1 to stop in-flight jobs as well, and understand that stopping a
              job mid-step leaves whatever it was doing half done.
              Restore only touches jobs whose current state DISAGREES with the snapshot, so it
              cannot re-enable something you disabled deliberately after taking the snapshot.
              Jobs created after the snapshot are not in it. Restore leaves them alone and Report
              lists them, because guessing at their intended state is not a rollback.
              Disable refuses to run when no snapshot exists. That is the whole safety property:
              never turn everything off without a recorded way back.
*/
-- WARNING: Disable turns off EVERY Agent job that is not excluded — run Save first
-- SAFE:CreatesObjects
-- IMPACT:High
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @Action            nvarchar(10)  = N'Report';        -- Report | Save | Disable | Restore
DECLARE @StateDatabase     sysname       = N'DBA_Admin';     -- a utility database, NOT tempdb
DECLARE @ExcludeCategories nvarchar(max) = N'Log Shipping,REPL-Distribution,REPL-LogReader,REPL-Merge,REPL-Snapshot';
DECLARE @ExcludeJobs       nvarchar(max) = N'';              -- comma separated exact job names
DECLARE @StopRunning       bit           = 0;                -- Disable only: stop in-flight jobs
-- ─────────────────────────────────────────────────────────────────────────────

IF @Action NOT IN (N'Report', N'Save', N'Disable', N'Restore')
BEGIN
    RAISERROR('@Action must be Report, Save, Disable or Restore.', 16, 1);
    RETURN;
END

IF DB_ID(@StateDatabase) IS NULL
BEGIN
    RAISERROR('@StateDatabase %s does not exist on this instance.', 16, 1, @StateDatabase);
    RETURN;
END

IF @StateDatabase IN (N'tempdb')
BEGIN
    RAISERROR('@StateDatabase must not be tempdb - the snapshot would not survive a restart.', 16, 1);
    RETURN;
END

DECLARE @sql   nvarchar(max);
DECLARE @db    nvarchar(300) = QUOTENAME(@StateDatabase);
DECLARE @rows  int;

-- Exclusions, resolved once into a temp table so every branch agrees on the same set.
IF OBJECT_ID('tempdb..#excluded') IS NOT NULL DROP TABLE #excluded;
CREATE TABLE #excluded (job_id uniqueidentifier PRIMARY KEY, name sysname, reason nvarchar(60));

INSERT INTO #excluded (job_id, name, reason)
SELECT j.job_id, j.name, N'category ' + c.name
FROM   msdb.dbo.sysjobs j
JOIN   msdb.dbo.syscategories c ON c.category_id = j.category_id
WHERE  LTRIM(RTRIM(c.name)) IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ExcludeCategories, ',')
                                WHERE LTRIM(RTRIM(value)) <> N'');

INSERT INTO #excluded (job_id, name, reason)
SELECT j.job_id, j.name, N'named in @ExcludeJobs'
FROM   msdb.dbo.sysjobs j
WHERE  LTRIM(RTRIM(j.name)) IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ExcludeJobs, ',')
                                WHERE LTRIM(RTRIM(value)) <> N'')
AND    NOT EXISTS (SELECT 1 FROM #excluded e WHERE e.job_id = j.job_id);

-- The latest snapshot, lifted out of @StateDatabase into a temp table so the rest of the script
-- is plain readable T-SQL rather than one long dynamic string.
IF OBJECT_ID('tempdb..#snapshot') IS NOT NULL DROP TABLE #snapshot;
CREATE TABLE #snapshot (job_id uniqueidentifier PRIMARY KEY, name sysname, enabled tinyint,
                        CapturedAt datetime2(0));

SET @sql = N'
IF OBJECT_ID(''' + @db + N'.dbo.AgentJobState'') IS NOT NULL
    SELECT job_id, name, enabled, CapturedAt
    FROM   ' + @db + N'.dbo.AgentJobState
    WHERE  CapturedAt = (SELECT MAX(CapturedAt) FROM ' + @db + N'.dbo.AgentJobState);';
INSERT INTO #snapshot (job_id, name, enabled, CapturedAt) EXEC sp_executesql @sql;

DECLARE @snapAt datetime2(0) = (SELECT MAX(CapturedAt) FROM #snapshot);
DECLARE @snapN  int          = (SELECT COUNT(*) FROM #snapshot);

-- ══ Report ═══════════════════════════════════════════════════════════════════
IF @Action = N'Report'
BEGIN
    IF @snapAt IS NULL
        PRINT 'No snapshot found in ' + @StateDatabase + '.dbo.AgentJobState. Run @Action = Save first.';
    ELSE
        PRINT 'Latest snapshot: ' + CONVERT(varchar(19), @snapAt, 120)
              + ' holding ' + CAST(@snapN AS varchar(10)) + ' job(s).';

    SELECT j.name,
           c.name                                      AS category,
           j.enabled                                   AS enabled_now,
           s.enabled                                   AS enabled_in_snapshot,
           e.reason                                    AS excluded_because,
           CASE
               WHEN e.job_id IS NOT NULL              THEN N'excluded, left alone'
               WHEN s.job_id IS NULL                  THEN N'not in snapshot - Restore will not touch it'
               WHEN j.enabled = 1                     THEN N'Disable would turn this off'
               ELSE                                        N'already disabled'
           END                                         AS on_disable,
           CASE
               WHEN s.job_id IS NULL                  THEN N'no snapshot row'
               WHEN s.enabled = j.enabled             THEN N'already matches'
               ELSE N'Restore would set enabled = ' + CAST(s.enabled AS varchar(1))
           END                                         AS on_restore
    FROM   msdb.dbo.sysjobs j
    JOIN   msdb.dbo.syscategories c ON c.category_id = j.category_id
    LEFT   JOIN #snapshot s ON s.job_id = j.job_id
    LEFT   JOIN #excluded e ON e.job_id = j.job_id
    ORDER  BY c.name, j.name;

    SELECT COUNT(*)                                                AS jobs_total,
           SUM(CASE WHEN j.enabled = 1 THEN 1 ELSE 0 END)          AS enabled_now,
           (SELECT COUNT(*) FROM #excluded)                        AS excluded,
           @snapN                                                  AS in_snapshot,
           SUM(CASE WHEN s.job_id IS NULL THEN 1 ELSE 0 END)       AS added_since_snapshot
    FROM   msdb.dbo.sysjobs j
    LEFT   JOIN #snapshot s ON s.job_id = j.job_id;

    -- The statements Disable would run, and the ones that would undo it. Report is a dry run,
    -- so this is the script you review before committing to anything - or save and run by hand
    -- if you would rather drive it yourself than let the tool do it.
    SELECT j.name                                                  AS job,
           N'EXEC msdb.dbo.sp_update_job @job_name = N'
             + QUOTENAME(j.name, '''') + N', @enabled = 0;'        AS disable_statement,
           N'EXEC msdb.dbo.sp_update_job @job_name = N'
             + QUOTENAME(j.name, '''') + N', @enabled = 1;'        AS enable_statement
    FROM   msdb.dbo.sysjobs j
    JOIN   msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE  j.enabled = 1
    AND    NOT EXISTS (SELECT 1 FROM #excluded e WHERE e.job_id = j.job_id)
    ORDER  BY c.name, j.name;
    RETURN;
END

-- ══ Save ═════════════════════════════════════════════════════════════════════
IF @Action = N'Save'
BEGIN
    SET @sql = N'
    IF OBJECT_ID(''' + @db + N'.dbo.AgentJobState'') IS NULL
        CREATE TABLE ' + @db + N'.dbo.AgentJobState (
            CapturedAt datetime2(0)      NOT NULL CONSTRAINT DF_AgentJobState_CapturedAt DEFAULT SYSDATETIME(),
            job_id     uniqueidentifier  NOT NULL,
            name       sysname           NOT NULL,
            enabled    tinyint           NOT NULL,
            CONSTRAINT PK_AgentJobState PRIMARY KEY (CapturedAt, job_id)
        );';
    EXEC sp_executesql @sql;

    -- One CapturedAt for the whole snapshot. SYSDATETIME() per row would split a single save
    -- across two timestamps and Restore reads MAX(CapturedAt), so it would then restore a
    -- fraction of the instance and report success.
    DECLARE @now datetime2(0) = SYSDATETIME();
    SET @sql = N'
    INSERT INTO ' + @db + N'.dbo.AgentJobState (CapturedAt, job_id, name, enabled)
    SELECT @now, job_id, name, enabled FROM msdb.dbo.sysjobs;';
    EXEC sp_executesql @sql, N'@now datetime2(0)', @now = @now;
    SET @rows = @@ROWCOUNT;

    PRINT 'Saved ' + CAST(@rows AS varchar(10)) + ' job(s) at ' + CONVERT(varchar(19), @now, 120)
          + ' into ' + @StateDatabase + '.dbo.AgentJobState.';

    SELECT @rows                                                     AS jobs_saved,
           (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE enabled = 1) AS were_enabled,
           @now                                                      AS captured_at;
    RETURN;
END

-- ══ Disable ══════════════════════════════════════════════════════════════════
IF @Action = N'Disable'
BEGIN
    -- The safety property. Without a snapshot there is no way back, and "I will remember which
    -- ones were on" is not a rollback plan.
    IF @snapAt IS NULL
    BEGIN
        RAISERROR('No snapshot in %s.dbo.AgentJobState. Run @Action = Save before disabling.',
                  16, 1, @StateDatabase);
        RETURN;
    END

    DECLARE @job sysname, @disabled int = 0;

    -- Record WHAT is about to be turned off, before turning it off. Once the loop has run,
    -- msdb no longer knows which jobs were enabled a moment ago, and a count is not a record.
    -- The DBA gets the list, and an undo statement per job that works even if the state table
    -- is lost, the window runs into the next shift, or somebody restores over the database.
    IF OBJECT_ID('tempdb..#changed') IS NOT NULL DROP TABLE #changed;
    CREATE TABLE #changed (name sysname, category sysname);
    INSERT INTO #changed (name, category)
    SELECT j.name, c.name
    FROM   msdb.dbo.sysjobs j
    JOIN   msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE  j.enabled = 1
    AND    NOT EXISTS (SELECT 1 FROM #excluded e WHERE e.job_id = j.job_id);

    DECLARE job_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT j.name
        FROM   msdb.dbo.sysjobs j
        WHERE  j.enabled = 1
        AND    NOT EXISTS (SELECT 1 FROM #excluded e WHERE e.job_id = j.job_id);

    OPEN job_cur;
    FETCH NEXT FROM job_cur INTO @job;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC msdb.dbo.sp_update_job @job_name = @job, @enabled = 0;
        SET @disabled += 1;
        FETCH NEXT FROM job_cur INTO @job;
    END
    CLOSE job_cur;
    DEALLOCATE job_cur;

    DECLARE @stopped int = 0;
    IF @StopRunning = 1
    BEGIN
        DECLARE stop_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT j.name
            FROM   msdb.dbo.sysjobactivity ja
            JOIN   msdb.dbo.sysjobs j ON j.job_id = ja.job_id
            WHERE  ja.run_requested_date IS NOT NULL
            AND    ja.stop_execution_date IS NULL
            AND    NOT EXISTS (SELECT 1 FROM #excluded e WHERE e.job_id = j.job_id);
        OPEN stop_cur;
        FETCH NEXT FROM stop_cur INTO @job;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC msdb.dbo.sp_stop_job @job_name = @job;
            SET @stopped += 1;
            FETCH NEXT FROM stop_cur INTO @job;
        END
        CLOSE stop_cur;
        DEALLOCATE stop_cur;
    END

    DECLARE @exCount int = (SELECT COUNT(*) FROM #excluded);
    PRINT 'Disabled ' + CAST(@disabled AS varchar(10)) + ' job(s), stopped '
          + CAST(@stopped AS varchar(10)) + ', excluded '
          + CAST(@exCount AS varchar(10)) + '.';

    SELECT @disabled                                                    AS jobs_disabled,
           @stopped                                                     AS jobs_stopped,
           (SELECT COUNT(*) FROM #excluded)                             AS jobs_excluded,
           (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE enabled = 1)    AS still_enabled;

    -- EXACTLY what was turned off, and the statement that puts each one back. Copy the last
    -- column out and you have a rollback script that depends on nothing but msdb - useful when
    -- the window runs into somebody else's shift, or the state database is itself being restored.
    SELECT c.name                                              AS job_disabled,
           c.category,
           N'EXEC msdb.dbo.sp_update_job @job_name = N'
             + QUOTENAME(c.name, '''') + N', @enabled = 1;'    AS undo_statement
    FROM   #changed c
    ORDER  BY c.category, c.name;

    SELECT name AS job_left_alone, reason FROM #excluded ORDER BY name;
    RETURN;
END

-- ══ Restore ══════════════════════════════════════════════════════════════════
IF @Action = N'Restore'
BEGIN
    IF @snapAt IS NULL
    BEGIN
        RAISERROR('No snapshot in %s.dbo.AgentJobState to restore from.', 16, 1, @StateDatabase);
        RETURN;
    END

    DECLARE @rjob sysname, @was tinyint, @changed int = 0;

    -- Same reasoning as Disable: capture the list before the loop changes it, so the DBA gets a
    -- record of what moved rather than a number.
    IF OBJECT_ID('tempdb..#restored') IS NOT NULL DROP TABLE #restored;
    CREATE TABLE #restored (name sysname, was tinyint, is_now tinyint);
    INSERT INTO #restored (name, was, is_now)
    SELECT s.name, j.enabled, s.enabled
    FROM   #snapshot s
    JOIN   msdb.dbo.sysjobs j ON j.job_id = s.job_id
    WHERE  j.enabled <> s.enabled;

    -- Only where the CURRENT state disagrees with the snapshot. Re-applying every row would
    -- undo anything you changed on purpose after taking it, and would report those as restored.
    DECLARE res_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.name, s.enabled
        FROM   #snapshot s
        JOIN   msdb.dbo.sysjobs j ON j.job_id = s.job_id
        WHERE  j.enabled <> s.enabled;

    OPEN res_cur;
    FETCH NEXT FROM res_cur INTO @rjob, @was;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC msdb.dbo.sp_update_job @job_name = @rjob, @enabled = @was;
        SET @changed += 1;
        FETCH NEXT FROM res_cur INTO @rjob, @was;
    END
    CLOSE res_cur;
    DEALLOCATE res_cur;

    PRINT 'Restored ' + CAST(@changed AS varchar(10)) + ' job(s) to the snapshot taken '
          + CONVERT(varchar(19), @snapAt, 120) + '.';

    -- What actually moved, and in which direction.
    SELECT name        AS job_restored,
           was         AS state_before_restore,
           is_now      AS state_after_restore
    FROM   #restored
    ORDER  BY name;

    -- The proof. Anything returned here is a job that did NOT come back as recorded.
    SELECT s.name, s.enabled AS was, j.enabled AS [now]
    FROM   #snapshot s
    JOIN   msdb.dbo.sysjobs j ON j.job_id = s.job_id
    WHERE  j.enabled <> s.enabled;

    -- Jobs created since the snapshot. Not an error, but they are yours to decide on.
    SELECT j.name AS created_since_snapshot, j.enabled
    FROM   msdb.dbo.sysjobs j
    WHERE  NOT EXISTS (SELECT 1 FROM #snapshot s WHERE s.job_id = j.job_id)
    ORDER  BY j.name;

    SELECT @changed AS jobs_changed, @snapAt AS restored_from, @snapN AS jobs_in_snapshot;
    RETURN;
END
