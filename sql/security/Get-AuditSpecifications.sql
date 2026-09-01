/*
Script Name : Get-AuditSpecifications
Category    : security
Purpose     : SQL Server Audit objects and specifications with compliance gap analysis.
              SQL Audit (the formal mechanism for SOX, GDPR, PCI-DSS) is completely
              separate from login monitoring. Most inherited servers have none configured.
              Surfaces missing critical action groups (FAILED_LOGIN_GROUP, privilege changes)
              and database-level audit specifications across all user databases.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-audit-triggers-and-proxy-credentials/)
Requires    : VIEW ANY DATABASE, VIEW ANY DEFINITION, CONTROL SERVER
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #audit_info (
    result_type NVARCHAR(30),
    audit_name NVARCHAR(128),
    specification_name NVARCHAR(128),
    database_name NVARCHAR(128), -- NVARCHAR not SYSNAME; SYSNAME is NOT NULL
    action_group NVARCHAR(256),
    audit_type NVARCHAR(60),
    audit_state NVARCHAR(20),
    on_failure NVARCHAR(30),
    status NVARCHAR(400)
);

-- Server-level audit objects
INSERT INTO #audit_info
SELECT
    'SERVER_AUDIT' AS result_type,
    a.name AS audit_name,
    NULL AS specification_name,
    NULL AS database_name,
    NULL AS action_group,
    a.type_desc AS audit_type,
    CASE a.is_state_enabled WHEN 1 THEN 'STARTED' ELSE 'STOPPED' END AS audit_state,
    a.on_failure_desc AS on_failure,
    CASE
        WHEN a.is_state_enabled = 0
            THEN 'WARN - audit exists but is not running'
        WHEN a.on_failure_desc = 'CONTINUE'
            THEN 'INFO - on_failure = CONTINUE; audit records can be lost silently on I/O error'
        ELSE 'OK'
    END AS status
FROM sys.server_audits AS a;

-- Server audit specification detail
INSERT INTO #audit_info
SELECT
    'SERVER_SPEC' AS result_type,
    a.name AS audit_name,
    s.name AS specification_name,
    NULL,
    d.audit_action_name AS action_group,
    NULL,
    CASE s.is_state_enabled WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END,
    NULL,
    CASE WHEN s.is_state_enabled = 0
         THEN 'WARN - specification is disabled'
         ELSE 'OK'
    END
FROM sys.server_audit_specifications AS s
JOIN sys.server_audits AS a ON a.audit_guid = s.audit_guid
JOIN sys.server_audit_specification_details AS d ON d.server_specification_id = s.server_specification_id;

-- Gap analysis: critical server-level action groups
DECLARE @covered_groups TABLE (action_group NVARCHAR(256));
INSERT INTO @covered_groups
SELECT DISTINCT d.audit_action_name
FROM sys.server_audit_specification_details AS d
JOIN sys.server_audit_specifications AS s ON s.server_specification_id = d.server_specification_id
WHERE s.is_state_enabled = 1;

INSERT INTO #audit_info (result_type, action_group, status)
SELECT
    'GAP_CHECK',
    critical_group,
    CASE WHEN EXISTS (SELECT 1 FROM @covered_groups WHERE action_group = critical_group)
         THEN 'OK - covered by an enabled specification'
         ELSE gap_severity + ' - ' + critical_group + ' is not audited; ' + why_it_matters
    END
FROM (VALUES
    ('FAILED_LOGIN_GROUP', 'CRITICAL', 'brute-force attacks and failed access go undetected'),
    ('SERVER_ROLE_MEMBER_CHANGE_GROUP', 'CRITICAL', 'privilege escalation (adding sysadmin) is not recorded'),
    ('DATABASE_ROLE_MEMBER_CHANGE_GROUP', 'HIGH', 'db_owner grants and role membership changes unrecorded'),
    ('SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP','HIGH', 'GRANT/REVOKE/DENY on objects not captured'),
    ('SUCCESSFUL_LOGIN_GROUP', 'MEDIUM', 'no record of who connected and when'),
    ('SERVER_OBJECT_CHANGE_GROUP', 'MEDIUM', 'CREATE/ALTER/DROP SERVER OBJECT events not captured')
) AS gaps(critical_group, gap_severity, why_it_matters);

-- Database-level audit specifications (cross-database)
DECLARE @db SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    INSERT INTO #audit_info
    SELECT
        ''DB_SPEC'',
        a.name,
        s.name,
        N' + QUOTENAME(@db, N'''') + N',
        d.audit_action_name,
        NULL,
        CASE s.is_state_enabled WHEN 1 THEN ''ENABLED'' ELSE ''DISABLED'' END,
        NULL,
        CASE WHEN s.is_state_enabled = 0 THEN ''WARN - specification disabled''
             ELSE ''OK'' END
    FROM ' + QUOTENAME(@db) + N'.sys.database_audit_specifications s
    JOIN sys.server_audits a
        ON a.audit_guid = s.audit_guid
    JOIN ' + QUOTENAME(@db) + N'.sys.database_audit_specification_details d
        ON d.database_specification_id = s.database_specification_id;';

    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

IF NOT EXISTS (SELECT 1 FROM sys.server_audits)
BEGIN
    INSERT INTO #audit_info (result_type, status)
    VALUES ('GAP_CHECK',
            'CRITICAL - No SQL Server Audit objects configured on this instance. ' +
            'Login monitoring and sp_configure checks are not a substitute for SQL Audit. ' +
            'Create a server audit with FAILED_LOGIN_GROUP and SERVER_ROLE_MEMBER_CHANGE_GROUP at minimum.');
END;

SELECT
    result_type, audit_name, specification_name, database_name,
    action_group, audit_type, audit_state, on_failure, status
FROM #audit_info
ORDER BY
    CASE result_type WHEN 'GAP_CHECK' THEN 1
                     WHEN 'SERVER_AUDIT' THEN 2
                     WHEN 'SERVER_SPEC' THEN 3
                     WHEN 'DB_SPEC' THEN 4
                     ELSE 5 END,
    CASE WHEN status LIKE 'CRITICAL%' THEN 1
         WHEN status LIKE 'HIGH%' THEN 2
         WHEN status LIKE 'WARN%' THEN 3
         ELSE 4 END,
    audit_name, database_name, action_group;

DROP TABLE #audit_info;
