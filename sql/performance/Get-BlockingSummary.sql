/*
Script Name : Get-BlockingSummary
Category    : performance-troubleshooting
Purpose     : Head blockers with context — who is blocking, how many sessions, and what they are running.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

WITH blocked_counts AS (
    SELECT
        r.blocking_session_id,
        COUNT(*)                AS blocked_session_count,
        MAX(r.wait_time) / 1000 AS max_wait_sec,
        SUM(r.wait_time) / 1000 AS total_wait_sec
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
    GROUP BY r.blocking_session_id
)
SELECT
    bc.blocking_session_id                                          AS head_blocker_session_id,
    bc.blocked_session_count,
    bc.max_wait_sec,
    bc.total_wait_sec,
    s.login_name                                                    AS head_blocker_login,
    s.host_name                                                     AS head_blocker_host,
    s.program_name                                                  AS head_blocker_program,
    DB_NAME(s.database_id)                                          AS head_blocker_database,
    s.open_transaction_count,
    r.wait_type                                                     AS head_blocker_wait_type,
    CAST(ISNULL(r.wait_time, 0) / 1000.0 AS DECIMAL(10,1))        AS head_blocker_wait_sec,
    SUBSTRING(ISNULL(qt.text, ''), 1, 500)                         AS head_blocker_statement
FROM blocked_counts                  AS bc
JOIN  sys.dm_exec_sessions            AS s   ON s.session_id  = bc.blocking_session_id
LEFT JOIN sys.dm_exec_requests        AS r   ON r.session_id  = bc.blocking_session_id
LEFT JOIN sys.dm_exec_connections     AS c   ON c.session_id  = bc.blocking_session_id
                                           AND r.session_id  IS NULL
OUTER APPLY sys.dm_exec_sql_text(COALESCE(r.sql_handle, c.most_recent_sql_handle)) AS qt
ORDER BY bc.blocked_session_count DESC, bc.max_wait_sec DESC;
