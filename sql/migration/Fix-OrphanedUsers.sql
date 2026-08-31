/*
Script Name : Fix-OrphanedUsers
Category    : migration
Purpose     : Generate ALTER USER statements to re-map orphaned database users to their
              matching server-level logins across all user databases. Run on TARGET after
              databases are restored and logins are created.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-fix-orphaned-users/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE, plus access to each online database it inspects
*/
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

  This script never applies a fix. It RETURNS the ALTER USER statements as text for you to
  review and run yourself, which is why it is classed ReadOnly. There are no commented-out
  EXEC lines to uncomment: the one EXEC sp_executesql below collects the orphan list, it does
  not repair anything.
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
    + N'-- by name - verify the name match is correct first.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

-- Temp table to collect orphans across all databases
IF OBJECT_ID('tempdb..#orphans') IS NOT NULL DROP TABLE #orphans;
CREATE TABLE #orphans (
    database_name nvarchar(128),
    user_name     nvarchar(128),
    user_type     char(1),
    user_sid      varbinary(85),
    is_read_only  bit
);

IF OBJECT_ID('tempdb..#failed') IS NOT NULL DROP TABLE #failed;
CREATE TABLE #failed (
    database_name nvarchar(128),
    reason        nvarchar(2048)
);

-- READ-ONLY DATABASES ARE SCANNED, NOT SKIPPED. This filter used to be
-- `AND is_read_only = 0`, and the orphans in a read-only database then vanished from the
-- output with no warning at all: the report looked clean. Proved on the lab 2026-09-01 by
-- setting a test database READ_ONLY - three known orphans disappeared and the database was
-- not even mentioned. Read-only is common exactly where this script is used: readable AG
-- secondaries, archive copies, and databases restored for reporting during a migration.
-- Reading sys.database_principals in a read-only database works fine; only the ALTER USER
-- fix needs write access, so the orphan is reported and the generated line says what has to
-- happen first. Silently under-reporting is the worse failure: the reader cannot see it.
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE database_id > 4
      AND state_desc = N'ONLINE'
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- QUOTENAME on the database, not string concatenation into brackets: a database name
    -- containing a ] would otherwise terminate the identifier early and change what this
    -- dynamic SQL means.
    SET @sql = N'
        INSERT INTO #orphans (database_name, user_name, user_type, user_sid, is_read_only)
        SELECT
            N''' + REPLACE(@dbname, N'''', N'''''') + N''',
            dp.name,
            dp.type,
            dp.sid,
            CASE WHEN DATABASEPROPERTYEX(N''' + REPLACE(@dbname, N'''', N'''''')
              + N''', ''Updateability'') = ''READ_ONLY'' THEN 1 ELSE 0 END
        FROM ' + QUOTENAME(@dbname) + N'.sys.database_principals dp
        WHERE dp.type IN (''S'', ''U'', ''G'')   -- SQL, Windows user, Windows group
          AND dp.authentication_type_desc = N''INSTANCE'' -- mapped to a server login
          AND dp.sid IS NOT NULL
          AND dp.name NOT IN (N''dbo'', N''guest'', N''sys'', N''INFORMATION_SCHEMA'')
          AND dp.name NOT LIKE N''##%''
          -- NOT EXISTS, not NOT IN. A single NULL sid in the server_principals list makes
          -- `sid NOT IN (...)` evaluate to UNKNOWN for EVERY row, so the script would report
          -- zero orphans on a server that has them. Same shape as the sibling detector
          -- Get-OrphanedUsers, which already used NOT EXISTS.
          AND NOT EXISTS (
              SELECT 1 FROM sys.server_principals sp
              WHERE sp.sid = dp.sid AND sp.type IN (''S'', ''U'', ''G'')
          );';

    -- A FAILED SCAN MUST NOT LOOK LIKE A CLEAN ONE. Without this, any per-database failure
    -- (no CONNECT permission, the database going offline mid-loop, a broken principal) was
    -- swallowed: the INSERT simply did not happen, that database's orphans vanished, and the
    -- script still printed "No orphaned users found. All database users map to a valid server
    -- login." Demonstrated for real on 2026-09-01 - a syntax slip in this very statement made
    -- all eight databases fail and the script reported the instance CLEAN. Silence is the one
    -- answer a check like this must never give.
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #failed (database_name, reason) VALUES (@dbname, ERROR_MESSAGE());
    END CATCH;
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

-- QUOTENAME on every identifier that reaches the generated script. Concatenating a name
-- straight into brackets emits SYNTACTICALLY INVALID DDL the moment the name contains a ].
-- Proved on the lab 2026-09-01: a user called `zzorph_we]ird` produced
--   ALTER USER [zzorph_we]ird] WITH LOGIN = [zzorph_we]ird];
-- which fails with "Msg 102 ... Incorrect syntax near 'ird'". QUOTENAME doubles the bracket.
-- A generator is only as good as the DDL it emits, and nothing else in the pipeline checks it.
SELECT @ddl = @ddl
    + N'USE ' + QUOTENAME(o.database_name) + N';' + @crlf
    + CASE WHEN o.is_read_only = 1
        THEN N'-- NOTE: ' + o.database_name + N' is READ_ONLY. Set it READ_WRITE before the '
             + N'ALTER USER below can run.' + @crlf
        ELSE N'' END
    + CASE
        WHEN EXISTS (
            SELECT 1 FROM sys.server_principals sp
            WHERE sp.name = o.user_name AND sp.type IN ('S','U','G')
        )
        THEN N'ALTER USER ' + QUOTENAME(o.user_name) + N' WITH LOGIN = '
             + QUOTENAME(o.user_name) + N';' + @crlf
        ELSE N'-- Cannot auto-fix: no login named ' + QUOTENAME(o.user_name)
             + N' found. Create the login first or map manually.' + @crlf
      END
    + N'GO' + @crlf + @crlf
FROM #orphans o
ORDER BY o.database_name, o.user_name;

-- Databases that could not be scanned are named, with the reason, ABOVE any all-clear, and
-- the all-clear itself is reworded so it can never claim more than was actually checked.
IF EXISTS (SELECT 1 FROM #failed)
BEGIN
    SET @ddl = @ddl + @crlf
        + N'-- !! NOT A COMPLETE SCAN. These databases could not be read, so any orphaned'
        + @crlf
        + N'-- !! users in them are NOT listed above. Resolve these before trusting the result.'
        + @crlf;
    SELECT @ddl = @ddl + N'--    ' + f.database_name + N': ' + f.reason + @crlf
    FROM #failed f;
    SET @ddl = @ddl + @crlf;
END

IF NOT EXISTS (SELECT 1 FROM #orphans)
    SET @ddl = @ddl
        + CASE WHEN EXISTS (SELECT 1 FROM #failed)
            THEN N'-- No orphaned users found IN THE DATABASES THAT COULD BE SCANNED. '
                 + N'See the unscanned list above.'
            ELSE N'-- No orphaned users found. All database users map to a valid server login.'
          END + @crlf;

DROP TABLE #orphans;
DROP TABLE #failed;

SELECT @ddl AS ddl;
