/*
Script Name : Get-LockEscalationStats
Category    : performance
Purpose     : Shows tables with the most lock escalations since last restart.
              Lock escalation converts row/page locks to a table lock, increasing blocking.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-lock-contention-and-blocking-plans/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: sys.dm_db_index_operational_stats with NULL parameters covers all databases
  and all indexes. Aggregated per table (summing across all indexes) since escalation
  is a table-level event. Excludes system databases (database_id <= 4).

  High escalation counts on a table indicate:
    - Large batch operations scanning many rows (e.g. bulk updates, large deletes)
    - Queries that acquire more than 5,000 row/page locks in a single statement
  Remedies:
    - ALTER TABLE t SET (LOCK_ESCALATION = DISABLE) — prevents escalation (use carefully)
    - Batch large DML into smaller chunks to stay below the lock threshold
    - Add covering indexes to reduce rows scanned per operation
    - Use READ_COMMITTED_SNAPSHOT isolation to eliminate shared locks on reads
*/

SELECT TOP 30
    DB_NAME(ios.database_id) AS database_name,
    OBJECT_NAME(ios.object_id, ios.database_id) AS table_name,
    SUM(ios.index_lock_promotion_count) AS lock_escalations,
    SUM(ios.row_lock_count) AS row_lock_count,
    SUM(ios.page_lock_count) AS page_lock_count,
    SUM(ios.row_lock_wait_count) AS row_lock_wait_count,
    SUM(ios.page_lock_wait_count) AS page_lock_wait_count,
    CAST(SUM(ios.row_lock_wait_in_ms) / 1000.0 AS decimal(12,2)) AS row_lock_wait_sec,
    CAST(SUM(ios.page_lock_wait_in_ms) / 1000.0 AS decimal(12,2)) AS page_lock_wait_sec
FROM sys.dm_db_index_operational_stats(NULL, NULL, NULL, NULL) ios
WHERE ios.database_id > 4
  AND ios.index_lock_promotion_count > 0
GROUP BY
    ios.database_id,
    ios.object_id
ORDER BY
    lock_escalations DESC;
