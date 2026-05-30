/*
Script Name : Get-OrphanedUsers
Category    : security-and-permissions
Purpose     : Find database users with no matching server login — common after migrations or login drops.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
Notes       : Orphaned users cause login failures for that account. Fix with
              ALTER USER [username] WITH LOGIN = [login_name]; or DROP USER [username].
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

IF OBJECT_ID('tempdb..#orphaned') IS NOT NULL DROP TABLE #orphaned;

CREATE TABLE #orphaned (
    database_name NVARCHAR(128),
    user_name     NVARCHAR(128),
    user_type     NVARCHAR(60),
    create_date   DATETIME
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #orphaned
SELECT
    DB_NAME()    AS database_name,
    dp.name      AS user_name,
    dp.type_desc AS user_type,
    dp.create_date
FROM sys.database_principals AS dp
WHERE dp.type          IN (''S'', ''U'')
  AND dp.principal_id   > 4
  AND dp.sid           IS NOT NULL
  AND dp.name          NOT IN (''guest'', ''INFORMATION_SCHEMA'', ''sys'', ''dbo'')
  AND NOT EXISTS (
      SELECT 1
      FROM sys.server_principals AS sp
      WHERE sp.sid = dp.sid
  );
'
FROM sys.databases
WHERE database_id > 4
  AND state_desc  = 'ONLINE';

EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    user_name,
    user_type,
    create_date
FROM #orphaned
ORDER BY database_name, user_name;

DROP TABLE #orphaned;
