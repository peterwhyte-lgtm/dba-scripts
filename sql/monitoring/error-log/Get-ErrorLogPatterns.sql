/*
Script Name : Get-ErrorLogPatterns
Category    : monitoring
Purpose     : Reads the current SQL Server error log and groups entries by category — surfaces memory pressure, login failures, IO issues, corruption warnings, and auto-growth events without scrolling through raw entries.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-error-log-patterns/)
Requires    : EXECUTE on xp_readerrorlog, which is granted to sysadmin and securityadmin.
              VIEW SERVER STATE does not grant it.
*/
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

/* Categorise once, in a CTE. The CASE used to be written out twice, in the SELECT and
   again in the GROUP BY, so any change to a pattern had to be made in both places or the
   two would silently disagree. */
WITH categorised AS (
    SELECT
        LogDate,
        Txt,
        CASE
            WHEN Txt LIKE '%paged out%'
              OR Txt LIKE '%virtual address space%'
              OR Txt LIKE '%out of memory%'
              OR Txt LIKE '%cannot allocate%' THEN 'Memory Pressure'
            WHEN Txt LIKE '%login failed%'
              OR Txt LIKE '%18456%'
              OR Txt LIKE '%password%incorrect%' THEN 'Login Failure'
            /* Corruption is tested BEFORE IO and Backup, and its patterns match the way the
               error log actually writes these lines. Verified 2026-08-30, and the category was
               inverted before that: 'Error: 823, Severity: 24' matched nothing at all and fell
               through to Error / Failure, the real 824 text ('logical consistency-based I/O
               error') matched IO Issue first and never reached here, and the ONLY thing landing
               in Corruption / Integrity was 'CHECKDB ... finished without errors', a success
               message. The bucket a DBA scans first for corruption could not detect corruption. */
            WHEN Txt LIKE '%corrupt%'
              OR Txt LIKE '%consistency-based I/O error%'
              OR Txt LIKE '%Error: 823%'
              OR Txt LIKE '%Error: 824%'
              OR Txt LIKE '%Error: 825%'
              OR Txt LIKE '% 823 %'
              OR Txt LIKE '% 824 %'
              OR Txt LIKE '% 825 %'
              OR Txt LIKE '%suspect_pages%'
              OR (Txt LIKE '%CHECKDB%'
                  AND Txt NOT LIKE '%without errors%'
                  AND Txt NOT LIKE '%0 allocation errors and 0 consistency errors%')
                 THEN 'Corruption / Integrity'
            /* A clean integrity check is good news and must not be filed as a failure. Both
               wordings are excluded above and caught here, because 'finished without errors'
               and 'found 0 allocation errors' both contain the word errors and would otherwise
               be swept up by the generic Error / Failure branch further down. */
            WHEN Txt LIKE '%without errors%'
              OR Txt LIKE '%0 allocation errors and 0 consistency errors%'
                 THEN 'Informational'
            WHEN Txt LIKE '%Backup%'
              OR Txt LIKE '%BACKUP%'
              OR Txt LIKE '%backup of database%'
              OR Txt LIKE '%RESTORE%' THEN 'Backup / Restore'
            WHEN Txt LIKE '%I/O%'
              OR Txt LIKE '%stall%'
              OR Txt LIKE '%stalled%'
              OR Txt LIKE '%disk%' THEN 'IO Issue'
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
        END AS category
    FROM #ErrLog
),
/* latest_message must be the most RECENT entry in the category. It used to be
   LEFT(MAX(Txt), 200), which is the alphabetically greatest text, not the newest one, and
   it sat next to last_seen where a reader would naturally read the two as the same event. */
ranked AS (
    SELECT
        category,
        LogDate,
        Txt,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY LogDate DESC, Txt) AS rn
    FROM categorised
)
SELECT
    category,
    COUNT(*)                                        AS occurrences,
    MIN(LogDate)                                    AS first_seen,
    MAX(LogDate)                                    AS last_seen,
    LEFT(MAX(CASE WHEN rn = 1 THEN Txt END), 200)   AS latest_message
FROM ranked
GROUP BY category
ORDER BY occurrences DESC;

DROP TABLE #ErrLog;
