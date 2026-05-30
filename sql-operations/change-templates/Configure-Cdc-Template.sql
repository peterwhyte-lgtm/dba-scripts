/*
Change Order / DBA Runbook: Configure CDC

Purpose:
  Enable Change Data Capture for a database and one target table.
Business impact:
  Supports change tracking for downstream ETL, auditing, and replication workflows.
Pre-checks:
  1. Ensure SQL Server Agent is running.
  2. Confirm the table has a reliable primary key or unique index.
  3. Confirm the DBA has rights to enable CDC on the database and table.
Execution notes:
  - Replace placeholders before execution.
  - Review the capture job and retention settings after enabling CDC.
Validation:
  - Confirm CDC is enabled at the database and table level.
Rollback:
  - Disable CDC with sys.sp_cdc_disable_db and sys.sp_cdc_disable_table if the change must be reversed.
*/

SET NOCOUNT ON;
GO

DECLARE @TargetDatabase sysname = N'YourDatabase';
DECLARE @TargetSchema   sysname = N'dbo';
DECLARE @TargetTable    sysname = N'YourTable';

DECLARE @sql nvarchar(max);

-- Enable CDC at the database level if it is not already enabled.
SET @sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N''' + REPLACE(@TargetDatabase, '''', '''''') + N''' AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END;
';
PRINT @sql;
EXEC sys.sp_executesql @sql;

-- Enable CDC on the target table.
SET @sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
IF NOT EXISTS (
    SELECT 1
    FROM cdc.change_tables ct
    INNER JOIN sys.tables t ON ct.source_object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = N''' + REPLACE(@TargetSchema, '''', '''''') + N'''
      AND t.name = N''' + REPLACE(@TargetTable, '''', '''''') + N'''
)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N''' + REPLACE(@TargetSchema, '''', '''''') + N''',
        @source_name   = N''' + REPLACE(@TargetTable, '''', '''''') + N''',
        @role_name     = NULL,
        @supports_net_changes = 0;
END;
';
PRINT @sql;
EXEC sys.sp_executesql @sql;
GO

-- Validation query to confirm CDC is enabled for the table.
SELECT
    DB_NAME() AS database_name,
    s.name AS schema_name,
    t.name AS table_name,
    t.is_tracked_by_cdc
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON t.schema_id = s.schema_id
WHERE s.name = @TargetSchema
  AND t.name = @TargetTable;
