/*
Script Name : Get-FailedLoginSummary
Category    : security
Purpose     : Aggregated failed login analysis from the SQL Server error log and current
              lockout state per SQL login. Surfaces brute-force patterns and locked accounts.
              Complements Get-WeakLoginSettings (which checks policy configuration) — this
              checks what is actually happening.
              Note: SQL Server 2025 does not write 18456 events to RING_BUFFER_SECURITY_ERROR;
              xp_readerrorlog is the reliable cross-version source for login failures.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-security-audit/)
Requires    : VIEW SERVER STATE, sysadmin (for LOGINPROPERTY on other logins), EXECUTE on xp_readerrorlog
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- INSERT...EXEC cannot be used inside a CTE so materialise to a temp table first
CREATE TABLE #failed_logins (
    log_date DATETIME,
    process_info NVARCHAR(100),
    log_text NVARCHAR(MAX)
);

-- Filter to current error log (log# 0), type 1 (SQL Server log), login failure messages only
INSERT INTO #failed_logins
EXEC xp_readerrorlog 0, 1, N'Login failed';

WITH parsed AS (
    SELECT
        -- Login name sits between the first pair of single quotes
        SUBSTRING(
            log_text,
            CHARINDEX('''', log_text) + 1,
            CHARINDEX('''', log_text, CHARINDEX('''', log_text) + 1) - CHARINDEX('''', log_text) - 1
        ) AS login_name,
        -- Client IP/host is in the trailing [CLIENT: ...] tag
        CASE
            WHEN CHARINDEX('[CLIENT: ', log_text) > 0
            THEN SUBSTRING(
                log_text,
                CHARINDEX('[CLIENT: ', log_text) + 9,
                CHARINDEX(']', log_text, CHARINDEX('[CLIENT: ', log_text))
                    - CHARINDEX('[CLIENT: ', log_text) - 9
            )
            ELSE NULL
        END AS client_host,
        -- Map reason text to the canonical error code
        CASE
            WHEN log_text LIKE '%untrusted domain%' THEN 18452
            WHEN log_text LIKE '%only administrators%' THEN 18451
            WHEN log_text LIKE '%account is disabled%' THEN 18470
            WHEN log_text LIKE '%password must be changed%' THEN 18488
            WHEN log_text LIKE '%password did not match%' THEN 18456
            WHEN log_text LIKE '%could not find a login%' THEN 18456
            ELSE 18456
        END AS error_code,
        log_date
    FROM #failed_logins
),
aggregated AS (
    SELECT
        login_name,
        client_host,
        error_code,
        COUNT(*) AS failure_count,
        MIN(log_date) AS first_failure,
        MAX(log_date) AS last_failure
    FROM parsed
    GROUP BY login_name, client_host, error_code
)
SELECT
    agg.login_name,
    agg.client_host,
    agg.error_code,
    CASE agg.error_code
        WHEN 18456 THEN 'Login failed (bad password or login does not exist)'
        WHEN 18452 THEN 'Login from untrusted domain or cannot use Windows auth'
        WHEN 18451 THEN 'Login failed — only admin connections are allowed'
        WHEN 18470 THEN 'Account is disabled'
        WHEN 18488 THEN 'Password must be changed'
        WHEN 4818 THEN 'Password does not meet complexity requirements'
        ELSE 'Error ' + CAST(agg.error_code AS VARCHAR(10))
    END AS error_description,
    agg.failure_count,
    agg.first_failure AS first_failure_approx,
    agg.last_failure AS last_failure_approx,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'IsLocked') AS BIT)
        ELSE NULL
    END AS is_currently_locked,
    CASE
        WHEN sl.name IS NOT NULL
        THEN CAST(LOGINPROPERTY(sl.name, 'BadPasswordCount') AS INT)
        ELSE NULL
    END AS bad_password_count,
    CASE
        WHEN agg.failure_count >= 50
        THEN 'CRITICAL — ' + CAST(agg.failure_count AS VARCHAR) +
             ' failures in error log; likely brute-force or application misconfiguration'
        WHEN agg.failure_count >= 10
        THEN 'WARN — repeated failures for login [' + ISNULL(agg.login_name, '(unknown)') + ']'
        ELSE 'INFO'
    END AS status
FROM aggregated AS agg
LEFT JOIN sys.sql_logins AS sl ON sl.name = agg.login_name
ORDER BY agg.failure_count DESC;

DROP TABLE #failed_logins;
