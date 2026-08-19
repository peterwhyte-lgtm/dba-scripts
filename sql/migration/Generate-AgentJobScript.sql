/*
Script Name : Generate-AgentJobScript
Category    : migration
Purpose     : Generate sp_add_job DDL to recreate all SQL Agent jobs on the target server.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-agent-job-script/)
Requires    : SQLAgentUserRole in msdb (or sysadmin)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @ddl  NVARCHAR(MAX) = N'';
DECLARE @crlf NCHAR(2)      = CHAR(13) + CHAR(10);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- SQL Agent Job Migration Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Review owner_login_name values - map to valid logins on target.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf
    + N'USE msdb;' + @crlf + N'GO' + @crlf + @crlf;

-- ── Per job ───────────────────────────────────────────────────────────────────

DECLARE @job_id    UNIQUEIDENTIFIER;
DECLARE @job_name  NVARCHAR(128);
DECLARE @enabled   TINYINT;
DECLARE @desc      NVARCHAR(512);
DECLARE @category  NVARCHAR(128);
DECLARE @owner     NVARCHAR(128);
DECLARE @start_step INT;
DECLARE @nl_email  INT; DECLARE @nl_netsend INT; DECLARE @nl_page INT; DECLARE @nl_eventlog INT;
DECLARE @op_email  NVARCHAR(128); DECLARE @op_netsend NVARCHAR(128); DECLARE @op_page NVARCHAR(128);

DECLARE job_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        j.job_id,
        j.name,
        j.enabled,
        ISNULL(j.description, N''),
        ISNULL(c.name, N'[Uncategorized (Local)]'),
        ISNULL(SUSER_SNAME(j.owner_sid), N'sa'),
        j.start_step_id,
        j.notify_level_email,
        j.notify_level_netsend,
        j.notify_level_page,
        j.notify_level_eventlog,
        ISNULL(CAST(n_email.name  AS NVARCHAR(128)), N''),
        ISNULL(CAST(n_ns.name     AS NVARCHAR(128)), N''),
        ISNULL(CAST(n_page.name   AS NVARCHAR(128)), N'')
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.syscategories c ON j.category_id = c.category_id
    LEFT JOIN msdb.dbo.sysoperators n_email ON j.notify_email_operator_id   = n_email.id
    LEFT JOIN msdb.dbo.sysoperators n_ns    ON j.notify_netsend_operator_id = n_ns.id
    LEFT JOIN msdb.dbo.sysoperators n_page  ON j.notify_page_operator_id    = n_page.id
    ORDER BY j.name;

OPEN job_cur;
FETCH NEXT FROM job_cur INTO
    @job_id, @job_name, @enabled, @desc, @category, @owner, @start_step,
    @nl_email, @nl_netsend, @nl_page, @nl_eventlog,
    @op_email, @op_netsend, @op_page;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- ── Job header ────────────────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'-- Job: ' + @job_name + @crlf
        + N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N''' + REPLACE(@job_name, N'''', N'''''') + N''')' + @crlf
        + N'BEGIN' + @crlf
        + N'    DECLARE @job_id UNIQUEIDENTIFIER;' + @crlf
        + N'    EXEC msdb.dbo.sp_add_job' + @crlf
        + N'        @job_name              = N''' + REPLACE(@job_name, N'''', N'''''') + N''',' + @crlf
        + N'        @enabled               = '    + CAST(@enabled AS NVARCHAR(1)) + N',' + @crlf
        + N'        @description           = N''' + REPLACE(@desc,     N'''', N'''''') + N''',' + @crlf
        + N'        @category_name         = N''' + REPLACE(@category, N'''', N'''''') + N''',' + @crlf
        + N'        @owner_login_name      = N''' + REPLACE(@owner,    N'''', N'''''') + N''',' + @crlf
        + N'        @notify_level_eventlog = '    + CAST(@nl_eventlog  AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_email    = '    + CAST(@nl_email     AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_netsend  = '    + CAST(@nl_netsend   AS NVARCHAR(1)) + N',' + @crlf
        + N'        @notify_level_page     = '    + CAST(@nl_page      AS NVARCHAR(1)) + @crlf
        + CASE WHEN @op_email   <> N'' THEN N'       ,@notify_email_operator_name   = N''' + REPLACE(@op_email,   N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + CASE WHEN @op_netsend <> N'' THEN N'       ,@notify_netsend_operator_name = N''' + REPLACE(@op_netsend, N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + CASE WHEN @op_page    <> N'' THEN N'       ,@notify_page_operator_name    = N''' + REPLACE(@op_page,    N'''',N'''''') + N'''' + @crlf ELSE N'' END
        + N'        ,@job_id = @job_id OUTPUT;' + @crlf + @crlf;

    -- ── Job steps ─────────────────────────────────────────────────────────────
    SELECT @ddl = @ddl
        + N'    EXEC msdb.dbo.sp_add_jobstep' + @crlf
        + N'        @job_name        = N''' + REPLACE(@job_name,      N'''', N'''''') + N''',' + @crlf
        + N'        @step_id         = '    + CAST(s.step_id          AS NVARCHAR(5))   + N',' + @crlf
        + N'        @step_name       = N''' + REPLACE(s.step_name,    N'''', N'''''') + N''',' + @crlf
        + N'        @subsystem       = N''' + s.subsystem                               + N''',' + @crlf
        + N'        @command         = N''' + REPLACE(ISNULL(s.command, N''), N'''', N'''''') + N''',' + @crlf
        + N'        @database_name   = N''' + ISNULL(s.database_name, N'master')        + N''',' + @crlf
        + N'        @on_success_action = '  + CAST(s.on_success_action AS NVARCHAR(1))  + N',' + @crlf
        + N'        @on_success_step_id= '  + CAST(s.on_success_step_id AS NVARCHAR(5)) + N',' + @crlf
        + N'        @on_fail_action  = '    + CAST(s.on_fail_action    AS NVARCHAR(1))  + N',' + @crlf
        + N'        @on_fail_step_id = '    + CAST(s.on_fail_step_id   AS NVARCHAR(5))  + N',' + @crlf
        + N'        @retry_attempts  = '    + CAST(s.retry_attempts    AS NVARCHAR(5))  + N',' + @crlf
        + N'        @retry_interval  = '    + CAST(s.retry_interval    AS NVARCHAR(5))  + N';' + @crlf + @crlf
    FROM msdb.dbo.sysjobsteps s
    WHERE s.job_id = @job_id
    ORDER BY s.step_id;

    -- ── Set start step ────────────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'    EXEC msdb.dbo.sp_update_job @job_name = N''' + REPLACE(@job_name, N'''', N'''''') + N''', @start_step_id = ' + CAST(@start_step AS NVARCHAR(5)) + N';' + @crlf + @crlf;

    -- ── Schedules ─────────────────────────────────────────────────────────────
    SELECT @ddl = @ddl
        + N'    IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N''' + REPLACE(sc.name, N'''', N'''''') + N''')' + @crlf
        + N'    BEGIN' + @crlf
        + N'        EXEC msdb.dbo.sp_add_schedule' + @crlf
        + N'            @schedule_name       = N''' + REPLACE(sc.name, N'''', N'''''')     + N''',' + @crlf
        + N'            @enabled             = '    + CAST(sc.enabled            AS NVARCHAR(1))  + N',' + @crlf
        + N'            @freq_type           = '    + CAST(sc.freq_type          AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_interval       = '    + CAST(sc.freq_interval      AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_subday_type    = '    + CAST(sc.freq_subday_type   AS NVARCHAR(10)) + N',' + @crlf
        + N'            @freq_subday_interval= '    + CAST(sc.freq_subday_interval AS NVARCHAR(10))+ N',' + @crlf
        + N'            @freq_relative_interval='   + CAST(sc.freq_relative_interval AS NVARCHAR(10))+N',' + @crlf
        + N'            @freq_recurrence_factor='   + CAST(sc.freq_recurrence_factor AS NVARCHAR(10))+N',' + @crlf
        + N'            @active_start_date   = '    + CAST(sc.active_start_date  AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_end_date     = '    + CAST(sc.active_end_date    AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_start_time   = '    + CAST(sc.active_start_time  AS NVARCHAR(10)) + N',' + @crlf
        + N'            @active_end_time     = '    + CAST(sc.active_end_time    AS NVARCHAR(10)) + N';' + @crlf
        + N'    END' + @crlf
        + N'    EXEC msdb.dbo.sp_attach_schedule @job_name = N''' + REPLACE(@job_name, N'''', N'''''') + N''', @schedule_name = N''' + REPLACE(sc.name, N'''', N'''''') + N''';' + @crlf + @crlf
    FROM msdb.dbo.sysjobschedules js
    INNER JOIN msdb.dbo.sysschedules sc ON js.schedule_id = sc.schedule_id
    WHERE js.job_id = @job_id;

    -- ── Add to local server ───────────────────────────────────────────────────
    SET @ddl = @ddl
        + N'    EXEC msdb.dbo.sp_add_jobserver @job_name = N''' + REPLACE(@job_name, N'''', N'''''') + N''', @server_name = N''(local)'';' + @crlf
        + N'END' + @crlf + N'GO' + @crlf + @crlf;

    FETCH NEXT FROM job_cur INTO
        @job_id, @job_name, @enabled, @desc, @category, @owner, @start_step,
        @nl_email, @nl_netsend, @nl_page, @nl_eventlog,
        @op_email, @op_netsend, @op_page;
END

CLOSE job_cur;
DEALLOCATE job_cur;

SELECT @ddl AS ddl;
