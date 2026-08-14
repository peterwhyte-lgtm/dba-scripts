/*
Script Name : Get-ActiveConnectionsByDatabase
Category    : monitoring
Purpose     : Session count, active requests, open transactions, and blocked sessions grouped by database — essential check before taking any database offline or starting a decommission.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-active-connections-by-database/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    DB_NAME(s.database_id) AS database_name,
    COUNT(*) AS total_sessions,
    SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS active_requests,
    SUM(CASE WHEN s.open_transaction_count > 0 THEN 1 ELSE 0 END) AS open_transactions,
    SUM(CASE WHEN r.blocking_session_id > 0 THEN 1 ELSE 0 END) AS blocked_sessions,
    COUNT(DISTINCT s.login_name) AS distinct_logins,
    MAX(DATEDIFF(MINUTE, s.login_time, GETDATE())) AS oldest_conn_min,
    MIN(s.login_time) AS oldest_login_time
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON r.session_id = s.session_id
WHERE s.is_user_process = 1
  AND s.database_id > 0
GROUP BY s.database_id
ORDER BY total_sessions DESC, active_requests DESC;
