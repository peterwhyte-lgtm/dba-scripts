/*
Script Name : Get-WeakLoginSettings
Category    : security-and-permissions
Purpose     : Identify SQL logins with weak security settings: policy off, expiration off, or sa enabled.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, sysadmin to see LOGINPROPERTY details
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    sl.name                                                     AS login_name,
    sl.is_disabled,
    sl.is_policy_checked,
    sl.is_expiration_checked,
    CAST(LOGINPROPERTY(sl.name, 'PasswordLastSetTime') AS DATETIME) AS password_last_set,
    CAST(LOGINPROPERTY(sl.name, 'IsLocked')           AS BIT)      AS is_locked,
    CAST(LOGINPROPERTY(sl.name, 'IsMustChange')       AS BIT)      AS must_change_password,
    sl.default_database_name,
    sl.create_date,
    sl.modify_date,
    CASE
        WHEN sl.name = 'sa' AND sl.is_disabled = 0 THEN 'SA_ENABLED'
        WHEN sl.is_policy_checked    = 0           THEN 'PASSWORD_POLICY_OFF'
        WHEN sl.is_expiration_checked = 0          THEN 'EXPIRATION_OFF'
        ELSE 'OK'
    END                                                         AS risk_flag
FROM sys.sql_logins AS sl
WHERE sl.name NOT LIKE '##%'
ORDER BY
    CASE
        WHEN sl.name = 'sa' AND sl.is_disabled = 0 THEN 0
        WHEN sl.is_policy_checked    = 0           THEN 1
        WHEN sl.is_expiration_checked = 0          THEN 2
        ELSE 3
    END,
    sl.name;
