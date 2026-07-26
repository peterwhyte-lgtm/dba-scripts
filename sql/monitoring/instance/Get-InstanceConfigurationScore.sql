/*
Script Name : Get-InstanceConfigurationScore
Category    : monitoring
Purpose     : Scores the SQL Server instance across ~20 key configuration checks. Returns PASS/WARN/FAIL per item with finding and recommended action. Run this first when taking ownership of a new instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-instance-configuration-score/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-instance-configuration-score/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @max_server_memory        BIGINT  = (SELECT CAST(value_in_use AS BIGINT) FROM sys.configurations WHERE name = 'max server memory (MB)');
DECLARE @maxdop                   INT     = (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'max degree of parallelism');
DECLARE @cost_threshold           INT     = (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'cost threshold for parallelism');
DECLARE @xp_cmdshell              INT     = (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'xp_cmdshell');
DECLARE @optimize_adhoc           INT     = (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'optimize for ad hoc workloads');
DECLARE @backup_compression       INT     = (SELECT CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'backup compression default');
DECLARE @cpu_count                INT     = (SELECT cpu_count FROM sys.dm_os_sys_info);
DECLARE @physical_memory_mb       BIGINT  = (SELECT physical_memory_kb / 1024 FROM sys.dm_os_sys_info);
DECLARE @recommended_max_mem      BIGINT  = @physical_memory_mb - CASE WHEN @physical_memory_mb > 16384 THEN 4096 WHEN @physical_memory_mb > 4096 THEN 2048 ELSE 1024 END;
DECLARE @recommended_maxdop       INT     = CASE WHEN @cpu_count <= 8 THEN @cpu_count ELSE 8 END;
DECLARE @sa_enabled               INT     = (SELECT CAST(is_disabled AS INT) FROM sys.server_principals WHERE name = 'sa');
DECLARE @db_without_backup_7d     INT     = (SELECT COUNT(*) FROM sys.databases d WHERE d.name NOT IN ('master','model','msdb','tempdb') AND d.state = 0 AND NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset bs WHERE bs.database_name = d.name AND bs.type = 'D' AND bs.backup_finish_date >= DATEADD(DAY, -7, GETDATE())));
DECLARE @db_without_checkdb_7d    INT     = (SELECT COUNT(*) FROM sys.databases d WHERE d.name NOT IN ('master','model','tempdb') AND d.state = 0 AND NOT EXISTS (SELECT 1 FROM msdb.dbo.suspect_pages WHERE 1=0) AND DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') < DATEADD(DAY, -7, GETDATE()));
DECLARE @autoshrink_count         INT     = (SELECT COUNT(*) FROM sys.databases WHERE is_auto_shrink_on = 1 AND name NOT IN ('master','model','msdb','tempdb'));
DECLARE @autoclose_count          INT     = (SELECT COUNT(*) FROM sys.databases WHERE is_auto_close_on = 1 AND name NOT IN ('master','model','msdb','tempdb'));
DECLARE @pct_growth_db_count      INT     = (SELECT COUNT(DISTINCT database_id) FROM sys.master_files WHERE is_percent_growth = 1 AND type = 0 AND database_id > 4);
DECLARE @non_checksum_db_count    INT     = (SELECT COUNT(*) FROM sys.databases WHERE page_verify_option_desc <> 'CHECKSUM' AND name NOT IN ('master','model','msdb','tempdb') AND state = 0);
DECLARE @offline_db_count         INT     = (SELECT COUNT(*) FROM sys.databases WHERE state <> 0 AND name NOT IN ('master','model','msdb','tempdb'));
DECLARE @compat_behind_count      INT     = (SELECT COUNT(*) FROM sys.databases d WHERE d.state = 0 AND d.name NOT IN ('master','model','msdb','tempdb') AND d.compatibility_level < (SELECT CASE CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) WHEN 16 THEN 160 WHEN 15 THEN 150 WHEN 14 THEN 140 WHEN 13 THEN 130 WHEN 12 THEN 120 WHEN 11 THEN 110 ELSE 100 END));
DECLARE @linked_server_count      INT     = (SELECT COUNT(*) FROM sys.servers WHERE is_linked = 1);
DECLARE @user_db_count            INT     = (SELECT COUNT(*) FROM sys.databases WHERE name NOT IN ('master','model','msdb','tempdb') AND state = 0);

SELECT
    sort_order,
    category,
    check_name,
    weight,
    status,
    finding,
    recommendation
FROM (

    -- Max server memory
    SELECT 1 AS sort_order, 'Memory' AS category, 'Max server memory configured' AS check_name, 'HIGH' AS weight,
        CASE WHEN @max_server_memory = 2147483647 THEN 'FAIL' WHEN @max_server_memory > @recommended_max_mem * 1.1 THEN 'WARN' ELSE 'PASS' END AS status,
        CASE WHEN @max_server_memory = 2147483647 THEN 'Default (2147483647 MB) — no limit set; SQL can starve the OS'
             WHEN @max_server_memory > @recommended_max_mem * 1.1 THEN 'Set to ' + CAST(@max_server_memory AS VARCHAR) + ' MB — may be higher than recommended (' + CAST(@recommended_max_mem AS VARCHAR) + ' MB)'
             ELSE 'Set to ' + CAST(@max_server_memory AS VARCHAR) + ' MB (recommended: ' + CAST(@recommended_max_mem AS VARCHAR) + ' MB)' END AS finding,
        CASE WHEN @max_server_memory = 2147483647 THEN 'Set max server memory: EXEC sp_configure ''max server memory (MB)'', ' + CAST(@recommended_max_mem AS VARCHAR) + '; RECONFIGURE'
             ELSE 'No action required' END AS recommendation

    UNION ALL

    -- MAXDOP
    SELECT 2, 'Parallelism', 'MAXDOP configured', 'HIGH',
        CASE WHEN @maxdop = 0 AND @cpu_count > 8 THEN 'WARN' WHEN @maxdop = 0 AND @cpu_count <= 8 THEN 'PASS' WHEN @maxdop BETWEEN 1 AND @recommended_maxdop THEN 'PASS' ELSE 'WARN' END,
        'MAXDOP: ' + CAST(@maxdop AS VARCHAR) + ' | CPU count: ' + CAST(@cpu_count AS VARCHAR) + ' | Recommended: ' + CAST(@recommended_maxdop AS VARCHAR),
        CASE WHEN @maxdop = 0 AND @cpu_count > 8 THEN 'Set MAXDOP to ' + CAST(@recommended_maxdop AS VARCHAR) + ': EXEC sp_configure ''max degree of parallelism'', ' + CAST(@recommended_maxdop AS VARCHAR) + '; RECONFIGURE' ELSE 'No action required' END

    UNION ALL

    -- Cost threshold for parallelism
    SELECT 3, 'Parallelism', 'Cost threshold for parallelism', 'MEDIUM',
        CASE WHEN @cost_threshold <= 5 THEN 'WARN' ELSE 'PASS' END,
        'Cost threshold: ' + CAST(@cost_threshold AS VARCHAR) + CASE WHEN @cost_threshold <= 5 THEN ' (default — most OLTP queries will parallelize unnecessarily)' ELSE '' END,
        CASE WHEN @cost_threshold <= 5 THEN 'Increase to 50: EXEC sp_configure ''cost threshold for parallelism'', 50; RECONFIGURE' ELSE 'No action required' END

    UNION ALL

    -- Backup coverage (7 days)
    SELECT 4, 'Backup', 'All databases have recent full backup', 'CRITICAL',
        CASE WHEN @db_without_backup_7d > 0 THEN 'FAIL' ELSE 'PASS' END,
        CASE WHEN @db_without_backup_7d > 0 THEN CAST(@db_without_backup_7d AS VARCHAR) + ' database(s) have no full backup in the last 7 days — see Get-BackupCoverage.sql'
             ELSE 'All ' + CAST(@user_db_count AS VARCHAR) + ' user database(s) have a full backup within 7 days' END,
        CASE WHEN @db_without_backup_7d > 0 THEN 'Run Get-BackupCoverage.sql to identify affected databases; ensure backup jobs are scheduled and running' ELSE 'No action required' END

    UNION ALL

    -- Backup compression
    SELECT 5, 'Backup', 'Backup compression enabled', 'MEDIUM',
        CASE WHEN @backup_compression = 1 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @backup_compression = 1 THEN 'Backup compression is enabled (default)' ELSE 'Backup compression is OFF — backups will be larger and slower' END,
        CASE WHEN @backup_compression = 0 THEN 'Enable: EXEC sp_configure ''backup compression default'', 1; RECONFIGURE' ELSE 'No action required' END

    UNION ALL

    -- DBCC CHECKDB (7 days)
    SELECT 6, 'Integrity', 'DBCC CHECKDB run within 7 days', 'CRITICAL',
        CASE WHEN @db_without_checkdb_7d > 0 THEN 'WARN' ELSE 'PASS' END,
        CASE WHEN @db_without_checkdb_7d > 0 THEN CAST(@db_without_checkdb_7d AS VARCHAR) + ' database(s) have not had DBCC CHECKDB in 7+ days — see Get-LastDbccCheckdb.sql'
             ELSE 'All databases have had DBCC CHECKDB within 7 days' END,
        CASE WHEN @db_without_checkdb_7d > 0 THEN 'Schedule regular DBCC CHECKDB maintenance — weekly minimum; run Get-DatabaseIntegrityChecks.sql' ELSE 'No action required' END

    UNION ALL

    -- sa login disabled
    SELECT 7, 'Security', 'sa login disabled or renamed', 'HIGH',
        CASE WHEN @sa_enabled = 1 THEN 'PASS' WHEN @sa_enabled = 0 THEN 'WARN' ELSE 'PASS' END,
        CASE WHEN @sa_enabled = 1 THEN 'sa login is disabled' WHEN @sa_enabled = 0 THEN 'sa login is ENABLED — SQL auth attack surface' ELSE 'sa login not found (likely renamed — best practice)' END,
        CASE WHEN @sa_enabled = 0 THEN 'Disable: ALTER LOGIN [sa] DISABLE; or rename: ALTER LOGIN [sa] WITH NAME = [sql_sa_disabled]' ELSE 'No action required' END

    UNION ALL

    -- xp_cmdshell
    SELECT 8, 'Security', 'xp_cmdshell disabled', 'HIGH',
        CASE WHEN @xp_cmdshell = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @xp_cmdshell = 0 THEN 'xp_cmdshell is disabled' ELSE 'xp_cmdshell is ENABLED — allows OS command execution from SQL' END,
        CASE WHEN @xp_cmdshell = 1 THEN 'Disable: EXEC sp_configure ''xp_cmdshell'', 0; RECONFIGURE' ELSE 'No action required' END

    UNION ALL

    -- AUTO_SHRINK
    SELECT 9, 'Database Settings', 'AUTO_SHRINK disabled', 'HIGH',
        CASE WHEN @autoshrink_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @autoshrink_count = 0 THEN 'No user databases have AUTO_SHRINK enabled'
             ELSE CAST(@autoshrink_count AS VARCHAR) + ' database(s) have AUTO_SHRINK ON — causes fragmentation and growth-shrink cycles' END,
        CASE WHEN @autoshrink_count > 0 THEN 'Disable on affected databases: ALTER DATABASE [dbname] SET AUTO_SHRINK OFF — see Get-DatabaseHealth.sql for full list' ELSE 'No action required' END

    UNION ALL

    -- AUTO_CLOSE
    SELECT 10, 'Database Settings', 'AUTO_CLOSE disabled', 'MEDIUM',
        CASE WHEN @autoclose_count = 0 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @autoclose_count = 0 THEN 'No user databases have AUTO_CLOSE enabled'
             ELSE CAST(@autoclose_count AS VARCHAR) + ' database(s) have AUTO_CLOSE ON — causes connection overhead and plan cache flushes' END,
        CASE WHEN @autoclose_count > 0 THEN 'Disable: ALTER DATABASE [dbname] SET AUTO_CLOSE OFF — see Get-DatabaseHealth.sql for list' ELSE 'No action required' END

    UNION ALL

    -- Percentage-based autogrowth
    SELECT 11, 'Storage', 'No percentage-based autogrowth', 'HIGH',
        CASE WHEN @pct_growth_db_count = 0 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @pct_growth_db_count = 0 THEN 'No data files use percentage-based autogrowth'
             ELSE CAST(@pct_growth_db_count AS VARCHAR) + ' database(s) have data files with percentage-based growth — growth events become unpredictably large' END,
        CASE WHEN @pct_growth_db_count > 0 THEN 'Switch to fixed-size growth (e.g., 256 MB or 1 GB): ALTER DATABASE [dbname] MODIFY FILE (NAME = N''filename'', FILEGROWTH = 256MB) — see Get-DatabaseFilesDetail.sql' ELSE 'No action required' END

    UNION ALL

    -- Page verify CHECKSUM
    SELECT 12, 'Data Integrity', 'Page verify set to CHECKSUM', 'MEDIUM',
        CASE WHEN @non_checksum_db_count = 0 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @non_checksum_db_count = 0 THEN 'All databases use CHECKSUM page verification'
             ELSE CAST(@non_checksum_db_count AS VARCHAR) + ' database(s) not using CHECKSUM — torn page detection only or none' END,
        CASE WHEN @non_checksum_db_count > 0 THEN 'Set CHECKSUM: ALTER DATABASE [dbname] SET PAGE_VERIFY CHECKSUM WITH NO_WAIT — see Get-DatabaseHealth.sql for list' ELSE 'No action required' END

    UNION ALL

    -- Databases in non-ONLINE state
    SELECT 13, 'Database State', 'No databases offline or suspect', 'CRITICAL',
        CASE WHEN @offline_db_count = 0 THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN @offline_db_count = 0 THEN 'All user databases are ONLINE'
             ELSE CAST(@offline_db_count AS VARCHAR) + ' database(s) are in a non-ONLINE state — investigate immediately' END,
        CASE WHEN @offline_db_count > 0 THEN 'Run: SELECT name, state_desc, user_access_desc FROM sys.databases WHERE state <> 0 — investigate each' ELSE 'No action required' END

    UNION ALL

    -- Optimize for ad hoc workloads
    SELECT 14, 'Memory', 'Optimize for ad hoc workloads', 'MEDIUM',
        CASE WHEN @optimize_adhoc = 1 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @optimize_adhoc = 1 THEN 'Optimize for ad hoc workloads is enabled'
             ELSE 'Optimize for ad hoc workloads is OFF — single-use plan stubs waste plan cache memory' END,
        CASE WHEN @optimize_adhoc = 0 THEN 'Enable: EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE' ELSE 'No action required' END

    UNION ALL

    -- Compatibility levels
    SELECT 15, 'Compatibility', 'Databases at current compat level', 'MEDIUM',
        CASE WHEN @compat_behind_count = 0 THEN 'PASS' ELSE 'WARN' END,
        CASE WHEN @compat_behind_count = 0 THEN 'All user databases are at the instance native compatibility level'
             ELSE CAST(@compat_behind_count AS VARCHAR) + ' database(s) are below instance native compatibility level — may miss QO improvements' END,
        CASE WHEN @compat_behind_count > 0 THEN 'Review with Get-CompatibilityLevelAudit.sql; test in non-prod before upgrading compat level' ELSE 'No action required' END

    UNION ALL

    -- Linked servers (awareness)
    SELECT 16, 'Dependencies', 'Linked servers present', 'LOW',
        CASE WHEN @linked_server_count = 0 THEN 'PASS' ELSE 'INFO' END,
        CASE WHEN @linked_server_count = 0 THEN 'No linked servers configured'
             ELSE CAST(@linked_server_count AS VARCHAR) + ' linked server(s) configured — review for security and dependency risk' END,
        CASE WHEN @linked_server_count > 0 THEN 'Review with Get-LinkedServerAndJobInventory.sql — confirm each is still required' ELSE 'No action required' END

) checks
ORDER BY
    CASE status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 WHEN 'INFO' THEN 3 ELSE 4 END,
    CASE weight WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
    sort_order;
