/*
Script Name : Get-ActiveSessions
Category    : performance-troubleshooting
Purpose     : Show all active user sessions with current wait type, blocking, elapsed time, and statement.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    s.session_id,
    s.status                                                               AS session_status,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(s.database_id)                                                 AS database_name,
    s.open_transaction_count,
    r.status                                                               AS request_status,
    r.wait_type,
    CAST(ISNULL(r.wait_time, 0) / 1000.0 AS DECIMAL(10,2))                AS wait_time_sec,
    r.blocking_session_id,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,2))       AS elapsed_sec,
    r.cpu_time                                                             AS cpu_ms,
    r.logical_reads,
    r.writes,
    s.last_request_start_time,
    SUBSTRING(
        ISNULL(qt.text, ''),
        (ISNULL(r.statement_start_offset, 0) / 2) + 1,
        CASE
            WHEN ISNULL(r.statement_end_offset, -1) = -1
                THEN LEN(ISNULL(qt.text, ''))
            ELSE (r.statement_end_offset - r.statement_start_offset) / 2
        END
    )                                                                      AS current_statement
FROM sys.dm_exec_sessions    AS s
LEFT  JOIN sys.dm_exec_requests AS r  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS qt
WHERE s.is_user_process = 1
ORDER BY
    ISNULL(r.blocking_session_id, 0) DESC,
    s.open_transaction_count          DESC,
    s.session_id;
