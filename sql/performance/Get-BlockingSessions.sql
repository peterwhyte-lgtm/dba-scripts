/*
Script Name : Get-BlockingSessions
Category    : performance-troubleshooting
Purpose     : Show sessions involved in blocking chains with wait type, timing, and current statement.
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
    DB_NAME(s.database_id)                                          AS database_name,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    r.blocking_session_id,
    r.wait_type,
    CAST(ISNULL(r.wait_time, 0) / 1000.0 AS DECIMAL(10,1))        AS wait_sec,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,1)) AS elapsed_sec,
    r.cpu_time,
    r.logical_reads,
    t.text                                                          AS current_statement
FROM sys.dm_exec_sessions    AS s
LEFT  JOIN sys.dm_exec_requests AS r  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND (r.blocking_session_id IS NOT NULL OR r.wait_type IS NOT NULL)
ORDER BY ISNULL(r.wait_time, 0) DESC;
