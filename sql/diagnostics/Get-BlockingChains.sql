/*
Script Name : Get-BlockingChains
Category    : diagnostics
Purpose     : Traces all active blocking chains using a recursive CTE. Returns
              every session involved in blocking — head blockers, mid-chain
              nodes, and leaf victims — ordered so each chain reads depth-first.
              Idle head blockers (sleeping but holding locks) are included; their
              last executed statement is recovered via sys.dm_exec_connections.
              Returns no rows when the server is not blocked.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE

Performance note: dm_exec_requests is materialised into #ar once to avoid
repeated DMV scans. downstream_waiters is pre-aggregated rather than computed
via a correlated subquery. dm_exec_connections is joined only for sessions
that have no active request (idle head blockers).
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

-- Materialise once — the recursive CTE and downstream count would otherwise
-- each trigger a separate scan of sys.dm_exec_requests.
DROP TABLE IF EXISTS #ar;

SELECT
    session_id, blocking_session_id, status, wait_type, wait_time,
    cpu_time, logical_reads, writes, total_elapsed_time,
    sql_handle, plan_handle, database_id,
    statement_start_offset, statement_end_offset
INTO #ar
FROM sys.dm_exec_requests
WHERE session_id <> @@SPID;

WITH
DownstreamCounts AS (
    SELECT blocking_session_id,
           COUNT(*) AS downstream_waiters
    FROM   #ar
    WHERE  blocking_session_id > 0
    GROUP BY blocking_session_id
),
Chain AS (
    -- Anchor: head blockers — block others but are not themselves blocked
    SELECT
        s.session_id                                              AS chain_id,
        0                                                         AS chain_level,
        CAST('head blocker' AS VARCHAR(16))                       AS role,
        CAST(0 AS SMALLINT)                                       AS blocker_session_id,
        s.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        s.open_transaction_count,
        COALESCE(r.status, s.status)                              AS status,
        r.wait_type,
        r.wait_time,
        r.cpu_time,
        r.logical_reads,
        r.writes,
        r.total_elapsed_time,
        COALESCE(r.database_id, s.database_id)                   AS database_id,
        COALESCE(r.statement_start_offset, 0)                    AS statement_start_offset,
        COALESCE(r.statement_end_offset,  -1)                    AS statement_end_offset,
        -- Only fetch dm_exec_connections when there is no active request (idle blocker)
        COALESCE(r.sql_handle, c.most_recent_sql_handle)         AS sql_handle,
        r.plan_handle
    FROM      sys.dm_exec_sessions    AS s
    LEFT JOIN #ar                     AS r  ON r.session_id  = s.session_id
    LEFT JOIN sys.dm_exec_connections AS c  ON c.session_id  = s.session_id
                                          AND r.session_id  IS NULL
    WHERE s.is_user_process = 1
      AND     EXISTS (SELECT 1 FROM #ar WHERE blocking_session_id = s.session_id)
      AND NOT EXISTS (SELECT 1 FROM #ar WHERE session_id = s.session_id AND blocking_session_id > 0)

    UNION ALL

    -- Recursive: victims blocked by the previous chain level
    SELECT
        ch.chain_id,
        ch.chain_level + 1,
        CAST('blocked' AS VARCHAR(16)),
        r.blocking_session_id,
        r.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        s.open_transaction_count,
        r.status,
        r.wait_type,
        r.wait_time,
        r.cpu_time,
        r.logical_reads,
        r.writes,
        r.total_elapsed_time,
        r.database_id,
        r.statement_start_offset,
        r.statement_end_offset,
        r.sql_handle,
        r.plan_handle
    FROM      #ar                    AS r
    JOIN      sys.dm_exec_sessions   AS s  ON s.session_id  = r.session_id
    JOIN      Chain                  AS ch ON ch.session_id = r.blocking_session_id
    WHERE r.blocking_session_id > 0
)
SELECT
    ch.chain_id,
    ch.chain_level,
    ch.role,
    ch.blocker_session_id,
    ch.session_id,
    ch.login_name,
    ch.host_name,
    ch.program_name,
    DB_NAME(ch.database_id)                                                              AS database_name,
    ch.open_transaction_count,
    ch.status,
    ch.wait_type,
    ISNULL(ch.wait_time,          0)                                                     AS wait_time_ms,
    ISNULL(ch.cpu_time,           0)                                                     AS cpu_time_ms,
    ISNULL(ch.logical_reads,      0)                                                     AS logical_reads,
    ISNULL(ch.writes,             0)                                                     AS writes,
    ISNULL(ch.total_elapsed_time, 0)                                                     AS total_elapsed_time_ms,
    ISNULL(dc.downstream_waiters, 0)                                                     AS downstream_waiters,
    CAST(
        (ISNULL(su.user_objects_alloc_page_count,     0) +
         ISNULL(su.internal_objects_alloc_page_count, 0)) * 8
    AS BIGINT)                                                                           AS tempdb_allocations_kb,
    CAST(
        (ISNULL(su.user_objects_alloc_page_count,      0) - ISNULL(su.user_objects_dealloc_page_count,      0) +
         ISNULL(su.internal_objects_alloc_page_count,  0) - ISNULL(su.internal_objects_dealloc_page_count,  0)) * 8
    AS BIGINT)                                                                           AS tempdb_current_kb,
    SUBSTRING(
        ISNULL(qt.text, ''),
        (ch.statement_start_offset / 2) + 1,
        CASE
            WHEN ch.statement_end_offset = -1
                THEN LEN(ISNULL(qt.text, ''))
            ELSE (ch.statement_end_offset - ch.statement_start_offset) / 2 + 1
        END
    )                                                                                    AS sql_text
FROM      Chain                         AS ch
LEFT JOIN DownstreamCounts              AS dc ON dc.blocking_session_id = ch.session_id
LEFT JOIN sys.dm_db_session_space_usage AS su ON su.session_id          = ch.session_id
OUTER APPLY sys.dm_exec_sql_text(ch.sql_handle) AS qt
ORDER BY
    ch.chain_id,
    ch.chain_level,
    ch.session_id
OPTION (MAXRECURSION 10);
