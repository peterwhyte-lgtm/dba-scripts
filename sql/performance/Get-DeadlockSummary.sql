/*
Script Name : Get-DeadlockSummary
Category    : performance-troubleshooting
Purpose     : Show recent deadlock events from the system_health XEvent ring buffer.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
Notes       : Ring buffer holds recent events only (typically last 30–60 min). For full
              history, query the system_health .xel files directly in SSMS.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH ring_buffer AS (
    SELECT
        CAST(target_data AS XML) AS ring_xml
    FROM sys.dm_xe_session_targets AS t
    INNER JOIN sys.dm_xe_sessions   AS s ON t.event_session_address = s.address
    WHERE s.name        = 'system_health'
      AND t.target_name = 'ring_buffer'
),
deadlock_nodes AS (
    SELECT
        e.x.value('@timestamp', 'datetime2')             AS event_timestamp,
        e.x.query('data[@name="xml_report"]/value')      AS deadlock_graph
    FROM ring_buffer
    CROSS APPLY ring_xml.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS e(x)
)
SELECT TOP 50
    event_timestamp,
    deadlock_graph
FROM deadlock_nodes
ORDER BY event_timestamp DESC;
