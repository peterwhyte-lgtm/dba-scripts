/*
Script Name : Remove-OrphanedUserScenario
Category    : lab
Purpose     : Remove everything Create-OrphanedUserScenario.sql created, and prove it is gone.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-fix-orphaned-users/)
Requires    : sysadmin on the same LAB instance.
*/
-- SAFE:WritesData
-- IMPACT:High
--
-- Drops the zzorph_db database and the three zzorph_ logins, and NOTHING else: every object
-- is matched on the zzorph_ prefix. The final two counts must both be 0; if they are not, say
-- so rather than assuming the teardown worked.
--
-- Note the escaping, which is the same trap the script itself had: a ] doubles inside
-- BRACKETS but is written plainly inside a STRING. Getting that backwards on 2026-09-01 left
-- one login behind and the first teardown reported success.
--   SUSER_ID('zzorph_we]ird')  -- plain, it is a string
--   DROP LOGIN [zzorph_we]]ird]  -- doubled, it is an identifier

SET NOCOUNT ON;
USE master;
GO

IF DB_ID('zzorph_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzorph_db SET READ_WRITE WITH ROLLBACK IMMEDIATE;
    ALTER DATABASE zzorph_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzorph_db;
END

IF SUSER_ID('zzorph_fixable') IS NOT NULL DROP LOGIN zzorph_fixable;
IF SUSER_ID('zzorph_nologin') IS NOT NULL DROP LOGIN zzorph_nologin;
IF SUSER_ID('zzorph_we]ird')  IS NOT NULL DROP LOGIN [zzorph_we]]ird];
IF SUSER_ID('zzorph_scan')    IS NOT NULL DROP LOGIN zzorph_scan;
GO

SELECT COUNT(*) AS zzorph_logins_left FROM sys.server_principals WHERE name LIKE 'zzorph%';
SELECT COUNT(*) AS zzorph_databases_left FROM sys.databases WHERE name LIKE 'zzorph%';
