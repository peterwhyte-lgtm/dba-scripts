/*
Script Name : Remove-XeSession
Category    : traces
Purpose     : Lists all DBA-created Extended Events sessions (running and stopped) and generates the DDL to stop and drop each one.
              Copy the remove_cmd value for any session you want to clean up and run it.
              .xel files on disk are NOT deleted — review them first with Get-XeSessionActivity.sql, then delete manually.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-remove-xe-session/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    ses.name AS session_name,
    CASE WHEN dm.name IS NOT NULL THEN 'RUNNING' ELSE 'STOPPED' END AS session_status,
    dm.create_time AS started_at,
    DATEDIFF(HOUR, dm.create_time, GETDATE()) AS running_hours,
    ses.startup_state AS auto_start_on_restart,
    COALESCE(
        CAST(CAST(tgt.target_data AS XML).value(
            '(EventFileTarget/File/@name)[1]', 'nvarchar(500)') AS NVARCHAR(500)),
        CONVERT(NVARCHAR(500), f.value)
    ) AS output_file,
    'ALTER EVENT SESSION ' + QUOTENAME(ses.name) + ' ON SERVER STATE = STOP; DROP EVENT SESSION ' + QUOTENAME(ses.name) + ' ON SERVER;' AS remove_cmd
FROM sys.server_event_sessions ses
LEFT JOIN sys.dm_xe_sessions dm ON dm.name = ses.name
LEFT JOIN sys.dm_xe_session_targets tgt ON tgt.event_session_address = dm.address
                                                        AND tgt.target_name = 'event_file'
LEFT JOIN sys.server_event_session_targets st ON st.event_session_id = ses.event_session_id
                                                        AND st.name = 'event_file'
LEFT JOIN sys.server_event_session_fields f ON f.event_session_id = ses.event_session_id
                                                        AND f.object_id = st.target_id
                                                        AND f.name = 'filename'
WHERE ses.name NOT IN (
    'system_health', 'telemetry_xevents', 'hkenginexesession',
    'AlwaysOn_health', 'sp_server_diagnostics session'
)
ORDER BY CASE WHEN dm.name IS NOT NULL THEN 0 ELSE 1 END, ses.name;
