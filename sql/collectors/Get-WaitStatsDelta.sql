/*
Script Name : Get-WaitStatsDelta
Category    : collectors
Purpose     : Computes interval wait deltas between the two most recent snapshots
              in [DBAMonitor].[collector].[WaitStats]. Shows delta_wait_ms, task count,
              average wait per task, and percentage of total interval wait — sorted
              by heaviest waiter descending. Detects SQL Server restarts between
              snapshots and suppresses invalid deltas.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : SELECT on [DBAMonitor].[collector].[WaitStats]
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase sysname       = N'DBAMonitor';
DECLARE @ServerName     nvarchar(128) = @@SERVERNAME;   -- override for remote collection
DECLARE @Top            int           = 25;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @t1 datetime2, @t2 datetime2, @start1 datetime2, @start2 datetime2;

SELECT TOP 1 @t2 = collection_time
FROM [DBAMonitor].[collector].[WaitStats]
WHERE server_name = @ServerName
ORDER BY collection_time DESC;

SELECT TOP 1 @t1 = collection_time
FROM [DBAMonitor].[collector].[WaitStats]
WHERE server_name = @ServerName AND collection_time < @t2
ORDER BY collection_time DESC;

IF @t1 IS NULL
BEGIN
    SELECT 'Only one snapshot available - run the wait-stats collector at least twice.' AS status;
    RETURN;
END

SELECT @start1 = MIN(sqlserver_start_time) FROM [DBAMonitor].[collector].[WaitStats]
WHERE server_name = @ServerName AND collection_time = @t1;
SELECT @start2 = MIN(sqlserver_start_time) FROM [DBAMonitor].[collector].[WaitStats]
WHERE server_name = @ServerName AND collection_time = @t2;

IF @start1 <> @start2
BEGIN
    SELECT 'SQL Server restarted between snapshots - counters reset, delta invalid.' AS status,
           @t1 AS snapshot1, @t2 AS snapshot2, @start1 AS start_time_1, @start2 AS start_time_2;
    RETURN;
END

;WITH deltas AS (
    SELECT
        s2.wait_type,
        s2.wait_time_ms          - s1.wait_time_ms          AS delta_wait_ms,
        s2.waiting_tasks_count   - s1.waiting_tasks_count   AS delta_tasks,
        s2.signal_wait_time_ms   - s1.signal_wait_time_ms   AS delta_signal_ms,
        s2.max_wait_time_ms                                  AS max_wait_ms
    FROM [DBAMonitor].[collector].[WaitStats] s2
    JOIN [DBAMonitor].[collector].[WaitStats] s1
        ON s1.server_name = s2.server_name
       AND s1.collection_time = @t1
       AND s1.wait_type = s2.wait_type
    WHERE s2.server_name = @ServerName
      AND s2.collection_time = @t2
      AND s2.wait_time_ms > s1.wait_time_ms
),
totals AS (SELECT SUM(delta_wait_ms) AS total_ms FROM deltas)
SELECT TOP (@Top)
    d.wait_type,
    d.delta_wait_ms,
    d.delta_tasks,
    CASE WHEN d.delta_tasks > 0
         THEN CAST(d.delta_wait_ms * 1.0 / d.delta_tasks AS decimal(10,1))
         END                                                        AS avg_wait_ms,
    CAST(d.delta_signal_ms * 100.0 / NULLIF(d.delta_wait_ms,0) AS decimal(5,1))
                                                                    AS signal_pct,
    -- Percent of the total WAIT accumulated in the window (totals.total_ms is
    -- SUM(delta_wait_ms)), NOT percent of the wall-clock interval. It was called
    -- pct_of_interval until 2026-08-20 and that name said the wrong thing: a single task
    -- can accumulate more wait than the interval is long, so the published sample output
    -- showed QDS_ASYNC_QUEUE at 43,912,480 ms with delta_tasks = 1 over four minutes.
    -- Read it as "which wait dominated", never as "how busy the window was".
    CAST(d.delta_wait_ms * 100.0 / NULLIF(t.total_ms,0) AS decimal(5,1))
                                                                    AS pct_of_total_wait,
    d.max_wait_ms,
    @t1                                                             AS snapshot1,
    @t2                                                             AS snapshot2
FROM deltas d
CROSS JOIN totals t
ORDER BY d.delta_wait_ms DESC;
