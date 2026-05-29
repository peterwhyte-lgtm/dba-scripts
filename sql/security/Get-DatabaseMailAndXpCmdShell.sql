/*
Script Name : Get-DatabaseMailAndXpCmdShell
Category    : security-and-permissions
Purpose     : Review whether Database Mail, xp_cmdshell, and CLR are enabled for security audits.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE (sysadmin to see xp_cmdshell value_in_use)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Queries sys.configurations directly — no sp_configure RECONFIGURE needed.

SELECT
    name,
    value           AS configured_value,
    value_in_use    AS running_value,
    description
FROM sys.configurations
WHERE name IN (
    'xp_cmdshell',
    'clr enabled',
    'clr strict security',
    'Database Mail XPs'
)
ORDER BY name;





