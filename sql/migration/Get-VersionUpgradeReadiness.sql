/*
Script Name : Get-VersionUpgradeReadiness
Category    : migration
Purpose     : Pre-upgrade readiness summary for SQL Server version upgrades.
              One result set with a section column: instance summary, per-database
              compatibility levels, configuration items to review, and sizing for
              migration window planning. Run on SOURCE.
              Complements Get-DeprecatedFeaturesInUse.sql (feature detail) and
              Get-MigrationRiskAssessment.sql (per-database risk).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: A single result set (the repo contract: one script, one CSV) shaped as
  section / item / detail / status:
    1-instance  — current version, edition, and supported direct upgrade paths
    2-compat    — which databases are behind the native compatibility level
    3-config    — sp_configure items worth reviewing before a version move
    4-sizing    — data/log totals per database for migration window planning

  Use alongside:
    Get-DeprecatedFeaturesInUse.sql — deprecated features called since last restart
    Get-MigrationRiskAssessment.sql — per-database risk findings (compat, settings, AG, sizing)
    Get-EditionFeatureUsage.sql — Enterprise-only features (if changing edition at same time)
*/

DECLARE @major INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);
DECLARE @version NVARCHAR(20) = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(20));
DECLARE @level NVARCHAR(20) = CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(20));
DECLARE @edition NVARCHAR(128)= CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128));
DECLARE @collation NVARCHAR(128)= CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128));
DECLARE @nativeCompat SMALLINT;
DECLARE @upgradeNote NVARCHAR(400);

SET @nativeCompat =
    CASE @major
        WHEN 17 THEN 170 -- SQL 2025
        WHEN 16 THEN 160 -- SQL 2022
        WHEN 15 THEN 150 -- SQL 2019
        WHEN 14 THEN 140 -- SQL 2017
        WHEN 13 THEN 130 -- SQL 2016
        WHEN 12 THEN 120 -- SQL 2014
        WHEN 11 THEN 110 -- SQL 2012
        WHEN 10 THEN 100 -- SQL 2008/2008R2
        WHEN 9 THEN 90 -- SQL 2005
        ELSE NULL -- newer than this script knows about, or older than SQL 2005
    END;

SET @upgradeNote =
    CASE @major
        WHEN 17 THEN 'SQL 2025 is current GA release. No direct upgrade target beyond this.'
        WHEN 16 THEN 'Direct upgrade supported to: SQL 2025.'
        WHEN 15 THEN 'Direct upgrade supported to: SQL 2022, SQL 2025.'
        WHEN 14 THEN 'Direct upgrade supported to: SQL 2019, SQL 2022, SQL 2025.'
        WHEN 13 THEN 'Direct upgrade supported to: SQL 2019, SQL 2022, SQL 2025.'
        WHEN 12 THEN 'Direct upgrade supported to: SQL 2016, SQL 2017, SQL 2019, SQL 2022.'
        WHEN 11 THEN 'Direct upgrade supported to: SQL 2016, SQL 2017, SQL 2019, SQL 2022.'
        WHEN 10 THEN 'Direct in-place upgrade NOT supported to SQL 2017+. Upgrade to SQL 2014 or SQL 2016 first, or use side-by-side migration.'
        WHEN 9 THEN 'Very old version — side-by-side migration strongly recommended. No direct in-place upgrade path to current versions.'
        ELSE 'Newer than this script''s known version table — update Get-VersionUpgradeReadiness.sql with this release before trusting the compat-level and upgrade-path rows.'
    END;

-- ── 1. Instance summary ───────────────────────────────────────────────────────
SELECT section, item, detail, status
FROM (
    SELECT '1-instance' AS section, 'version' AS item,
           @version + ' (' + @level + ')' AS detail, '' AS status, 1 AS ord
    UNION ALL SELECT '1-instance', 'edition', @edition, '', 2
    UNION ALL SELECT '1-instance', 'server_collation', @collation, '', 3
    UNION ALL SELECT '1-instance', 'native_compat_level',
           ISNULL(CAST(@nativeCompat AS NVARCHAR(10)), 'unknown'), '', 4
    UNION ALL SELECT '1-instance', 'max_server_memory_mb',
           CAST((SELECT value_in_use FROM sys.configurations
                 WHERE name = 'max server memory (MB)') AS NVARCHAR(20)), '', 5
    UNION ALL SELECT '1-instance', 'maxdop',
           CAST((SELECT value_in_use FROM sys.configurations
                 WHERE name = 'max degree of parallelism') AS NVARCHAR(20)), '', 6
    UNION ALL SELECT '1-instance', 'last_restart',
           CONVERT(NVARCHAR(20), (SELECT sqlserver_start_time FROM sys.dm_os_sys_info), 120)
           + ' (' + CAST(DATEDIFF(DAY, (SELECT sqlserver_start_time FROM sys.dm_os_sys_info),
                                  GETDATE()) AS NVARCHAR(10)) + ' days ago)', '', 7
    UNION ALL SELECT '1-instance', 'upgrade_paths', @upgradeNote, '', 8

-- ── 2. Compatibility level per database ───────────────────────────────────────
    UNION ALL
    SELECT '2-compat', d.name,
           'compat ' + CAST(d.compatibility_level AS NVARCHAR(10))
           + ' vs native ' + CAST(@nativeCompat AS NVARCHAR(10))
           + ' (gap ' + CAST(@nativeCompat - d.compatibility_level AS NVARCHAR(10)) + ')'
           + ', ' + d.recovery_model_desc + ', ' + d.state_desc,
           CASE
               WHEN d.compatibility_level >= @nativeCompat THEN 'OK — at native level'
               WHEN d.compatibility_level = @nativeCompat - 10 THEN 'INFO — 1 version behind'
               WHEN d.compatibility_level = @nativeCompat - 20 THEN 'WARN — 2 versions behind'
               ELSE 'HIGH — severely behind native level'
           END,
           100 + (@nativeCompat - d.compatibility_level)
    FROM sys.databases d
    WHERE d.database_id > 4

-- ── 3. Configuration items to review for target version ──────────────────────
    UNION ALL
    SELECT '3-config', name, CAST(CAST(value_in_use AS BIGINT) AS NVARCHAR(20)),
           CASE
               WHEN name = 'max server memory (MB)' AND value_in_use >= 2147483647
                   THEN 'HIGH — Unconfigured. Set this before cutover to target to prevent memory pressure.'
               WHEN name = 'max degree of parallelism' AND value_in_use = 0
                   THEN 'INFO — MAXDOP = 0 (uses all CPUs). Set to min(8, CPU count / 2) unless validated.'
               WHEN name = 'cost threshold for parallelism' AND value_in_use <= 5
                   THEN 'INFO — Cost threshold = 5 (default). Consider 50+ on modern hardware to reduce parallelism noise.'
               WHEN name = 'optimize for ad hoc workloads' AND value_in_use = 0
                   THEN 'WARN — Disabled. Enable to reduce single-use plan cache bloat (sp_configure ''optimize for ad hoc workloads'', 1).'
               WHEN name = 'backup checksum default' AND value_in_use = 0
                   THEN 'INFO — Backup checksums off. Enable for stronger backup integrity checks.'
               WHEN name = 'remote query timeout (s)' AND value_in_use = 600
                   THEN 'INFO — Remote query timeout at default 600s. Review if linked servers are in use.'
               ELSE 'OK'
           END,
           200
    FROM sys.configurations
    WHERE name IN (
        'max server memory (MB)', 'min server memory (MB)',
        'max degree of parallelism', 'cost threshold for parallelism',
        'optimize for ad hoc workloads', 'backup compression default',
        'backup checksum default', 'remote query timeout (s)',
        'remote login timeout (s)', 'lightweight pooling', 'priority boost',
        'clr enabled', 'clr strict security', 'cross db ownership chaining',
        'Database Mail XPs', 'xp_cmdshell')

-- ── 4. Sizing per database, for migration window planning ─────────────────────
    UNION ALL
    SELECT '4-sizing', d.name,
           'data ' + CAST(CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(20))
           + ' GB, log ' + CAST(CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(20))
           + ' GB, total ' + CAST(CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS NVARCHAR(20)) + ' GB',
           '',
           300 - CAST(SUM(mf.size) / 128 AS INT)
    FROM sys.databases d
    INNER JOIN sys.master_files mf ON d.database_id = mf.database_id
    WHERE d.database_id > 4
    GROUP BY d.name
) readiness
ORDER BY section, ord, item;
