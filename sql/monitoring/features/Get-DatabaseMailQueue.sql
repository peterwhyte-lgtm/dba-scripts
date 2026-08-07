/*
Script Name : Get-DatabaseMailQueue
Category    : monitoring
Purpose     : Database Mail items that are failed, retrying, or unsent — plus last 24 hours of sent mail for context. Shows error detail for failed items.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/)
Requires    : msdb access (DatabaseMailUserRole or sysadmin)
*/
-- Blog: https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    m.mailitem_id,
    m.subject,
    LEFT(m.recipients, 200) AS recipients,
    m.sent_status,
    m.send_request_date,
    m.sent_date,
    DATEDIFF(MINUTE, m.send_request_date, COALESCE(m.sent_date, GETDATE())) AS queue_minutes,
    m.send_request_user,
    LEFT(l.description, 500) AS error_detail
FROM msdb.dbo.sysmail_allitems m
LEFT JOIN (
    SELECT mailitem_id, MAX(log_id) AS latest_log_id
    FROM msdb.dbo.sysmail_event_log
    WHERE event_type = 'error'
    GROUP BY mailitem_id
) latest ON latest.mailitem_id = m.mailitem_id
LEFT JOIN msdb.dbo.sysmail_event_log l ON l.log_id = latest.latest_log_id
WHERE m.sent_status IN ('failed', 'retrying', 'unsent')
   OR m.send_request_date >= DATEADD(HOUR, -24, GETDATE())
ORDER BY
    CASE m.sent_status WHEN 'failed' THEN 1
                       WHEN 'retrying' THEN 2
                       WHEN 'unsent' THEN 3
                       ELSE 4 END,
    m.send_request_date DESC;
