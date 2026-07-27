/*
Script Name : Get-DistributionAgentStatus
Category    : high-availability
Purpose     : Monitors Distribution Agent activity — status, delivery latency (current and overall),
              transaction and command counts, and any replication errors. Returns the last 24 hours
              of history. Run against the distribution database (-Database distribution).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-replication-agent-status/)
Requires    : db_owner or replmonitor role on the distribution database
*/
-- Blog: https://sqldba.blog/dba-scripts-get-replication-agent-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    a.name                                          AS agent_name,
    CASE h.runstatus
        WHEN 1 THEN 'Start'
        WHEN 2 THEN 'Succeed'
        WHEN 3 THEN 'In progress'
        WHEN 4 THEN 'Idle'
        WHEN 5 THEN 'Retry'
        WHEN 6 THEN 'Fail'
        ELSE 'Unknown'
    END                                             AS status,
    h.start_time,
    h.[time]                                        AS logged_at,
    h.duration                                      AS duration_seconds,
    h.comments,
    h.xact_seqno                                    AS last_sequence_number,
    h.current_delivery_rate                         AS current_commands_per_sec,
    h.current_delivery_latency                      AS current_latency_ms,
    h.delivered_transactions,
    h.delivered_commands,
    h.average_commands,
    h.delivery_rate                                 AS avg_commands_per_sec,
    h.delivery_latency                              AS delivery_latency_ms,
    h.total_delivered_commands,
    h.error_id,
    e.error_text
FROM dbo.MSdistribution_history  h
JOIN dbo.MSdistribution_agents   a ON a.id = h.agent_id
LEFT JOIN dbo.MSrepl_errors      e ON e.id = h.error_id
WHERE h.[time] >= DATEADD(DAY, -1, GETDATE())
ORDER BY h.[time] DESC;
