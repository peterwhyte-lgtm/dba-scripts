/*
Script Name : Generate-UserMappingScript
Category    : migration
Purpose     : Generate CREATE USER and role membership DDL for all user databases.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-migration-scripts/)
Requires    : VIEW ANY DATABASE, VIEW DEFINITION on each database
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @ddl    NVARCHAR(MAX) = N'';
DECLARE @crlf   NCHAR(2)     = CHAR(13) + CHAR(10);
DECLARE @dbname NVARCHAR(128);
DECLARE @chunk  NVARCHAR(MAX);
DECLARE @owner  NVARCHAR(128);
DECLARE @q      NVARCHAR(MAX);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Database User and Role Mapping Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- Run on TARGET server AFTER databases are restored and logins are created.' + @crlf
    + N'-- Order per database:' + @crlf
    + N'--   1. ALTER AUTHORIZATION (re-map dbo / database owner)' + @crlf
    + N'--   2. CREATE ROLE         (custom roles only)' + @crlf
    + N'--   3. CREATE USER         (skips dbo, guest, built-ins)' + @crlf
    + N'--   4. ALTER ROLE ADD MEMBER' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = N'ONLINE'
      AND is_read_only = 0
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @chunk = N'';
    SET @owner = NULL;

    -- ── 1. Database owner (ALTER AUTHORIZATION) ───────────────────────────────
    -- sys.databases is server-scoped so no dynamic SQL needed
    SELECT @owner = SUSER_SNAME(owner_sid)
    FROM sys.databases
    WHERE name = @dbname;

    IF @owner IS NOT NULL
        SET @chunk = @chunk
            + N'-- Database owner' + @crlf
            + N'IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N''' + REPLACE(@owner, N'''', N'''''') + N''')' + @crlf
            + N'    ALTER AUTHORIZATION ON DATABASE::[' + @dbname + N'] TO [' + REPLACE(@owner, N']', N']]') + N'];' + @crlf
            + N'GO' + @crlf + @crlf;

    -- ── 2. Custom database roles ───────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#roles') IS NOT NULL DROP TABLE #roles;
    CREATE TABLE #roles (rname NVARCHAR(128));
    SET @q = N'SELECT name FROM [' + @dbname + N'].sys.database_principals
               WHERE type = ''R'' AND is_fixed_role = 0 AND name <> N''public''
               ORDER BY name';
    INSERT INTO #roles EXEC sp_executesql @q;

    SELECT @chunk = @chunk
        + N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(rname, N'''', N'''''') + N''' AND type = ''R'')' + @crlf
        + N'    CREATE ROLE [' + rname + N'];' + @crlf
        + N'GO' + @crlf + @crlf
    FROM #roles
    ORDER BY rname;

    DROP TABLE #roles;

    -- ── 3. Database users ─────────────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#users') IS NOT NULL DROP TABLE #users;
    CREATE TABLE #users (uname NVARCHAR(128), utype CHAR(1), auth_type NVARCHAR(60), usid VARBINARY(85));
    SET @q = N'SELECT name, type, authentication_type_desc, sid
               FROM [' + @dbname + N'].sys.database_principals
               WHERE type IN (''S'', ''U'', ''G'')
                 AND name NOT IN (N''dbo'', N''guest'', N''INFORMATION_SCHEMA'', N''sys'', N''public'')
                 AND name NOT LIKE N''##%##''
               ORDER BY name';
    INSERT INTO #users EXEC sp_executesql @q;

    SELECT @chunk = @chunk
        + CASE
            WHEN utype IN ('U', 'G')
                THEN N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(uname, N'''', N'''''') + N''')' + @crlf
                   + N'    CREATE USER [' + uname + N'] FOR LOGIN [' + uname + N']' + @crlf
            WHEN utype = 'S'
                 AND usid IS NOT NULL
                 AND EXISTS (SELECT 1 FROM sys.server_principals sp WHERE sp.sid = usid)
                THEN N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(uname, N'''', N'''''') + N''')' + @crlf
                   + N'    CREATE USER [' + uname + N'] FOR LOGIN [' + ISNULL(SUSER_SNAME(usid), uname) + N']' + @crlf
            WHEN utype = 'S' AND auth_type = 'DATABASE'
                THEN N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(uname, N'''', N'''''') + N''')' + @crlf
                   + N'    CREATE USER [' + uname + N'] WITHOUT LOGIN' + @crlf
            ELSE N'-- SKIP (no matching server login): ' + uname + @crlf
          END
        + N'GO' + @crlf + @crlf
    FROM #users
    ORDER BY uname;

    DROP TABLE #users;

    -- ── 4. Role memberships ────────────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#rolemem') IS NOT NULL DROP TABLE #rolemem;
    CREATE TABLE #rolemem (rname NVARCHAR(128), mname NVARCHAR(128));
    SET @q = N'SELECT r.name, m.name
               FROM [' + @dbname + N'].sys.database_role_members drm
               JOIN [' + @dbname + N'].sys.database_principals r ON drm.role_principal_id   = r.principal_id
               JOIN [' + @dbname + N'].sys.database_principals m ON drm.member_principal_id  = m.principal_id
               WHERE r.name <> N''public''
                 AND m.name NOT IN (N''dbo'', N''guest'', N''INFORMATION_SCHEMA'', N''sys'', N''public'')
                 AND m.name NOT LIKE N''##%##''
               ORDER BY r.name, m.name';
    INSERT INTO #rolemem EXEC sp_executesql @q;

    SELECT @chunk = @chunk
        + N'IF EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(mname, N'''', N'''''') + N''')' + @crlf
        + N'    ALTER ROLE [' + rname + N'] ADD MEMBER [' + mname + N'];' + @crlf
        + N'GO' + @crlf + @crlf
    FROM #rolemem
    ORDER BY rname, mname;

    DROP TABLE #rolemem;

    -- ── Append to output if non-empty ──────────────────────────────────────────
    IF @chunk IS NOT NULL AND @chunk <> N''
    BEGIN
        SET @ddl = @ddl
            + N'-- ----------------------------------------------------------------' + @crlf
            + N'-- Database: [' + @dbname + N']' + @crlf
            + N'-- ----------------------------------------------------------------' + @crlf
            + N'USE [' + @dbname + N'];' + @crlf
            + N'GO' + @crlf + @crlf
            + @chunk;
    END

    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT @ddl AS ddl;
