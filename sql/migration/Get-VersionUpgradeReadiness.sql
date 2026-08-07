/*
Script Name : Get-VersionUpgradeReadiness
Category    : migration
Purpose     : Pre-upgrade readiness summary for SQL Server version upgrades.
              Complements Get-DeprecatedFeaturesInUse.sql (feature detail) and
              Get-MigrationRiskAssessment.sql (per-database risk). Run on SOURCE.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Returns four result sets:
    1. Instance summary — current version, edition, and supported direct upgrade paths
    2. Compatibility level matrix — which databases are behind native compat level
    3. Configuration delta — sp_configure items that have changed defaults or behaviour in newer versions
    4. Sizing summary — data/log totals per database for migration window planning

  Use alongside:
    Get-DeprecatedFeaturesInUse.sql — deprecated features called since last restart
    Get-MigrationRiskAssessment.sql — per-database risk findings (compat, settings, AG, sizing)
    Get-EditionFeatureUsage.sql — Enterprise-only features (if changing edition at same time)
*/

-- ── 1. Instance summary ───────────────────────────────────────────────────────

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
        ELSE 'Newer than this script''s known version table — update Get-VersionUpgradeReadiness.sql with this release before trusting the compat-level and upgrade-path columns.'
    END;

SELECT
    @version AS current_version,
    @level AS product_level,
    @edition AS edition,
    @collation AS server_collation,
    @nativeCompat AS native_compat_level,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)') AS max_server_memory_mb,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism') AS maxdop,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS last_restart,
    DATEDIFF(DAY, (SELECT sqlserver_start_time FROM sys.dm_os_sys_info), GETDATE()) AS days_since_restart,
    @upgradeNote AS upgrade_paths;

-- ── 2. Compatibility level matrix ─────────────────────────────────────────────

SELECT
    d.name AS database_name,
    d.compatibility_level AS current_compat_level,
    @nativeCompat AS native_compat_level,
    @nativeCompat - d.compatibility_level AS compat_gap,
    CASE
        WHEN d.compatibility_level >= @nativeCompat THEN 'OK — at native level'
        WHEN d.compatibility_level = @nativeCompat - 10 THEN 'INFO — 1 version behind'
        WHEN d.compatibility_level = @nativeCompat - 20 THEN 'WARN — 2 versions behind'
        ELSE 'HIGH — severely behind native level'
    END AS compat_status,
    d.recovery_model_desc AS recovery_model,
    d.state_desc AS database_state
FROM sys.databases d
WHERE d.database_id > 4
ORDER BY compat_gap DESC, d.name;

-- ── 3. Configuration items to review for target version ───────────────────────

;WITH config_review AS (
    SELECT
        name AS config_name,
        CAST(value_in_use AS BIGINT) AS current_value,
        CAST(minimum AS BIGINT) AS minimum,
        CAST(maximum AS BIGINT) AS maximum,
        is_advanced,
        CASE
            -- max server memory at SQL Server default (likely unconfigured)
            WHEN name = 'max server memory (MB)' AND value_in_use >= 2147483647
                THEN 'HIGH — Unconfigured. Set this before cutover to target to prevent memory pressure.'
            -- MAXDOP 0 (uses all CPUs) — newer guidance prefers explicit value
            WHEN name = 'max degree of parallelism' AND value_in_use = 0
                THEN 'INFO — MAXDOP = 0 (uses all CPUs). Set to min(8, CPU count / 2) unless validated.'
            -- Cost threshold default (5) — very low for modern hardware
            WHEN name = 'cost threshold for parallelism' AND value_in_use <= 5
                THEN 'INFO — Cost threshold = 5 (default). Consider 50+ on modern hardware to reduce parallelism noise.'
            -- Optimize for ad hoc workloads — should be ON
            WHEN name = 'optimize for ad hoc workloads' AND value_in_use = 0
                THEN 'WARN — Disabled. Enable to reduce single-use plan cache bloat (sp_configure ''optimize for ad hoc workloads'', 1).'
            -- Backup checksum — should be ON for new installs
            WHEN name = 'backup checksum default' AND value_in_use = 0
                THEN 'INFO — Backup checksums off. Enable for stronger backup integrity checks.'
            -- Remote query timeout default is 600s — may want to review
            WHEN name = 'remote query timeout (s)' AND value_in_use = 600
                THEN 'INFO — Remote query timeout at default 600s. Review if linked servers are in use.'
            ELSE 'OK'
        END AS review_note
    FROM sys.configurations
    WHERE name IN (
        'max server memory (MB)',
        'min server memory (MB)',
        'max degree of parallelism',
        'cost threshold for parallelism',
        'optimize for ad hoc workloads',
        'backup compression default',
        'backup checksum default',
        'remote query timeout (s)',
        'remote login timeout (s)',
        'lightweight pooling',
        'priority boost',
        'clr enabled',
        'clr strict security',
        'cross db ownership chaining',
        'Database Mail XPs',
        'xp_cmdshell'
    )
)
SELECT *
FROM config_review
ORDER BY
    CASE
        WHEN review_note LIKE 'HIGH%' THEN 1
        WHEN review_note LIKE 'WARN%' THEN 2
        WHEN review_note LIKE 'INFO%' THEN 3
        ELSE 4
    END,
    config_name;

-- ── 4. Sizing summary — for migration window planning ─────────────────────────

SELECT
    d.name AS database_name,
    d.recovery_model_desc AS recovery_model,
    d.compatibility_level AS compat_level,
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS data_size_gb,
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS log_size_gb,
    CAST(SUM(mf.size) * 8.0 / 1024 / 1024 AS DECIMAL(12,2)) AS total_size_gb
FROM sys.databases d
INNER JOIN sys.master_files mf ON d.database_id = mf.database_id
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc, d.compatibility_level
ORDER BY total_size_gb DESC;
