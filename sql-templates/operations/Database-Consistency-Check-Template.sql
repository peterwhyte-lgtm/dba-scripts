/*
Change Order / DBA Runbook: Database Consistency Check

Purpose:
  Run a repeatable DBCC CHECKDB validation pass for a production database.
Business impact:
  Helps confirm database integrity before upgrades, migrations, or major maintenance.
Pre-checks:
  1. Confirm the database is in a safe maintenance window.
  2. Ensure the DBA has the needed DBCC CHECKDB permissions and storage headroom.
  3. Review expected runtime and alerting before starting.
Execution notes:
  - Replace the database name and any options before execution.
  - Save the output for incident or change record evidence.
Validation:
  - Review the DBCC output for corruption or consistency issues.
Rollback:
  - No rollback is required, but the change record should capture the result and next action.
*/

SET NOCOUNT ON;
GO

DECLARE @DatabaseName sysname = N'YourDatabase';

DECLARE @sql nvarchar(max);

SET @sql = N'USE ' + QUOTENAME(@DatabaseName) + N';
DBCC CHECKDB WITH NO_INFOMSGS, ALL_ERRORMSGS;
';

PRINT @sql;
EXEC sys.sp_executesql @sql;
GO

SELECT name, state_desc, recovery_model_desc
FROM sys.databases
WHERE name = @DatabaseName;
