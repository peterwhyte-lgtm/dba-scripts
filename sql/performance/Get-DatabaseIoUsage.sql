/*
Script Name : Get-DatabaseIoUsage
Category    : performance-troubleshooting
Purpose     : Database I/O totals with percentage share, MB read/written, and latency breakdown.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH io_stats AS
(
    SELECT
        vfs.database_id,
        SUM(vfs.num_of_reads)                AS total_reads,
        SUM(vfs.num_of_writes)               AS total_writes,
        SUM(vfs.num_of_bytes_read)           AS total_bytes_read,
        SUM(vfs.num_of_bytes_written)        AS total_bytes_written,
        SUM(vfs.io_stall_read_ms)            AS total_read_stall_ms,
        SUM(vfs.io_stall_write_ms)           AS total_write_stall_ms
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    GROUP BY vfs.database_id
),

totals AS
(
    SELECT
        SUM(total_reads)          AS grand_total_reads,
        SUM(total_writes)         AS grand_total_writes,
        SUM(total_read_stall_ms)  AS grand_total_read_stall_ms,
        SUM(total_write_stall_ms) AS grand_total_write_stall_ms
    FROM io_stats
)
SELECT
    DB_NAME(io.database_id) AS database_name,
    io.total_reads,
    CAST(100.0 * io.total_reads / NULLIF(t.grand_total_reads, 0) AS DECIMAL(6,2)) AS pct_total_reads,
    io.total_writes,
    CAST(100.0 * io.total_writes / NULLIF(t.grand_total_writes, 0) AS DECIMAL(6,2)) AS pct_total_writes,
    io.total_bytes_read / 1024 / 1024 AS total_mb_read,
    io.total_bytes_written / 1024 / 1024 AS total_mb_written,
    io.total_read_stall_ms,
    CAST(100.0 * io.total_read_stall_ms / NULLIF(t.grand_total_read_stall_ms, 0) AS DECIMAL(6,2)) AS pct_total_read_stall,
    io.total_write_stall_ms,
    CAST(100.0 * io.total_write_stall_ms / NULLIF(t.grand_total_write_stall_ms, 0) AS DECIMAL(6,2)) AS pct_total_write_stall
FROM io_stats io
CROSS JOIN totals t
ORDER BY pct_total_write_stall DESC;
