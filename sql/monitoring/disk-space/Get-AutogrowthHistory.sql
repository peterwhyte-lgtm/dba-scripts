/*
Script Name : Get-AutogrowthHistory
Category    : monitoring
Purpose     : Reads autogrowth events from the SQL Server default trace.
              Autogrowth events during business hours indicate undersized files;
              frequent events indicate the growth increment is too small.
              Use this to right-size initial file sizes and growth increments.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-autogrowth-history/)
Requires    : VIEW SERVER STATE, ALTER TRACE (to read trace files)
HealthCheck : Yes
Notes       : Default trace rolls over; history depth depends on server activity.
              Typically covers the last few days to weeks.
              EventClass 92 = Data File Autogrow, 93 = Log File Autogrow.
              Fix: pre-size files to expected peak size and set a fixed MB growth
              increment (not percent) via ALTER DATABASE ... MODIFY FILE.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @tracepath NVARCHAR(256);

SELECT @tracepath = path
FROM   sys.traces
WHERE  is_default = 1;

IF @tracepath IS NULL
BEGIN
    SELECT 'Default trace is not running or has been disabled.' AS note;
    RETURN;
END

SELECT
    DB_NAME(e.DatabaseID)                           AS database_name,
    e.FileName                                      AS data_file,
    CASE e.EventClass
        WHEN 92 THEN 'Data File Autogrow'
        WHEN 93 THEN 'Log File Autogrow'
    END                                             AS event_type,
    e.StartTime                                     AS grew_at,
    CAST(e.IntegerData * 8.0 / 1024 AS DECIMAL(10,2)) AS growth_mb,
    CAST(e.Duration / 1000.0 AS DECIMAL(10,1))     AS duration_ms,
    DATENAME(WEEKDAY, e.StartTime)                  AS day_of_week,
    DATEPART(HOUR,    e.StartTime)                  AS hour_of_day
FROM   sys.fn_trace_gettable(@tracepath, DEFAULT) AS e
WHERE  e.EventClass IN (92, 93)
  AND  e.DatabaseID  > 4
ORDER BY e.StartTime DESC;
