/*
Script Name : Get-BlockingSummary
Category    : performance-troubleshooting
Purpose     : Quick blocking summary showing head blockers and blocked session counts.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    blocking_session_id AS head_blocker,
    COUNT(*) AS blocked_session_count,
    MAX(wait_time) / 1000 AS max_wait_seconds
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0
GROUP BY blocking_session_id
ORDER BY blocked_session_count DESC;
