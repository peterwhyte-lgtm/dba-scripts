/*
Script Name : Create-BackupChainScenario
Category    : lab
Purpose     : Build a backup chain that shows every case the differential base behaves
              differently, so the chain inspector query returns something worth reading
              instead of one full backup and nothing else.
Author      : Peter Whyte (https://sqldba.blog/sql-server-differential-vs-log-backup/)
Requires    : sysadmin on a LAB instance. Creates one database.
*/
-- SAFE:CreatesObjects
-- IMPACT:High
--
-- LAB ONLY. Creates a database called zzchain_db and nothing else. Removed by
-- Remove-BackupChainScenario.sql, which also deletes its msdb backup history.
--
-- Backups go to DISK = 'nul', the Windows null device. They are real backup operations as far
-- as SQL Server and msdb are concerned, so backupset is populated exactly as it would be, but
-- nothing is written to disk and nothing needs cleaning up. These backups CANNOT be restored,
-- which is fine, the point is the chain metadata.
--
-- WHAT THE CHAIN DEMONSTRATES, in order:
--   1  FULL                 the differential base is established here
--   2  DIFFERENTIAL         base points at step 1
--   3  LOG                  begins_log_chain = 1, the first log backup of a new chain
--   4  DIFFERENTIAL         base STILL points at step 1, a log backup does not move it
--   5  FULL with COPY_ONLY  is_copy_only = 1
--   6  DIFFERENTIAL         base STILL points at step 1, copy-only does not move it either
--   7  FULL, ordinary       this is the one that moves the base
--   8  DIFFERENTIAL         base now points at step 7, everything before it is orphaned
--   9  LOG                  the chain continues
--
-- Step 7 is the whole point. An ordinary full backup taken by anyone, from any tool, silently
-- reparents every differential that follows it.

SET NOCOUNT ON;
USE master;
GO

IF DB_ID('zzchain_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzchain_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzchain_db;
END

-- Purge any msdb history from a previous run. Found the hard way: DROP DATABASE does NOT remove
-- backupset rows, so re-running this script stacked a second set of nine on top of the first and
-- the demo query returned eighteen. Same reason the teardown deletes history before the drop.
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'zzchain_db';

CREATE DATABASE zzchain_db;
ALTER DATABASE zzchain_db SET RECOVERY FULL;
GO

USE zzchain_db;
CREATE TABLE dbo.Activity (id INT IDENTITY PRIMARY KEY, note NVARCHAR(100), at DATETIME2 DEFAULT SYSDATETIME());
GO
USE master;
GO

-- a row between each step, so every backup has something new to carry
DECLARE @i INT = 1;
INSERT zzchain_db.dbo.Activity (note) VALUES (N'before the first full');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH NAME = N'S1_FULL';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after full');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH DIFFERENTIAL, NAME = N'S2_DIFF_after_full';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after diff');

BACKUP LOG zzchain_db TO DISK = 'nul' WITH NAME = N'S3_LOG';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after log');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH DIFFERENTIAL, NAME = N'S4_DIFF_after_LOG';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after second diff');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH COPY_ONLY, NAME = N'S5_FULL_COPYONLY';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after copy-only full');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH DIFFERENTIAL, NAME = N'S6_DIFF_after_COPYONLY';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after third diff');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH NAME = N'S7_FULL_ordinary';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after the ad hoc full');

BACKUP DATABASE zzchain_db TO DISK = 'nul' WITH DIFFERENTIAL, NAME = N'S8_DIFF_after_FULL';
INSERT zzchain_db.dbo.Activity (note) VALUES (N'after fourth diff');

BACKUP LOG zzchain_db TO DISK = 'nul' WITH NAME = N'S9_LOG';
GO

-- ---------------------------------------------------------------------------------------
-- THIS is the query to screenshot. Same shape as the one in the post.
-- ---------------------------------------------------------------------------------------
SELECT
    bs.database_name,
    backup_type = CASE bs.type
                      WHEN 'D' THEN CASE WHEN bs.is_copy_only = 1
                                         THEN 'Full (COPY_ONLY)' ELSE 'Full' END
                      WHEN 'I' THEN 'Differential'
                      WHEN 'L' THEN 'Log'
                      ELSE bs.type END,
    bs.name,
    bs.checkpoint_lsn,          -- on a full: the value a later differential points back to
    bs.differential_base_lsn,   -- on a differential: which full it actually needs
    bs.begins_log_chain,        -- 1 = a NEW log chain starts here, i.e. an old one ended
    bs.is_copy_only
FROM msdb.dbo.backupset AS bs
WHERE bs.database_name = N'zzchain_db'
  AND bs.backup_start_date >= DATEADD(DAY, -30, SYSDATETIME())
ORDER BY bs.backup_start_date, bs.backup_set_id;
GO

-- and the verdict, computed rather than eyeballed, so the scenario proves itself
DECLARE @base1 NUMERIC(25,0) = (SELECT checkpoint_lsn FROM msdb.dbo.backupset
                                WHERE database_name = N'zzchain_db' AND name LIKE N'S1_FULL');
DECLARE @base7 NUMERIC(25,0) = (SELECT checkpoint_lsn FROM msdb.dbo.backupset
                                WHERE database_name = N'zzchain_db' AND name LIKE N'S7_FULL_ordinary');
SELECT
    log_backup     = CASE WHEN (SELECT differential_base_lsn FROM msdb.dbo.backupset
                                WHERE database_name = N'zzchain_db' AND name LIKE N'S4_DIFF_after_LOG') = @base1
                          THEN 'CONFIRMED: a log backup does NOT move the differential base'
                          ELSE '*** UNEXPECTED ***' END,
    copy_only_full = CASE WHEN (SELECT differential_base_lsn FROM msdb.dbo.backupset
                                WHERE database_name = N'zzchain_db' AND name LIKE N'S6_DIFF_after_COPYONLY') = @base1
                          THEN 'CONFIRMED: a COPY_ONLY full does NOT move it'
                          ELSE '*** UNEXPECTED ***' END,
    ordinary_full  = CASE WHEN (SELECT differential_base_lsn FROM msdb.dbo.backupset
                                WHERE database_name = N'zzchain_db' AND name LIKE N'S8_DIFF_after_FULL') = @base7
                          THEN 'CONFIRMED: an ordinary full DOES move it'
                          ELSE '*** UNEXPECTED ***' END;
