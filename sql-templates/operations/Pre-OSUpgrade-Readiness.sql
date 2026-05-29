/*
Change Order / DBA Runbook: Pre-OS Upgrade Readiness

Purpose:
  Gather evidence and operational checks before an OS or host upgrade.
Business impact:
  Reduces upgrade risk by validating the instance, database configuration, and backup coverage.
Pre-checks:
  1. Confirm the DBA has VIEW ANY DATABASE and VIEW SERVER STATE permissions.
  2. Review the maintenance window and backup schedule.
  3. Verify the target OS and SQL Server support matrix.
Execution notes:
  - Use this as a pre-change readiness checklist and evidence snapshot.
  - Save the output in the change record or runbook repository.
Validation:
  - Review version, compatibility, storage, and backup information before proceeding.
Rollback:
  - If the upgrade cannot proceed, stop and document the readiness findings for the change owner.
*/

SET NOCOUNT ON;

SELECT
    @@SERVERNAME AS server_name,
    SERVERPROPERTY('MachineName') AS machine_name,
    SERVERPROPERTY('InstanceName') AS instance_name,
    SERVERPROPERTY('Edition') AS edition,
    SERVERPROPERTY('ProductVersion') AS product_version,
    SERVERPROPERTY('ProductLevel') AS product_level,
    SERVERPROPERTY('IsClustered') AS is_clustered,
    SERVERPROPERTY('Collation') AS server_collation;

SELECT
    d.name AS database_name,
    d.compatibility_level,
    d.recovery_model_desc,
    d.state_desc,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.user_access_desc,
    MAX(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size * 8.0 / 1024 END) AS data_mb,
    MAX(CASE WHEN mf.type_desc = 'LOG' THEN mf.size * 8.0 / 1024 END) AS log_mb
FROM sys.databases AS d
LEFT JOIN sys.master_files AS mf ON d.database_id = mf.database_id
GROUP BY d.name, d.compatibility_level, d.recovery_model_desc, d.state_desc,
         d.is_auto_close_on, d.is_auto_shrink_on, d.user_access_desc
ORDER BY d.name;

SELECT
    db_name(database_id) AS database_name,
    type_desc,
    name,
    physical_name,
    size / 128.0 AS size_mb,
    growth / 128.0 AS growth_mb,
    is_percent_growth,
    max_size / 128.0 AS max_size_mb
FROM sys.master_files
WHERE DB_NAME(database_id) NOT IN ('master', 'model', 'msdb', 'tempdb')
ORDER BY database_name, type_desc;

SELECT
    database_name = DB_NAME(database_id),
    backup_start_date,
    backup_finish_date,
    recovery_model,
    backup_type = CASE type WHEN 'D' THEN 'Full' WHEN 'I' THEN 'Differential' WHEN 'L' THEN 'Log' ELSE CAST(type AS varchar(10)) END,
    backup_size_mb = CAST(backup_size / 1024.0 / 1024.0 AS decimal(18, 2)),
    compressed_backup_size_mb = CAST(compressed_backup_size / 1024.0 / 1024.0 AS decimal(18, 2))
FROM msdb.dbo.backupset
WHERE backup_start_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY backup_start_date DESC;
