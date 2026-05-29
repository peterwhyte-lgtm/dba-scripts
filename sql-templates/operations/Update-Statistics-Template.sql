/*
Change Order / DBA Runbook: Update Statistics

Purpose:
  Use this template to perform a controlled statistics update for a table or a full database.
Business impact:
  Improves plan quality and query performance after schema, index, or data distribution changes.
Pre-checks:
  1. Confirm the target database and table names.
  2. Confirm the DBA has rights to run UPDATE STATISTICS on the object.
  3. Choose a maintenance window for large objects.
Execution notes:
  - Replace placeholders before execution.
  - Use SAMPLE PERCENT for quick maintenance or FULLSCAN for more accurate plan quality.
Validation:
  - Review the output and confirm the command completes without errors.
Rollback:
  - No rollback is required for statistics updates; the engine will regenerate statistics as needed.
*/

SET NOCOUNT ON;
GO

DECLARE @TargetDatabase sysname = N'YourDatabase';
DECLARE @TargetSchema   sysname = N'dbo';
DECLARE @TargetTable    sysname = N'YourTable';
DECLARE @SamplePercent  int     = 25;      -- 0 = full scan, 100 = full scan, 1-99 = sample percent
DECLARE @ResampleAll    bit     = 1;       -- 1 = update all statistics on the table, 0 = only target stats

DECLARE @sql nvarchar(max);

SET @sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
'
         + N'UPDATE STATISTICS ' + QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable) + N' WITH SAMPLE ' + CAST(@SamplePercent AS nvarchar(10)) + N' PERCENT, RESAMPLE = ' + CASE WHEN @ResampleAll = 1 THEN N'ON' ELSE N'OFF' END + N';';

PRINT @sql;
EXEC sys.sp_executesql @sql;
GO

/* Optional: update all statistics in the database for a broader maintenance pass. */
-- EXEC sys.sp_updatestats;
