/*
Script Name : Get-DatabaseGrowthEvents
Category    : maintenance-and-reliability
Purpose     : Show recent autogrowth events from the default trace for capacity planning.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : ALTER TRACE or sysadmin (to read default trace path and files)
Notes       : The default trace covers the last 20 MB of trace data (rolling). It was
              deprecated in SQL Server 2022 — on 2022+ instances use the system_health
              XEvent session or query sys.fn_xe_file_target_read_file instead.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

DECLARE @trace_path NVARCHAR(4000);

SELECT @trace_path = path
FROM sys.traces
WHERE is_default = 1;

IF @trace_path IS NULL
BEGIN
    SELECT 'Default trace is disabled or not available on this instance.' AS status;
END
ELSE
BEGIN
    SELECT
        t.StartTime                            AS event_time,
        t.DatabaseName                         AS database_name,
        t.FileName                             AS file_name,
        CAST(t.IntegerData * 8.0 / 1024 AS DECIMAL(10,2)) AS growth_mb,
        t.Duration / 1000                      AS duration_ms,
        t.SPID                                 AS spid,
        CASE t.EventClass
            WHEN 92 THEN 'Data File Auto Grow'
            WHEN 93 THEN 'Log File Auto Grow'
        END                                    AS event_type
    FROM fn_trace_gettable(@trace_path, DEFAULT) AS t
    WHERE t.EventClass IN (92, 93)
    ORDER BY t.StartTime DESC;
END
