/*
Script Name : Get-ActiveXeSessions
Category    : traces
Purpose     : Shows all currently running Extended Events sessions with their targets and file output paths.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-active-xe-sessions/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    s.name AS session_name,
    s.create_time AS started_at,
    DATEDIFF(HOUR, s.create_time, GETDATE()) AS running_hours,
    t.target_name,
    CAST(
        CAST(t.target_data AS XML).value(
            '(EventFileTarget/File/@name)[1]', 'nvarchar(500)')
    AS NVARCHAR(500)) AS output_file,
    s.total_buffer_size / 1024 / 1024 AS buffer_size_mb,
    s.dropped_event_count,
    s.dropped_buffer_count,
    ses.startup_state AS auto_start_on_restart
FROM sys.dm_xe_sessions s
JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
JOIN sys.server_event_sessions ses ON ses.name = s.name
WHERE s.name NOT IN (
    'system_health', 'telemetry_xevents', 'hkenginexesession',
    'AlwaysOn_health', 'sp_server_diagnostics session'
)
ORDER BY s.create_time DESC;
