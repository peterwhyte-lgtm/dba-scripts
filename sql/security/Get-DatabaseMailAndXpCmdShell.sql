/*
Script Name : Get-DatabaseMailAndXpCmdShell
Category    : security
Purpose     : Security surface area audit — xp_cmdshell, CLR, Database Mail, force encryption, and active NTLM connections.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE, sysadmin (for xp_cmdshell value_in_use and registry access)
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    name,
    CAST(value        AS VARCHAR(20)) AS configured_value,
    CAST(value_in_use AS VARCHAR(20)) AS running_value,
    description
FROM sys.configurations
WHERE name IN (
    'xp_cmdshell',
    'clr enabled',
    'clr strict security',
    'Database Mail XPs'
)

UNION ALL

-- Force encryption: 1 = all connections must encrypt; 0 = encryption optional
SELECT
    'force encryption'                                                              AS name,
    '0'                                                                             AS configured_value,
    ISNULL(
        (SELECT TOP 1 CAST(value_data AS VARCHAR(20))
         FROM   sys.dm_server_registry
         WHERE  registry_key LIKE N'%SuperSocketNetLib%'
         AND    value_name   = N'ForceEncryption'),
        '0'
    )                                                                               AS running_value,
    'ForceEncryption - 1 = all connections must encrypt; 0 = unencrypted allowed'  AS description

UNION ALL

-- Active user sessions authenticated via NTLM (Kerberos is preferred for Windows auth)
SELECT
    'ntlm connections'                                                              AS name,
    '0'                                                                             AS configured_value,
    CAST(
        (SELECT COUNT(*)
         FROM   sys.dm_exec_sessions    AS s
         JOIN   sys.dm_exec_connections AS c ON c.session_id = s.session_id
         WHERE  c.auth_scheme     = 'NTLM'
         AND    s.is_user_process = 1)
    AS VARCHAR(20))                                                                 AS running_value,
    'Active user sessions using NTLM authentication (Kerberos preferred)'           AS description

ORDER BY name;





