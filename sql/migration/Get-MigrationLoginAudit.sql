/*
Script Name : Get-MigrationLoginAudit
Category    : migration
Purpose     : Audits all server-level principals that need to be migrated — SQL logins, Windows logins, and server roles — with migration risk and action per login type.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    sp.name                         AS login_name,
    sp.type_desc                    AS login_type,
    sp.default_database_name,
    sp.is_disabled,
    sl.is_policy_checked,
    sl.is_expiration_checked,
    CASE
        WHEN sp.name = 'sa'              THEN 'HIGH   — document or reset sa password; confirm enabled state is intentional'
        WHEN sp.type = 'S'
             AND sp.is_disabled = 0      THEN 'MEDIUM — active SQL login; script with SID preserved using Generate-LoginScript.ps1'
        WHEN sp.type = 'S'
             AND sp.is_disabled = 1      THEN 'LOW    — disabled SQL login; migrate or exclude intentionally'
        WHEN sp.type IN ('U', 'G')       THEN 'LOW    — Windows auth; no password migration needed'
        WHEN sp.type = 'C'               THEN 'HIGH   — certificate-backed login; script cert and login together'
        ELSE                                  'INFO'
    END                             AS migration_risk,
    CASE sp.type
        WHEN 'S' THEN 'Script with SID: Generate-LoginScript.ps1 — review output before running on target'
        WHEN 'U' THEN 'Windows user — verify AD account is accessible from target server domain/trust'
        WHEN 'G' THEN 'Windows group — verify group is accessible from target server domain/trust'
        WHEN 'C' THEN 'Certificate-backed — export certificate from master and recreate on target first'
        WHEN 'R' THEN 'Server role — verify role definition exists on target (custom roles only)'
        ELSE          'Review manually'
    END                             AS migration_action
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sl.principal_id = sp.principal_id
WHERE sp.type IN ('S', 'U', 'G', 'C', 'R')
  AND sp.name NOT LIKE '##%'
  AND sp.name NOT LIKE 'NT AUTHORITY\%'
  AND sp.name NOT LIKE 'NT SERVICE\%'
  AND sp.name NOT LIKE 'BUILTIN\%'
ORDER BY
    CASE sp.type WHEN 'S' THEN 1 WHEN 'U' THEN 2 WHEN 'G' THEN 3 ELSE 4 END,
    sp.is_disabled,
    sp.name;
