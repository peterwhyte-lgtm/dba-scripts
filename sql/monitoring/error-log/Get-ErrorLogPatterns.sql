/*
Script Name : Get-ErrorLogPatterns
Category    : monitoring
Purpose     : Reads the current SQL Server error log and groups entries by category — surfaces memory pressure, login failures, IO issues, corruption warnings, and auto-growth events without scrolling through raw entries.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-error-log-patterns/)
Requires    : VIEW SERVER STATE (for xp_readerrorlog via sysadmin or securityadmin)
*/
-- Blog: https://sqldba.blog/dba-scripts-get-error-log-patterns/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* ── How many hours back to read (default 24) ───────────────────────────── */
DECLARE @HoursBack INT = 24;
/* ─────────────────────────────────────────────────────────────────────────── */

IF OBJECT_ID('tempdb..#ErrLog') IS NOT NULL DROP TABLE #ErrLog;
CREATE TABLE #ErrLog (
    LogDate DATETIME NOT NULL,
    ProcessInfo NVARCHAR(50),
    Txt NVARCHAR(4000)
);

DECLARE @StartDate DATETIME = DATEADD(HOUR, -@HoursBack, GETDATE());
INSERT INTO #ErrLog
EXEC xp_readerrorlog 0, 1, NULL, NULL, @StartDate, NULL, N'desc';

SELECT
    CASE
        WHEN Txt LIKE '%paged out%'
          OR Txt LIKE '%virtual address space%'
          OR Txt LIKE '%out of memory%'
          OR Txt LIKE '%cannot allocate%' THEN 'Memory Pressure'
        WHEN Txt LIKE '%login failed%'
          OR Txt LIKE '%18456%'
          OR Txt LIKE '%password%incorrect%' THEN 'Login Failure'
        WHEN Txt LIKE '%Backup%'
          OR Txt LIKE '%BACKUP%'
          OR Txt LIKE '%backup of database%'
          OR Txt LIKE '%RESTORE%' THEN 'Backup / Restore'
        WHEN Txt LIKE '%I/O%'
          OR Txt LIKE '%stall%'
          OR Txt LIKE '%stalled%'
          OR Txt LIKE '%disk%' THEN 'IO Issue'
        WHEN Txt LIKE '%corrupt%'
          OR Txt LIKE '% 824 %'
          OR Txt LIKE '% 823 %'
          OR Txt LIKE '% 825 %'
          OR Txt LIKE '%checkdb%' THEN 'Corruption / Integrity'
        WHEN Txt LIKE '%suspect%'
          OR Txt LIKE '%offline%'
          OR Txt LIKE '%emergency%'
          OR Txt LIKE '%recovery%' THEN 'Database State'
        WHEN Txt LIKE '%autogrow%'
          OR Txt LIKE '%Auto-grow%'
          OR Txt LIKE '% grew %'
          OR Txt LIKE '%Autogrow%' THEN 'Auto-Growth'
        WHEN Txt LIKE '%deadlock%' THEN 'Deadlock'
        WHEN Txt LIKE '%Error%'
          OR Txt LIKE '%error%'
          OR Txt LIKE '%failed%' THEN 'Error / Failure'
        WHEN Txt LIKE '%Warning%'
          OR Txt LIKE '%warning%' THEN 'Warning'
        ELSE 'Informational'
    END AS category,
    COUNT(*) AS occurrences,
    MIN(LogDate) AS first_seen,
    MAX(LogDate) AS last_seen,
    LEFT(MAX(Txt), 200) AS sample_message
FROM #ErrLog
GROUP BY
    CASE
        WHEN Txt LIKE '%paged out%'
          OR Txt LIKE '%virtual address space%'
          OR Txt LIKE '%out of memory%'
          OR Txt LIKE '%cannot allocate%' THEN 'Memory Pressure'
        WHEN Txt LIKE '%login failed%'
          OR Txt LIKE '%18456%'
          OR Txt LIKE '%password%incorrect%' THEN 'Login Failure'
        WHEN Txt LIKE '%Backup%'
          OR Txt LIKE '%BACKUP%'
          OR Txt LIKE '%backup of database%'
          OR Txt LIKE '%RESTORE%' THEN 'Backup / Restore'
        WHEN Txt LIKE '%I/O%'
          OR Txt LIKE '%stall%'
          OR Txt LIKE '%stalled%'
          OR Txt LIKE '%disk%' THEN 'IO Issue'
        WHEN Txt LIKE '%corrupt%'
          OR Txt LIKE '% 824 %'
          OR Txt LIKE '% 823 %'
          OR Txt LIKE '% 825 %'
          OR Txt LIKE '%checkdb%' THEN 'Corruption / Integrity'
        WHEN Txt LIKE '%suspect%'
          OR Txt LIKE '%offline%'
          OR Txt LIKE '%emergency%'
          OR Txt LIKE '%recovery%' THEN 'Database State'
        WHEN Txt LIKE '%autogrow%'
          OR Txt LIKE '%Auto-grow%'
          OR Txt LIKE '% grew %'
          OR Txt LIKE '%Autogrow%' THEN 'Auto-Growth'
        WHEN Txt LIKE '%deadlock%' THEN 'Deadlock'
        WHEN Txt LIKE '%Error%'
          OR Txt LIKE '%error%'
          OR Txt LIKE '%failed%' THEN 'Error / Failure'
        WHEN Txt LIKE '%Warning%'
          OR Txt LIKE '%warning%' THEN 'Warning'
        ELSE 'Informational'
    END
ORDER BY occurrences DESC;

DROP TABLE #ErrLog;
