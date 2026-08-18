/*
Script Name : Generate-UserMappingScript
Category    : migration
Purpose     : Generate CREATE USER and role membership DDL for all user databases.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-user-mapping-script/)
Requires    : VIEW ANY DATABASE, VIEW DEFINITION on each database
Notes       : Where a user cannot be scripted faithfully the script emits a commented
              MANUAL block instead of a working-looking statement. Two cases:
              contained users with their own password (the password is not readable, so
              a real CREATE USER would silently drop authentication), and users whose
              login cannot be resolved by SID on the source. Search the output for
              "MANUAL" before running it.
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
            + N'    ALTER AUTHORIZATION ON DATABASE::' + QUOTENAME(@dbname) + N' TO ' + QUOTENAME(@owner) + N';' + @crlf
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
        + N'    CREATE ROLE ' + QUOTENAME(rname) + N';' + @crlf
        + N'GO' + @crlf + @crlf
    FROM #roles
    ORDER BY rname;

    DROP TABLE #roles;

    -- ── 3. Database users ─────────────────────────────────────────────────────
    IF OBJECT_ID('tempdb..#users') IS NOT NULL DROP TABLE #users;
    CREATE TABLE #users (uname NVARCHAR(128), utype CHAR(1), auth_type NVARCHAR(60), usid VARBINARY(85), login_name NVARCHAR(128) NULL);
    SET @q = N'SELECT name, type, authentication_type_desc, sid
               FROM [' + @dbname + N'].sys.database_principals
               WHERE type IN (''S'', ''U'', ''G'')
                 AND name NOT IN (N''dbo'', N''guest'', N''INFORMATION_SCHEMA'', N''sys'', N''public'')
                 AND name NOT LIKE N''##%##''
               ORDER BY name';
    INSERT INTO #users (uname, utype, auth_type, usid) EXEC sp_executesql @q;

    -- Resolve each user's login from the SERVER CATALOG, by SID, once.
    -- Not SUSER_SNAME: on an unresolvable Windows SID that can go out to the
    -- domain controller and stall the whole generation.
    UPDATE u
       SET login_name = sp.name
      FROM #users u
      JOIN sys.server_principals sp ON sp.sid = u.usid;

    -- Each branch must either script the user FAITHFULLY or refuse and say so.
    -- A statement that runs but changes how the user authenticates is worse than
    -- no statement at all, because nothing fails and nobody looks again.
    SELECT @chunk = @chunk
        + CASE
            -- Contained user carrying its own password: the password is not readable,
            -- so there is no faithful CREATE USER. Do NOT emit WITHOUT LOGIN, that
            -- succeeds and silently leaves an account that can never authenticate.
            WHEN auth_type = 'DATABASE'
                THEN N'-- MANUAL: [' + uname + N'] is a contained user (authentication_type = DATABASE).' + @crlf
                   + N'-- Its password cannot be read from the source, so it is not scripted here.' + @crlf
                   + N'-- Recreate it on the target with the password from your credential store:' + @crlf
                   + N'--   CREATE USER ' + QUOTENAME(uname) + N' WITH PASSWORD = N''ENTER_PASSWORD_HERE'';' + @crlf
                   + N'-- Target database must have CONTAINMENT = PARTIAL.' + @crlf
            -- Mapped to a server login: resolve by SID, never by name. A name match
            -- to a different login on the target hands the roles to the wrong identity.
            WHEN login_name IS NOT NULL
                THEN N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(uname, N'''', N'''''') + N''')' + @crlf
                   + N'    CREATE USER ' + QUOTENAME(uname) + N' FOR LOGIN ' + QUOTENAME(login_name) + @crlf
            -- Genuinely login-less (EXECUTE AS / impersonation user). Faithful as-is.
            WHEN auth_type = 'NONE'
                THEN N'IF NOT EXISTS (SELECT 1 FROM [' + @dbname + N'].sys.database_principals WHERE name = N''' + REPLACE(uname, N'''', N'''''') + N''')' + @crlf
                   + N'    CREATE USER ' + QUOTENAME(uname) + N' WITHOUT LOGIN' + @crlf
            -- SID present but no server principal owns it: the login is already
            -- missing on the SOURCE. Scripting a guess here would invent a mapping.
            ELSE N'-- MANUAL: no server login resolves for [' + uname + N'] (SID '
                   + ISNULL(CONVERT(NVARCHAR(MAX), usid, 1), N'NULL') + N').' + @crlf
               + N'-- Create the login first, then re-run this script.' + @crlf
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
        + N'    ALTER ROLE ' + QUOTENAME(rname) + N' ADD MEMBER ' + QUOTENAME(mname) + N';' + @crlf
        + N'GO' + @crlf + @crlf
    FROM #rolemem
    ORDER BY rname, mname;

    DROP TABLE #rolemem;

    -- ── Append to output if non-empty ──────────────────────────────────────────
    IF @chunk IS NOT NULL AND @chunk <> N''
    BEGIN
        SET @ddl = @ddl
            + N'-- ----------------------------------------------------------------' + @crlf
            + N'-- Database: ' + QUOTENAME(@dbname) + @crlf
            + N'-- ----------------------------------------------------------------' + @crlf
            + N'USE ' + QUOTENAME(@dbname) + N';' + @crlf
            + N'GO' + @crlf + @crlf
            + @chunk;
    END

    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

SELECT @ddl AS ddl;
