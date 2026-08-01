/*
Script Name : Fix-OrphanedUsers
Category    : migration
Purpose     : Generate ALTER USER statements to re-map orphaned database users to their
              matching server-level logins across all user databases. Run on TARGET after
              databases are restored and logins are created.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-fix-orphaned-users/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-fix-orphaned-users/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: After restoring databases from a source server, SQL logins are re-created with the
  same SID (via Generate-LoginScript.sql WITH SID = ...). This means SQL-authenticated users
  are NOT orphaned — their SID in sys.database_principals matches the new login's SID.

  Windows-authenticated users are also fine because the AD SID never changes.

  The orphan case that CAN occur:
    - SQL logins created without SID preservation (e.g. the old login was dropped and re-created
      and the SID therefore differs from what is stored in the restored database).
    - Databases restored from an environment where logins no longer exist on the new server.

  This script generates ALTER USER ... WITH LOGIN statements for any user in any database whose
  SID does not match any login on this instance. It assumes login name = user name (common case).
  Review the output before executing — not every orphan can be fixed with a simple name match.

  To EXECUTE the output directly:
    Uncomment the EXEC sp_executesql lines below (currently commented for safety).
*/

DECLARE @ddl  nvarchar(max) = N'';
DECLARE @crlf nchar(2)      = CHAR(13) + CHAR(10);
DECLARE @sql  nvarchar(max);
DECLARE @dbname nvarchar(128);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Orphaned User Fix Script' + @crlf
    + N'-- Target  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(nvarchar(30), GETDATE(), 120) + @crlf
    + N'-- Review before executing. Each line maps a database user to a login' + @crlf
    + N'-- by name — verify the name match is correct first.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

-- Temp table to collect orphans across all databases
IF OBJECT_ID('tempdb..#orphans') IS NOT NULL DROP TABLE #orphans;
CREATE TABLE #orphans (
    database_name nvarchar(128),
    user_name     nvarchar(128),
    user_type     char(1),
    user_sid      varbinary(85)
);

-- Loop all user databases using sp_MSforeachdb alternative (cursor-based for reliability)
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4
      AND state_desc = N'ONLINE'
      AND is_read_only = 0
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        INSERT INTO #orphans (database_name, user_name, user_type, user_sid)
        SELECT
            N''' + REPLACE(@dbname, N'''', N'''''') + N''',
            dp.name,
            dp.type,
            dp.sid
        FROM [' + @dbname + N'].sys.database_principals dp
        WHERE dp.type IN (''S'', ''U'', ''G'')   -- SQL, Windows user, Windows group
          AND dp.authentication_type_desc = N''INSTANCE'' -- mapped to a server login
          AND dp.sid IS NOT NULL
          AND dp.name NOT IN (N''dbo'', N''guest'', N''sys'', N''INFORMATION_SCHEMA'')
          AND dp.name NOT LIKE N''##%''
          AND dp.sid NOT IN (
              SELECT sid FROM sys.server_principals
              WHERE type IN (''S'', ''U'', ''G'')
          );';

    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cur INTO @dbname;
END

CLOSE db_cur;
DEALLOCATE db_cur;

-- Build output
SELECT @ddl = @ddl
    + N'-- ' + o.database_name + N': ' + CAST(cnt.n AS nvarchar(10)) + N' orphan(s)' + @crlf
FROM #orphans o
INNER JOIN (SELECT database_name, COUNT(*) AS n FROM #orphans GROUP BY database_name) cnt
    ON cnt.database_name = o.database_name
GROUP BY o.database_name, cnt.n
ORDER BY o.database_name;

SET @ddl = @ddl + @crlf;

SELECT @ddl = @ddl
    + N'USE [' + o.database_name + N'];' + @crlf
    + CASE
        WHEN EXISTS (
            SELECT 1 FROM sys.server_principals sp
            WHERE sp.name = o.user_name AND sp.type IN ('S','U','G')
        )
        THEN N'ALTER USER [' + o.user_name + N'] WITH LOGIN = [' + o.user_name + N'];' + @crlf
        ELSE N'-- Cannot auto-fix: no login named [' + o.user_name + N'] found. Create the login first or map manually.' + @crlf
      END
    + N'GO' + @crlf + @crlf
FROM #orphans o
ORDER BY o.database_name, o.user_name;

IF NOT EXISTS (SELECT 1 FROM #orphans)
    SET @ddl = @ddl + N'-- No orphaned users found. All database users map to a valid server login.' + @crlf;

DROP TABLE #orphans;

SELECT @ddl AS ddl;
