/*
Change Order / DBA Runbook: Restore with NORECOVERY

Purpose:
  Use this template for a controlled restore sequence that leaves the database in NORECOVERY.
Business impact:
  Supports DR, secondary recovery, and staged recovery preparation.
Pre-checks:
  1. Confirm backup paths and media are available.
  2. Confirm the restore login has the required permissions.
  3. Verify the target server has enough storage for the restore.
Execution notes:
  - Replace the file paths and database names before execution.
  - Use this as the foundation for a multi-step DR or failover procedure.
Validation:
  - Confirm the database state after the restore steps and inspect the recovery model.
Rollback:
  - Stop after the NORECOVERY step if the restore needs to be rechecked or re-run.
*/

SET NOCOUNT ON;
GO

DECLARE @DatabaseName sysname = N'YourDatabase';
DECLARE @BackupPath nvarchar(4000) = N'D:\SQLBackups\YourDatabase_FULL.bak';
DECLARE @LogBackupPath nvarchar(4000) = N'D:\SQLBackups\YourDatabase_LOG.trn';

RESTORE DATABASE [YourDatabase]
FROM DISK = @BackupPath
WITH NORECOVERY, REPLACE;
GO

RESTORE LOG [YourDatabase]
FROM DISK = @LogBackupPath
WITH NORECOVERY;
GO

SELECT name, recovery_model_desc, state_desc
FROM sys.databases
WHERE name = @DatabaseName;
