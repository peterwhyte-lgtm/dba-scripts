/*
Script Name : Get-DdlTriggers
Category    : security
Purpose     : Server-level DDL triggers. These fire on schema changes (CREATE/ALTER/DROP)
              and are often unknown to incoming DBAs. Can block DDL, audit changes, or
              enforce naming conventions — a hidden dependency on inherited servers.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/)
Requires    : VIEW ANY DEFINITION
*/
-- Blog: https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT
    t.name                                          AS trigger_name,
    t.type_desc,
    t.is_disabled,
    t.create_date,
    t.modify_date,
    STUFF((
        SELECT ', ' + e.type_desc
        FROM   sys.server_trigger_events AS e
        WHERE  e.object_id = t.object_id
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(500)'), 1, 2, '')        AS event_types,
    sp.name                                         AS execute_as_principal,
    m.definition                                    AS trigger_definition,
    CASE
        WHEN t.is_disabled = 1
            THEN 'INFO — trigger is disabled'
        WHEN m.definition LIKE '%ROLLBACK%'
            THEN 'WARN — trigger may ROLLBACK transactions; could block DDL operations'
        ELSE 'OK — review to confirm purpose and owner'
    END                                             AS status
FROM sys.server_triggers          AS t
JOIN sys.server_sql_modules       AS m  ON m.object_id = t.object_id
LEFT JOIN sys.server_principals   AS sp ON sp.principal_id = m.execute_as_principal_id
ORDER BY t.name;
