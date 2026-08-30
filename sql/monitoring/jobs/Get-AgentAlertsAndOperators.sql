/*
Script Name : Get-AgentAlertsAndOperators
Category    : monitoring
Purpose     : SQL Agent alerts and operators with severity gap analysis, plus the notification
              path itself: Database Mail on, a profile present, operators with email addresses,
              recent send failures. Surfaces instances where no alerts exist for severity 19-25
              (critical errors go unnoticed) and where alerts exist but mail cannot be sent.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-agent-alerts-and-operators/)
Requires    : VIEW SERVER STATE, SELECT on msdb
Notes       : SQL Server Agent's own "Enable mail profile" setting (Agent Properties > Alert
              System) is registry-backed and not readable from T-SQL; if everything below is
              OK and mail still does not arrive, check that box in SSMS and restart Agent.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- Severity coverage: which of 17–25 have at least one enabled alert?
WITH severity_alerts AS (
    SELECT DISTINCT severity
    FROM msdb.dbo.sysalerts
    WHERE enabled = 1
      AND severity BETWEEN 17 AND 25
),
severity_spine AS (
    SELECT 17 AS sev UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL
    SELECT 20 UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL
    SELECT 23 UNION ALL SELECT 24 UNION ALL SELECT 25
),
operators AS (
    SELECT COUNT(*) AS operator_count FROM msdb.dbo.sysoperators WHERE enabled = 1
)
SELECT * FROM (
    SELECT
        'severity_gap_check' AS result_type,
        sp.sev AS severity,
        CASE WHEN sa.severity IS NOT NULL THEN 'COVERED' ELSE 'NO ALERT' END AS coverage,
        CASE sp.sev
            WHEN 17 THEN 'Insufficient resources'
            WHEN 18 THEN 'Non-fatal internal error'
            WHEN 19 THEN 'Fatal resource error'
            WHEN 20 THEN 'Fatal error in current process'
            WHEN 21 THEN 'Fatal error in database processes'
            WHEN 22 THEN 'Fatal error: table integrity suspect'
            WHEN 23 THEN 'Fatal error: database integrity suspect'
            WHEN 24 THEN 'Fatal error: hardware error'
            WHEN 25 THEN 'Fatal error'
            ELSE ''
        END AS description,
        (SELECT operator_count FROM operators) AS enabled_operators,
        CASE WHEN sa.severity IS NULL AND sp.sev >= 19
             THEN 'CRITICAL - severity ' + CAST(sp.sev AS VARCHAR) + ' errors will not trigger an alert'
             WHEN sa.severity IS NULL
             THEN 'WARN - no alert for severity ' + CAST(sp.sev AS VARCHAR)
             ELSE 'OK'
        END AS status
    FROM severity_spine sp
    LEFT JOIN severity_alerts sa ON sa.severity = sp.sev

    UNION ALL

    -- All configured alerts (severity + error-number based)
    SELECT
        'configured_alert' AS result_type,
        a.severity AS severity,
        CASE a.enabled WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END AS coverage,
        a.name AS description,
        (SELECT COUNT(*) FROM msdb.dbo.sysnotifications n
         JOIN msdb.dbo.sysoperators op ON op.id = n.operator_id AND op.enabled = 1
         WHERE n.alert_id = a.id) AS enabled_operators,
        CASE
            WHEN a.enabled = 0
                THEN 'INFO - alert is disabled'
            WHEN NOT EXISTS (SELECT 1 FROM msdb.dbo.sysnotifications n
                             JOIN msdb.dbo.sysoperators op ON op.id = n.operator_id AND op.enabled = 1
                             WHERE n.alert_id = a.id)
                THEN 'WARN - no enabled operator assigned; alert fires but nobody is notified'
            ELSE 'OK'
        END AS status
    FROM msdb.dbo.sysalerts AS a

    UNION ALL

    -- Notification path: alerts and operators only matter if Database Mail can actually send.
    -- (Agent's registry-backed "Enable mail profile" flag cannot be read from T-SQL - see Notes.)
    SELECT
        'mail_system_check' AS result_type,
        NULL AS severity,
        CASE WHEN c.mail_xps = 1 THEN 'ENABLED' ELSE 'DISABLED' END AS coverage,
        'Database Mail XPs (server configuration)' AS description,
        (SELECT operator_count FROM operators) AS enabled_operators,
        CASE WHEN c.mail_xps = 1 THEN 'OK'
             ELSE 'CRITICAL - Database Mail is off; no alert on this instance can send email'
        END AS status
    FROM (SELECT CAST(value_in_use AS INT) AS mail_xps
          FROM sys.configurations WHERE name = 'Database Mail XPs') AS c

    UNION ALL

    SELECT
        'mail_system_check',
        NULL,
        CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile) THEN 'CONFIGURED' ELSE 'MISSING' END,
        'Database Mail profile exists',
        (SELECT operator_count FROM operators),
        CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile) THEN 'OK'
             ELSE 'CRITICAL - no mail profile exists; notifications have no way out'
        END

    UNION ALL

    SELECT
        'mail_system_check',
        NULL,
        CAST((SELECT COUNT(*) FROM msdb.dbo.sysoperators
              WHERE enabled = 1 AND (email_address IS NULL OR email_address = '')) AS VARCHAR(10)) + ' MISSING',
        'Enabled operators with no email address',
        (SELECT operator_count FROM operators),
        CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysoperators
                          WHERE enabled = 1 AND (email_address IS NULL OR email_address = ''))
             THEN 'WARN - operator(s) that can never receive an email notification'
             ELSE 'OK'
        END

    UNION ALL

    SELECT
        'mail_system_check',
        NULL,
        CAST((SELECT COUNT(*) FROM msdb.dbo.sysmail_faileditems
              WHERE send_request_date > DATEADD(DAY, -7, GETDATE())) AS VARCHAR(10)) + ' FAILED',
        'Database Mail failed items, last 7 days',
        (SELECT operator_count FROM operators),
        CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysmail_faileditems
                          WHERE send_request_date > DATEADD(DAY, -7, GETDATE()))
             THEN 'WARN - recent send failures; check msdb.dbo.sysmail_event_log'
             ELSE 'OK'
        END
) results

ORDER BY
    CASE result_type
        WHEN 'severity_gap_check' THEN 1
        WHEN 'configured_alert' THEN 2
        ELSE 3
    END,
    severity,
    result_type;
