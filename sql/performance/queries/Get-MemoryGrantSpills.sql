/*
Script Name : Get-MemoryGrantSpills
Category    : performance
Purpose     : Top queries by memory grant spills to TempDB. Spills occur when SQL grants
              less memory than a sort or hash join operator needs, forcing intermediate
              results to disk. Invisible in wait stats — shows as TempDB I/O pressure
              or RESOURCE_SEMAPHORE waits. Needs the total_spills column, which arrived in
              SQL Server 2016 SP2 and 2017 CU3, so the script detects the column rather than
              testing a version number.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- total_spills/max_spills arrived in SQL Server 2016 (13.x) SP2 and 2017 (14.x) CU3, NOT in
-- 2016 RTM. A major-version test cannot gate this anyway: the whole batch is bound before any
-- IF runs, so a static reference to a missing column fails to compile and the friendly message
-- never prints. Detect the column, and keep the query in dynamic SQL so it is only bound when
-- it can succeed. Same pattern as Get-CdcAndChangeTracking.
IF COL_LENGTH('sys.dm_exec_query_stats', 'total_spills') IS NULL
BEGIN
    SELECT 'Memory grant spill tracking (total_spills) needs SQL Server 2016 SP2 / 2017 CU3 or later. '
         + 'This instance is ' + CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')) + '.' AS info;
END
ELSE
BEGIN
    DECLARE @sql nvarchar(max) = N'
    SELECT TOP 30
        DB_NAME(qt.dbid) AS database_name,
        OBJECT_NAME(qt.objectid, qt.dbid) AS object_name,
        qs.execution_count,
        qs.total_spills AS total_spills,
        qs.total_spills / NULLIF(qs.execution_count, 0) AS avg_spills_per_exec,
        qs.max_spills AS max_spills_single_exec,
        -- Memory grant analysis (grant_kb columns: SQL 2016+)
        CAST(qs.total_grant_kb / 1024.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(10,2)) AS avg_granted_mb,
        CAST(qs.total_used_grant_kb / 1024.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(10,2)) AS avg_used_mb,
        CAST(qs.total_ideal_grant_kb / 1024.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(10,2)) AS avg_ideal_mb,
        -- Grant efficiency: used / granted (low = wasteful over-grant; high = under-grant causing spills)
        CAST(100.0 * qs.total_used_grant_kb / NULLIF(qs.total_grant_kb, 0) AS DECIMAL(5,1)) AS grant_efficiency_pct,
        -- Grant deficit: how much more memory was needed vs what was granted
        CAST((qs.total_ideal_grant_kb - qs.total_grant_kb)
             / 1024.0 / NULLIF(qs.execution_count, 0)
             AS DECIMAL(10,2)) AS avg_grant_deficit_mb,
        CAST(qs.total_worker_time / 1000.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(10,2)) AS avg_cpu_ms,
        CAST(qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS BIGINT) AS avg_logical_reads,
        qs.creation_time AS plan_cached_at,
        CASE
            WHEN qs.total_spills / NULLIF(qs.execution_count, 0) > 1000
            THEN ''CRITICAL - heavy spill every execution; query needs index, stats update, or hint''
            WHEN qs.total_ideal_grant_kb > qs.total_grant_kb * 2
            THEN ''WARN - grant consistently less than half of ideal; RESOURCE_SEMAPHORE pressure likely''
            WHEN qs.total_ideal_grant_kb > qs.total_grant_kb * 1.2
            THEN ''WARN - grant undersized vs ideal; spills expected under load''
            ELSE ''WARN - spilling (lower severity)''
        END AS diagnosis,
        LEFT(qt.text, 500) AS query_text
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
    WHERE qs.total_spills > 0
      AND qt.dbid > 4
    ORDER BY qs.total_spills DESC;';

    EXEC sys.sp_executesql @sql;
END;
