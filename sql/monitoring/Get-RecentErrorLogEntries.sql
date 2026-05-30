/*
Script Name : Get-RecentErrorLogEntries
Category    : maintenance-and-reliability
Purpose     : Show SQL Server error log entries from the last 24 hours, filtering routine noise.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE (xp_readerrorlog; sysadmin in practice for most instances)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

IF OBJECT_ID('tempdb..#error_log') IS NOT NULL DROP TABLE #error_log;

CREATE TABLE #error_log (
    log_date     DATETIME,
    process_info NVARCHAR(100),
    log_text     NVARCHAR(4000)
);

INSERT INTO #error_log (log_date, process_info, log_text)
EXEC xp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, 'asc';

SELECT TOP 500
    log_date,
    process_info,
    log_text
FROM #error_log
WHERE log_date >= DATEADD(HOUR, -24, GETDATE())
  AND log_text NOT LIKE '%This is an informational message%'
  AND log_text NOT LIKE '%found 0 errors%'
  AND log_text NOT LIKE '%without errors%'
  AND log_text NOT LIKE '%Log was backed up%'
  AND log_text NOT LIKE '%Database backed up%'
  AND log_text NOT LIKE '%I/O was resumed on database%'
  AND log_text NOT LIKE '%I/O is frozen on database%'
  AND log_text NOT LIKE '%CHECKDB%'
ORDER BY log_date DESC;

DROP TABLE #error_log;
