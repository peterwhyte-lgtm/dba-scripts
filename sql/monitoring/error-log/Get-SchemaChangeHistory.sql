/*
Script Name : Get-SchemaChangeHistory
Category    : monitoring
Purpose     : Recent DDL changes (CREATE, ALTER, DROP) captured by the SQL Server default trace — answers "what changed on this server recently?" after an incident or unexpected behaviour.
              Requires the default trace to be enabled (on by default). Covers the rolling window kept by the trace files.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-schema-change-history/)
Requires    : VIEW SERVER STATE, ALTER TRACE (to read default trace path)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @tracepath NVARCHAR(260);
SELECT @tracepath = path FROM sys.traces WHERE is_default = 1;

IF @tracepath IS NULL
BEGIN
    RAISERROR('Default trace is not enabled. Enable it via sp_configure ''default trace enabled'', 1.', 16, 1);
    RETURN;
END;

/* ── DDL event classes: 46 = Created, 47 = Deleted, 164 = Altered ────────── */
SELECT
    t.StartTime AS change_time,
    te.name AS change_type,
    t.DatabaseName AS database_name,
    t.ObjectName AS object_name,
    t.LoginName AS changed_by,
    t.HostName AS host_name,
    t.ApplicationName AS application_name,
    LEFT(CAST(t.TextData AS NVARCHAR(MAX)), 500) AS sql_text
FROM sys.fn_trace_gettable(@tracepath, DEFAULT) t
JOIN sys.trace_events te ON te.trace_event_id = t.EventClass
WHERE t.EventClass IN (46, 47, 164) /* Object:Created, Object:Deleted, Object:Altered */
  AND t.EventSubClass = 1 /* Commit only — each DDL event is logged twice (Begin + Commit);
                             without this filter every change shows as a duplicate row */
  AND ISNULL(t.DatabaseName, '') NOT IN ('', 'mssqlsystemresource')
  AND t.ObjectName NOT LIKE N'[_]WA[_]Sys[_]%' /* auto-created statistics are not schema changes */
ORDER BY t.StartTime DESC;
