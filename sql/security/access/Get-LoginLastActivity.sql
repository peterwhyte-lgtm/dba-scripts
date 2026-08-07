/*
Script Name : Get-LoginLastActivity
Category    : monitoring
Purpose     : All SQL and Windows logins with current session status, connection details, and disabled/locked state.
              Note: SQL Server does not record "last login time" natively without a SQL Server Audit configured.
              This script shows what is available: current active sessions and login metadata.
              For historical last-login tracking, enable a Server Audit with LOGIN action group.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-security-audit/)
Requires    : VIEW SERVER STATE, VIEW ANY DEFINITION
*/
-- Blog: https://sqldba.blog/dba-scripts-get-login-security-audit/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    sp.name AS login_name,
    sp.type_desc AS login_type,
    sp.is_disabled,
    sp.create_date,
    sp.modify_date,
    /* Current session info — NULL when not connected right now */
    COUNT(s.session_id) AS active_sessions,
    MIN(s.login_time) AS earliest_current_session,
    MAX(s.login_time) AS latest_current_session,
    /* Connection detail (most recent active session) */
    MAX(c.client_net_address) AS last_client_ip,
    MAX(s.host_name) AS last_host_name,
    MAX(s.program_name) AS last_program_name,
    MAX(c.auth_scheme) AS auth_scheme,
    /* Permission summary */
    IS_SRVROLEMEMBER('sysadmin', sp.name) AS is_sysadmin,
    IS_SRVROLEMEMBER('securityadmin', sp.name) AS is_securityadmin
FROM sys.server_principals sp
LEFT JOIN sys.dm_exec_sessions s ON s.login_name = sp.name AND s.is_user_process = 1
LEFT JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
WHERE sp.type IN ('S', 'U', 'G') /* SQL login, Windows user, Windows group */
  AND sp.name NOT LIKE '##%' /* exclude internal system logins */
GROUP BY sp.name, sp.type_desc, sp.is_disabled, sp.create_date, sp.modify_date
ORDER BY active_sessions DESC, sp.is_disabled, sp.name;
