/*
Script Name : Get-PerfmonDelta
Category    : collectors
Purpose     : Computes interval deltas for cumulative performance counters
              (cntr_type 272696576) between the two most recent snapshots in
              [DBAMonitor].[collector].[Perfmon]. Point-in-time gauges
              (cntr_type 65792) are shown as their current value.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : SELECT on [DBAMonitor].[collector].[Perfmon]
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase sysname       = N'DBAMonitor';
DECLARE @ServerName     nvarchar(128) = @@SERVERNAME;
DECLARE @Top            int           = 40;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @t1 datetime2, @t2 datetime2;

-- MAX() rather than TOP 1 ... ORDER BY: identical result, one ordered scan instead of a
-- parallel scan into a sort worktable (9 scans / 1495 logical reads -> 1 scan / 1420 on a
-- 77k-row table). Warm, both forms are single-digit milliseconds; the difference only shows
-- on a cold cache, where the sort form measured 11.9s against MAX()'s 14ms. There is no
-- index on collection_time, so both read the whole table for this server.
SELECT @t2 = MAX(collection_time)
FROM [DBAMonitor].[collector].[Perfmon]
WHERE server_name = @ServerName;

SELECT @t1 = MAX(collection_time)
FROM [DBAMonitor].[collector].[Perfmon]
WHERE server_name = @ServerName AND collection_time < @t2;

-- ── Cumulative counters: rate per second in the interval ──────────────────────
DECLARE @interval_s decimal(10,2);
SELECT @interval_s = CAST(DATEDIFF(SECOND, @t1, @t2) AS decimal(10,2));

SELECT TOP (@Top)
    s2.object_name,
    s2.counter_name,
    s2.instance_name,
    s2.cntr_value - s1.cntr_value                          AS delta_value,
    CASE WHEN @interval_s > 0
         THEN CAST((s2.cntr_value - s1.cntr_value) * 1.0 / @interval_s AS decimal(14,2))
         END                                                AS per_second,
    @t1                                                     AS snapshot1,
    @t2                                                     AS snapshot2,
    CAST(@interval_s AS int)                                AS interval_seconds
FROM [DBAMonitor].[collector].[Perfmon] s2
JOIN [DBAMonitor].[collector].[Perfmon] s1
    ON s1.server_name = s2.server_name
   AND s1.collection_time = @t1
   AND s1.object_name = s2.object_name
   AND s1.counter_name = s2.counter_name
   AND s1.instance_name = s2.instance_name
WHERE s2.server_name = @ServerName
  AND s2.collection_time = @t2
  AND s2.cntr_type = 272696576         -- cumulative bulk count: diff snapshots
  AND s2.cntr_value >= s1.cntr_value   -- positive delta only
ORDER BY delta_value DESC;

-- ── Point-in-time gauges: current value (no delta needed) ─────────────────────
SELECT TOP (@Top)
    object_name,
    counter_name,
    instance_name,
    cntr_value                                              AS current_value,
    collection_time                                         AS snapshot_time
FROM [DBAMonitor].[collector].[Perfmon]
WHERE server_name = @ServerName
  AND collection_time = @t2
  AND cntr_type = 65792               -- point-in-time gauge
ORDER BY object_name, counter_name, instance_name;
