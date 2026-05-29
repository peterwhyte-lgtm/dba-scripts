/*
Script Name : Get-DatabaseGrowthEvents
Category    : maintenance-and-reliability
Purpose     : Show recent database and log file autogrowth events from the default trace.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : ALTER TRACE (to read default trace file)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

DECLARE @DefaultTracePath NVARCHAR(4000);

-- Get the active default trace file path.
SELECT @DefaultTracePath = path
FROM sys.traces
WHERE is_default = 1;

SELECT
    t.StartTime,
    t.DatabaseName,
    t.FileName,
    t.Duration,
    t.IntegerData,
    t.SpID,
    t.EventClass
FROM fn_trace_gettable(@DefaultTracePath, DEFAULT) AS t
WHERE t.EventClass IN (92, 93)
ORDER BY t.StartTime DESC;




