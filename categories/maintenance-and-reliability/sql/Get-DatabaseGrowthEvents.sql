/*
Script Name : Show recent SQL Server database and log file autogrowth events from the default trace.
Description : Returns Database Growth Events for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

DECLARE @DefaultTracePath NVARCHAR(4000);

SELECT @DefaultTracePath = CAST(value AS NVARCHAR(4000))
FROM sys.configurations
WHERE name = 'default trace enabled';

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



