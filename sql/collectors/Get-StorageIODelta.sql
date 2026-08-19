/*
Script Name : Get-StorageIODelta
Category    : collectors
Purpose     : Computes interval I/O deltas between the two most recent snapshots
              in [DBAMonitor].[collector].[StorageIO]. Shows read/write counts,
              bytes transferred, and derived average latency for the interval.
              Detects SQL Server restarts and suppresses invalid deltas.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : SELECT on [DBAMonitor].[collector].[StorageIO]
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- ── Parameters ────────────────────────────────────────────────────────────────
DECLARE @TargetDatabase sysname       = N'DBAMonitor';
DECLARE @ServerName     nvarchar(128) = @@SERVERNAME;
DECLARE @Top            int           = 25;
-- ─────────────────────────────────────────────────────────────────────────────

DECLARE @t1 datetime2, @t2 datetime2, @start1 datetime2, @start2 datetime2;

SELECT TOP 1 @t2 = collection_time
FROM [DBAMonitor].[collector].[StorageIO]
WHERE server_name = @ServerName
ORDER BY collection_time DESC;

SELECT TOP 1 @t1 = collection_time
FROM [DBAMonitor].[collector].[StorageIO]
WHERE server_name = @ServerName AND collection_time < @t2
ORDER BY collection_time DESC;

IF @t1 IS NULL
BEGIN
    SELECT 'Only one snapshot available - run the storage-io collector at least twice.' AS status;
    RETURN;
END

SELECT @start1 = MIN(sqlserver_start_time) FROM [DBAMonitor].[collector].[StorageIO]
WHERE server_name = @ServerName AND collection_time = @t1;
SELECT @start2 = MIN(sqlserver_start_time) FROM [DBAMonitor].[collector].[StorageIO]
WHERE server_name = @ServerName AND collection_time = @t2;

IF @start1 <> @start2
BEGIN
    SELECT 'SQL Server restarted between snapshots - counters reset, delta invalid.' AS status,
           @t1 AS snapshot1, @t2 AS snapshot2;
    RETURN;
END

SELECT TOP (@Top)
    s2.database_name,
    s2.physical_name,
    s2.file_type,
    -- Interval read metrics
    s2.num_of_reads       - s1.num_of_reads       AS interval_reads,
    s2.num_of_bytes_read  - s1.num_of_bytes_read  AS interval_bytes_read,
    CASE WHEN s2.num_of_reads - s1.num_of_reads > 0
         THEN CAST((s2.io_stall_read_ms - s1.io_stall_read_ms) * 1.0
                   / (s2.num_of_reads - s1.num_of_reads) AS decimal(10,2))
         END                                        AS avg_read_latency_ms,
    -- Interval write metrics
    s2.num_of_writes      - s1.num_of_writes      AS interval_writes,
    s2.num_of_bytes_written - s1.num_of_bytes_written AS interval_bytes_written,
    CASE WHEN s2.num_of_writes - s1.num_of_writes > 0
         THEN CAST((s2.io_stall_write_ms - s1.io_stall_write_ms) * 1.0
                   / (s2.num_of_writes - s1.num_of_writes) AS decimal(10,2))
         END                                        AS avg_write_latency_ms,
    -- Total stall for sort
    (s2.io_stall - s1.io_stall)                    AS interval_total_stall_ms,
    @t1                                             AS snapshot1,
    @t2                                             AS snapshot2
FROM [DBAMonitor].[collector].[StorageIO] s2
JOIN [DBAMonitor].[collector].[StorageIO] s1
    ON s1.server_name = s2.server_name
   AND s1.collection_time = @t1
   AND s1.database_id = s2.database_id
   AND s1.file_id = s2.file_id
WHERE s2.server_name = @ServerName
  AND s2.collection_time = @t2
  AND (s2.num_of_reads - s1.num_of_reads + s2.num_of_writes - s1.num_of_writes) > 0
ORDER BY interval_total_stall_ms DESC;
