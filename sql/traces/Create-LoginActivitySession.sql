/*
Script Name : Create-LoginActivitySession
Category    : traces
Purpose     : Creates a lightweight Extended Events session that captures every successful and failed login to the server — who, from where, and using which application.
              Use to answer "who connects to this server" before decommissioning, during security reviews, or to baseline connection patterns.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-create-login-activity-session/)
Requires    : ALTER ANY EVENT SESSION, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-create-login-activity-session/
-- SAFE:CreatesObjects
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration — edit these before running ───────────────────────────── */
DECLARE @SessionName   NVARCHAR(128) = N'LoginActivity';
DECLARE @TraceFolder   NVARCHAR(260) = N'D:\SQLTrace';
    /* Folder must exist; SQL Server service account needs write access.      */
DECLARE @MaxFileMB     INT           = 100;   /* max size per .xel file in MB                         */
DECLARE @MaxFiles      INT           = 6;     /* number of rollover files; oldest is overwritten first */
DECLARE @RetentionDays INT           = 3;
    /* SQL Server 2025+ (v17+) only: session auto-stops after this many days.
       On older versions this has no effect — the session runs until you stop
       it manually (ALTER EVENT SESSION ... ON SERVER STATE = STOP).          */
/* ─────────────────────────────────────────────────────────────────────────── */

DECLARE @ProductMajorVersion INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);

/* Escape any single-quotes in the path so the dynamic SQL string stays valid */
DECLARE @FilePathRaw NVARCHAR(260) = @TraceFolder + N'\' + @SessionName + N'.xel';
DECLARE @FilePathEsc NVARCHAR(522) = REPLACE(@FilePathRaw, N'''', N'''''');

DECLARE @sql NVARCHAR(MAX);

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
BEGIN
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = STOP;
    DROP EVENT SESSION '  + QUOTENAME(@SessionName) + N' ON SERVER;';
    EXEC sp_executesql @sql;
    PRINT 'Existing session ' + @SessionName + ' stopped and dropped.';
END;

/* Build WITH clause — MAX_DURATION is SQL Server 2025+ (v17+) only */
DECLARE @WithClause NVARCHAR(500) =
    N'WITH (
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    STARTUP_STATE        = ON';
IF @ProductMajorVersion >= 17
    SET @WithClause = @WithClause
        + N',
    MAX_DURATION         = ' + CAST(@RetentionDays AS NVARCHAR(5)) + N' DAYS';
SET @WithClause = @WithClause + N'
)';

SET @sql = N'
CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER
ADD EVENT sqlserver.login (
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username,
        sqlserver.server_principal_name,
        sqlserver.database_name
    )
    WHERE sqlserver.is_system = 0
),
ADD EVENT sqlserver.error_reported (
    /* error 18456 = Login failed; state field indicates the specific reason */
    ACTION (
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.username,
        sqlserver.nt_username,
        sqlserver.server_principal_name,
        sqlserver.database_name
    )
    WHERE error_number = 18456
)
ADD TARGET package0.event_file (
    SET filename           = N''' + @FilePathEsc + N''',
        max_file_size      = ' + CAST(@MaxFileMB AS NVARCHAR(10)) + N',
        max_rollover_files = ' + CAST(@MaxFiles  AS NVARCHAR(10)) + N'
)
' + @WithClause + N';
ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + N' ON SERVER STATE = START;';

BEGIN TRY
    EXEC sp_executesql @sql;

    SELECT
        @SessionName                                               AS session_name,
        @FilePathRaw                                               AS output_file,
        @MaxFileMB                                                 AS max_file_mb,
        @MaxFiles                                                  AS max_files,
        @MaxFileMB * @MaxFiles                                     AS total_capacity_mb,
        CASE WHEN @ProductMajorVersion >= 17
             THEN CAST(@RetentionDays AS VARCHAR(5)) + ' days (MAX_DURATION)'
             ELSE 'manual stop (pre-2025)'
        END                                                        AS session_lifetime,
        'RUNNING'                                                  AS status,
        'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER STATE = STOP; DROP EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER;'
                                                                   AS remove_cmd;

    PRINT 'Session ' + @SessionName + ' created and started.';
    PRINT 'Output file : ' + @FilePathRaw;
    PRINT 'View data   : SSMS > Management > Extended Events > Sessions > ' + @SessionName + ' > right-click target > View Target Data';
END TRY
BEGIN CATCH
    PRINT 'ERROR creating session: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
