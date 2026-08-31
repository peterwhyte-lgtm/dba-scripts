/*
Script Name : Create-OrphanedUserScenario
Category    : lab
Purpose     : Create three deliberate orphaned-user shapes on a LAB instance so
              Fix-OrphanedUsers can be demonstrated showing every branch it has, instead of
              the single "cannot auto-fix" line the lab happens to produce today.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-fix-orphaned-users/)
Requires    : sysadmin on a LAB instance. Creates a database and three logins.
*/
-- SAFE:CreatesObjects
-- IMPACT:High
--
-- ⚠ LAB ONLY. This creates a database called zzorph_db and three logins, all prefixed
--   zzorph_, and it DROPS them again in Remove-OrphanedUserScenario.sql. Never run it on a
--   server you care about. Nothing outside the zzorph_ prefix is touched.
--
-- The three shapes, and what Fix-OrphanedUsers should say about each:
--   zzorph_fixable  login dropped and recreated, so the SID differs but the NAME matches
--                   -> ALTER USER [zzorph_fixable] WITH LOGIN = [zzorph_fixable];
--   zzorph_nologin  login dropped and left gone
--                   -> "-- Cannot auto-fix: no login named [zzorph_nologin] found."
--   zzorph_we]ird   same as fixable, but the name contains a ] so the generated DDL has to
--                   double it -> ALTER USER [zzorph_we]]ird] ... This is the case that
--                   produced invalid SQL before the 2026-09-01 QUOTENAME fix.
--
-- To also demonstrate the read-only branch, run this after setup:
--   ALTER DATABASE zzorph_db SET READ_ONLY WITH ROLLBACK IMMEDIATE;
-- and Fix-OrphanedUsers will list the orphans WITH a note that the database must be set
-- READ_WRITE first. Before the fix it skipped read-only databases silently.

SET NOCOUNT ON;

IF DB_ID('zzorph_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzorph_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzorph_db;
END
CREATE DATABASE zzorph_db;
GO

IF SUSER_ID('zzorph_fixable') IS NOT NULL DROP LOGIN zzorph_fixable;
IF SUSER_ID('zzorph_nologin') IS NOT NULL DROP LOGIN zzorph_nologin;
IF SUSER_ID('zzorph_we]ird')  IS NOT NULL DROP LOGIN [zzorph_we]]ird];
CREATE LOGIN zzorph_fixable WITH PASSWORD = 'Str0ng!Pass#2026', CHECK_POLICY = OFF;
CREATE LOGIN zzorph_nologin WITH PASSWORD = 'Str0ng!Pass#2026', CHECK_POLICY = OFF;
CREATE LOGIN [zzorph_we]]ird] WITH PASSWORD = 'Str0ng!Pass#2026', CHECK_POLICY = OFF;
GO

USE zzorph_db;
GO
CREATE USER zzorph_fixable FOR LOGIN zzorph_fixable;
CREATE USER zzorph_nologin FOR LOGIN zzorph_nologin;
CREATE USER [zzorph_we]]ird] FOR LOGIN [zzorph_we]]ird];
GO

USE master;
GO
-- orphan all three by removing the login each user's SID points at
DROP LOGIN zzorph_fixable;
CREATE LOGIN zzorph_fixable WITH PASSWORD = 'Str0ng!Pass#2026', CHECK_POLICY = OFF;
DROP LOGIN zzorph_nologin;
DROP LOGIN [zzorph_we]]ird];
CREATE LOGIN [zzorph_we]]ird] WITH PASSWORD = 'Str0ng!Pass#2026', CHECK_POLICY = OFF;
GO

SELECT dp.name AS database_user,
       CASE WHEN sp.sid IS NULL THEN 'ORPHANED' ELSE 'mapped' END AS state,
       CASE WHEN EXISTS (SELECT 1 FROM sys.server_principals x WHERE x.name = dp.name)
            THEN 'a login of this name exists, so it is auto-fixable'
            ELSE 'no login of this name, so it cannot be auto-fixed' END AS expected
FROM zzorph_db.sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.name LIKE 'zzorph%'
ORDER BY dp.name;
