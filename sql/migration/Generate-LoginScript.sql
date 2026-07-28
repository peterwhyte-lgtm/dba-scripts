/*
Script Name : Generate-LoginScript
Category    : migration
Purpose     : Generate CREATE LOGIN DDL for all non-system logins with SIDs and hashed passwords preserved.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-migration-scripts/)
Requires    : VIEW SERVER STATE, CONTROL SERVER (for password_hash column)
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @ddl  NVARCHAR(MAX) = N'';
DECLARE @crlf NCHAR(2)      = CHAR(13) + CHAR(10);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Login Migration Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Run on TARGET server AFTER databases are restored.' + @crlf
    + N'-- SQL logins include hashed passwords and original SIDs to avoid' + @crlf
    + N'-- orphaned users after restore.' + @crlf
    + N'-- NOTE: If a login''s DEFAULT_DATABASE does not exist on the target,' + @crlf
    + N'-- the login will fail to connect. Fix with:' + @crlf
    + N'--   ALTER LOGIN [name] WITH DEFAULT_DATABASE = [master]' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

-- ── SQL logins ────────────────────────────────────────────────────────────────

SET @ddl = @ddl + N'-- SQL Logins' + @crlf + N'GO' + @crlf + @crlf;

SELECT @ddl = @ddl
    + N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(p.name, N'''', N'''''') + N''')' + @crlf
    + N'BEGIN' + @crlf
    + N'    CREATE LOGIN [' + p.name + N']' + @crlf
    + N'        WITH PASSWORD = ' + CONVERT(NVARCHAR(MAX), sl.password_hash, 1) + N' HASHED,' + @crlf
    + N'             SID      = ' + CONVERT(NVARCHAR(MAX), p.sid, 1) + N',' + @crlf
    + N'             DEFAULT_DATABASE = [' + ISNULL(p.default_database_name, N'master') + N'],' + @crlf
    + N'             CHECK_POLICY     = ' + CASE sl.is_policy_checked     WHEN 1 THEN N'ON' ELSE N'OFF' END + N',' + @crlf
    + N'             CHECK_EXPIRATION = ' + CASE sl.is_expiration_checked WHEN 1 THEN N'ON' ELSE N'OFF' END + @crlf
    + N'END' + @crlf
    + N'GO' + @crlf + @crlf
FROM sys.server_principals p
INNER JOIN sys.sql_logins sl ON p.principal_id = sl.principal_id
WHERE p.type = 'S'
  AND p.name NOT LIKE N'##%##'
  AND p.name NOT IN (N'sa', N'guest', N'public')
ORDER BY p.name;

-- ── Windows logins and groups ─────────────────────────────────────────────────

SET @ddl = @ddl + N'-- Windows Logins and Groups' + @crlf + N'GO' + @crlf + @crlf;

SELECT @ddl = @ddl
    + N'IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(p.name, N'''', N'''''') + N''')' + @crlf
    + N'BEGIN' + @crlf
    + N'    CREATE LOGIN [' + p.name + N'] FROM WINDOWS' + @crlf
    + N'        WITH DEFAULT_DATABASE = [' + ISNULL(p.default_database_name, N'master') + N']' + @crlf
    + N'END' + @crlf
    + N'GO' + @crlf + @crlf
FROM sys.server_principals p
WHERE p.type IN ('W', 'G')
  AND p.name NOT LIKE N'##%##'
  AND p.name NOT IN (N'sa', N'guest', N'public')
  AND p.name NOT LIKE N'NT SERVICE\%'
  AND p.name NOT LIKE N'NT AUTHORITY\%'
  AND p.name NOT LIKE N'BUILTIN\%'
ORDER BY p.name;

-- ── Server role memberships ───────────────────────────────────────────────────

SET @ddl = @ddl + N'-- Server Role Memberships' + @crlf + N'GO' + @crlf + @crlf;

SELECT @ddl = @ddl
    + N'IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(m.name, N'''', N'''''') + N''')' + @crlf
    + N'    ALTER SERVER ROLE [' + r.name + N'] ADD MEMBER [' + m.name + N'];' + @crlf
    + N'GO' + @crlf + @crlf
FROM sys.server_role_members srm
INNER JOIN sys.server_principals r ON srm.role_principal_id  = r.principal_id
INNER JOIN sys.server_principals m ON srm.member_principal_id = m.principal_id
WHERE r.name <> N'public'
  AND m.name NOT LIKE N'##%##'
  AND m.name NOT IN (N'sa')
  AND m.name NOT LIKE N'NT SERVICE\%'
  AND m.name NOT LIKE N'NT AUTHORITY\%'
ORDER BY r.name, m.name;

SELECT @ddl AS ddl;
