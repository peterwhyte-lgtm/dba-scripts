/*
Script Name : Get-DatabaseFreeSpaceSummary
Category    : monitoring
Purpose     : Allocated, used, and free space for all online databases, ordered by total free space descending.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-free-space-summary/)
Requires    : VIEW SERVER STATE, VIEW DATABASE STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* Set to 1 to hide master/model/msdb/tempdb */
DECLARE @ExcludeSystemDBs BIT = 0;

/* ── Temp tables ─────────────────────────────────────────────────────────── */
IF OBJECT_ID('tempdb..#SpaceInfo') IS NOT NULL DROP TABLE #SpaceInfo;
CREATE TABLE #SpaceInfo (
    DatabaseName NVARCHAR(128) NOT NULL,
    DataAllocMB DECIMAL(20,2) NOT NULL DEFAULT 0,
    DataUsedMB DECIMAL(20,2) NOT NULL DEFAULT 0,
    LogAllocMB DECIMAL(20,2) NOT NULL DEFAULT 0,
    LogUsedMB DECIMAL(20,2) NOT NULL DEFAULT 0
);

IF OBJECT_ID('tempdb..#LogSpace') IS NOT NULL DROP TABLE #LogSpace;
CREATE TABLE #LogSpace (
    DatabaseName NVARCHAR(128),
    LogSizeMB FLOAT,
    LogUsedPct FLOAT,
    [Status] TINYINT
);

/* ── Capture log space from DBCC SQLPERF (one call for all DBs) ─────────── */
INSERT INTO #LogSpace
EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');

/* ── Cursor: collect data-file sizes via per-database context switch ──────── */
DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cur CURSOR FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND HAS_DBACCESS(name) = 1
      AND (@ExcludeSystemDBs = 0 OR database_id > 4)
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';
        INSERT INTO #SpaceInfo (DatabaseName, DataAllocMB, DataUsedMB, LogAllocMB, LogUsedMB)
        SELECT
            DB_NAME(),
            SUM(CASE WHEN type_desc = ''ROWS''
                     THEN CAST(size AS BIGINT) * 8.0 / 1024
                     ELSE 0 END),
            SUM(CASE WHEN type_desc = ''ROWS''
                     THEN CAST(COALESCE(FILEPROPERTY(name, ''SpaceUsed''), 0) AS BIGINT) * 8.0 / 1024
                     ELSE 0 END),
            SUM(CASE WHEN type_desc = ''LOG''
                     THEN CAST(size AS BIGINT) * 8.0 / 1024
                     ELSE 0 END),
            0
        FROM sys.database_files;
    ';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        /* Skip databases that are inaccessible mid-run */
    END CATCH;

    FETCH NEXT FROM db_cur INTO @db;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

/* ── Merge log-used percentages from DBCC SQLPERF ───────────────────────── */
UPDATE s
SET s.LogUsedMB = CAST(l.LogSizeMB * l.LogUsedPct / 100.0 AS DECIMAL(20,2))
FROM #SpaceInfo s
JOIN #LogSpace l ON l.DatabaseName = s.DatabaseName;

/* ── Final report ────────────────────────────────────────────────────────── */
;WITH calc AS (
    SELECT
        DatabaseName,
        DataAllocMB,
        DataUsedMB,
        CASE WHEN DataAllocMB - DataUsedMB > 0
             THEN DataAllocMB - DataUsedMB ELSE 0 END AS DataFreeMB,
        LogAllocMB,
        LogUsedMB,
        CASE WHEN LogAllocMB - LogUsedMB > 0
             THEN LogAllocMB - LogUsedMB ELSE 0 END AS LogFreeMB,
        DataAllocMB + LogAllocMB AS TotalAllocMB,
        DataUsedMB + LogUsedMB AS TotalUsedMB,
          CASE WHEN DataAllocMB - DataUsedMB > 0 THEN DataAllocMB - DataUsedMB ELSE 0 END
        + CASE WHEN LogAllocMB - LogUsedMB > 0 THEN LogAllocMB - LogUsedMB ELSE 0 END AS TotalFreeMB
    FROM #SpaceInfo
)
SELECT
    DatabaseName,

    /* ── Totals ──────────────────────────────────────────────────────────── */
    CASE WHEN TotalAllocMB >= 1048576 THEN CAST(CAST(TotalAllocMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN TotalAllocMB >= 1024 THEN CAST(CAST(TotalAllocMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(TotalAllocMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Total Allocated],

    CASE WHEN TotalUsedMB >= 1048576 THEN CAST(CAST(TotalUsedMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN TotalUsedMB >= 1024 THEN CAST(CAST(TotalUsedMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(TotalUsedMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Total Used],

    CASE WHEN TotalFreeMB >= 1048576 THEN CAST(CAST(TotalFreeMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN TotalFreeMB >= 1024 THEN CAST(CAST(TotalFreeMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(TotalFreeMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Total Free],

    CAST(
        CASE WHEN TotalAllocMB > 0
             THEN TotalFreeMB * 100.0 / TotalAllocMB
             ELSE 0
        END AS DECIMAL(5,2)) AS [Free %],

    /* ── Data files ──────────────────────────────────────────────────────── */
    CASE WHEN DataAllocMB >= 1048576 THEN CAST(CAST(DataAllocMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN DataAllocMB >= 1024 THEN CAST(CAST(DataAllocMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(DataAllocMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Data Allocated],

    CASE WHEN DataUsedMB >= 1048576 THEN CAST(CAST(DataUsedMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN DataUsedMB >= 1024 THEN CAST(CAST(DataUsedMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(DataUsedMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Data Used],

    CASE WHEN DataFreeMB >= 1048576 THEN CAST(CAST(DataFreeMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN DataFreeMB >= 1024 THEN CAST(CAST(DataFreeMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(DataFreeMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Data Free],

    /* ── Log files ───────────────────────────────────────────────────────── */
    CASE WHEN LogAllocMB >= 1048576 THEN CAST(CAST(LogAllocMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN LogAllocMB >= 1024 THEN CAST(CAST(LogAllocMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(LogAllocMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Log Allocated],

    CASE WHEN LogUsedMB >= 1048576 THEN CAST(CAST(LogUsedMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN LogUsedMB >= 1024 THEN CAST(CAST(LogUsedMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(LogUsedMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Log Used],

    CASE WHEN LogFreeMB >= 1048576 THEN CAST(CAST(LogFreeMB / 1048576.0 AS DECIMAL(10,2)) AS VARCHAR) + ' TB'
         WHEN LogFreeMB >= 1024 THEN CAST(CAST(LogFreeMB / 1024.0 AS DECIMAL(10,2)) AS VARCHAR) + ' GB'
         ELSE CAST(CAST(LogFreeMB AS DECIMAL(10,2)) AS VARCHAR) + ' MB'
    END AS [Log Free],

    /* ── Raw MB columns for charting ─────────────────────────────────────── */
    TotalAllocMB,
    TotalUsedMB,
    TotalFreeMB

FROM calc
ORDER BY TotalFreeMB DESC;

/* ── Cleanup ─────────────────────────────────────────────────────────────── */
IF OBJECT_ID('tempdb..#SpaceInfo') IS NOT NULL DROP TABLE #SpaceInfo;
IF OBJECT_ID('tempdb..#LogSpace') IS NOT NULL DROP TABLE #LogSpace;
