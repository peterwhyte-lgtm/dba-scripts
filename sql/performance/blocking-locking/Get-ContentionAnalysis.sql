/*
Script Name : Get-ContentionAnalysis
Category    : performance
Purpose     : Unified contention summary across lock waits, latch waits, TempDB allocation
              pressure, and spinlock contention. All figures are cumulative since the last
              SQL Server restart — high counts on a recently restarted instance are not
              necessarily concerning.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-lock-contention-and-blocking-plans/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @min_wait_count BIGINT = 100; -- suppress trivial entries with fewer wait occurrences
DECLARE @min_spinlock_collisions BIGINT = 50000; -- only flag high-volume spinlocks

SELECT
    contention_type,
    resource_name,
    wait_count,
    total_wait_ms,
    avg_wait_ms,
    days_since_restart,
    note
FROM (

    -- ── Lock waits ──────────────────────────────────────────────────────────────
    -- LCK_M_* waits represent time spent waiting for row/page/object locks.
    -- High values combined with active blocking indicate a locking hotspot.
    SELECT
        'LOCK' AS contention_type,
        ws.wait_type AS resource_name,
        ws.waiting_tasks_count AS wait_count,
        ws.wait_time_ms AS total_wait_ms,
        CAST(ws.wait_time_ms * 1.0
             / NULLIF(ws.waiting_tasks_count, 0) AS DECIMAL(12,2)) AS avg_wait_ms,
        uptime.days_since_restart,
        'Locking contention - run Get-BlockingChains for real-time chain analysis' AS note
    FROM sys.dm_os_wait_stats ws
    CROSS JOIN (
        SELECT DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS days_since_restart
        FROM sys.dm_os_sys_info
    ) uptime
    WHERE ws.wait_type LIKE 'LCK_M_%'
      AND ws.waiting_tasks_count >= @min_wait_count

    UNION ALL

    -- ── Latch waits ─────────────────────────────────────────────────────────────
    -- Latches protect internal memory structures. PAGEIOLATCH = I/O waits on data pages.
    -- ACCESS_METHODS / BUFFER / FGCB = internal structure contention.
    SELECT
        'LATCH',
        ls.latch_class,
        ls.waiting_requests_count,
        ls.wait_time_ms,
        CAST(ls.wait_time_ms * 1.0
             / NULLIF(ls.waiting_requests_count, 0) AS DECIMAL(12,2)),
        uptime.days_since_restart,
        CASE
            WHEN ls.latch_class LIKE 'PAGEIOLATCH%'
                THEN 'I/O latch - data page reads are slow; check disk latency'
            WHEN ls.latch_class LIKE 'ACCESS_METHODS%'
                THEN 'Scan/seek contention - high concurrent read/write activity'
            WHEN ls.latch_class = 'BUFFER'
                THEN 'Buffer pool contention - memory pressure or heavy page access'
            WHEN ls.latch_class LIKE 'FGCB%'
                THEN 'Filegroup cache contention - check filegroup configuration'
            ELSE 'Internal latch contention - investigate if avg_wait_ms is high'
        END
    FROM sys.dm_os_latch_stats ls
    CROSS JOIN (
        SELECT DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS days_since_restart
        FROM sys.dm_os_sys_info
    ) uptime
    WHERE ls.waiting_requests_count >= @min_wait_count
      AND ls.latch_class NOT LIKE 'LOG_%' -- log latches are usually expected
      AND ls.latch_class NOT LIKE 'LOGGING_%'

    UNION ALL

    -- ── TempDB allocation page contention ────────────────────────────────────────
    -- PAGELATCH_UP/EX on TempDB is classic allocation bitmap contention (PFS, GAM, SGAM).
    -- Symptom: many concurrent object creates/drops in TempDB (temp tables, table variables).
    -- Fix: add TempDB data files up to the number of logical CPUs (max 8).
    SELECT
        'TEMPDB_ALLOC',
        ws.wait_type,
        ws.waiting_tasks_count,
        ws.wait_time_ms,
        CAST(ws.wait_time_ms * 1.0
             / NULLIF(ws.waiting_tasks_count, 0) AS DECIMAL(12,2)),
        uptime.days_since_restart,
        CASE ws.wait_type
            WHEN 'PAGELATCH_UP' THEN 'TempDB PFS/GAM/SGAM allocation contention - add TempDB files (up to # of logical CPUs, max 8)'
            WHEN 'PAGELATCH_EX' THEN 'TempDB exclusive page latch - likely allocation bitmap contention'
            ELSE 'TempDB shared page latch - allocation page reads'
        END
    FROM sys.dm_os_wait_stats ws
    CROSS JOIN (
        SELECT DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS days_since_restart
        FROM sys.dm_os_sys_info
    ) uptime
    WHERE ws.wait_type IN ('PAGELATCH_UP', 'PAGELATCH_EX', 'PAGELATCH_SH')
      AND ws.waiting_tasks_count >= @min_wait_count

    UNION ALL

    -- ── Spinlock contention ──────────────────────────────────────────────────────
    -- Spinlocks are lightweight CPU-spinning locks protecting very short-lived structures.
    -- High spins-per-collision ratio (>1000) on a specific spinlock indicates a hot path.
    -- Note: total_wait_ms = spins / 1000 (proxy — spinlocks do not track wall-clock time).
    -- avg_wait_ms = spins per collision (spin ratio, not milliseconds).
    SELECT
        'SPINLOCK',
        ss.name,
        ss.collisions,
        ss.spins / 1000, -- proxy: not ms, but comparable magnitude for sorting
        CAST(ss.spins * 1.0 / NULLIF(ss.collisions, 0) AS DECIMAL(12,2)), -- spin ratio
        uptime.days_since_restart,
        'Spin ratio: ' + CAST(CAST(ss.spins * 1.0 / NULLIF(ss.collisions, 0) AS DECIMAL(10,0)) AS VARCHAR)
            + ' spins/collision - avg_wait_ms column shows spin ratio, not ms'
    FROM sys.dm_os_spinlock_stats ss
    CROSS JOIN (
        SELECT DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS days_since_restart
        FROM sys.dm_os_sys_info
    ) uptime
    WHERE ss.collisions >= @min_spinlock_collisions
      AND ss.spins / NULLIF(ss.collisions, 0) > 1000

) contention
ORDER BY
    CASE contention_type
        WHEN 'LOCK' THEN 1
        WHEN 'LATCH' THEN 2
        WHEN 'TEMPDB_ALLOC' THEN 3
        WHEN 'SPINLOCK' THEN 4
    END,
    total_wait_ms DESC;
