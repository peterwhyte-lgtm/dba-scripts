/*
Script Name : Get-CompatibilityLevelAudit
Category    : migration
Purpose     : Lists all user databases with current compatibility level, equivalent SQL version name, and the instance's native compatibility level. Use to plan compat level upgrades before or after migration.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/)
Requires    : VIEW ANY DATABASE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @instance_major   INT      = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);
DECLARE @instance_compat  SMALLINT =
    CASE @instance_major
        WHEN 17 THEN 170  -- SQL Server 2025
        WHEN 16 THEN 160  -- SQL Server 2022
        WHEN 15 THEN 150  -- SQL Server 2019
        WHEN 14 THEN 140  -- SQL Server 2017
        WHEN 13 THEN 130  -- SQL Server 2016
        WHEN 12 THEN 120  -- SQL Server 2014
        WHEN 11 THEN 110  -- SQL Server 2012
        WHEN 10 THEN 100  -- SQL Server 2008/R2
        WHEN 9  THEN 90   -- SQL Server 2005
        ELSE NULL         -- newer than this script knows about, or older than SQL 2005
    END;

SELECT
    d.name                  AS database_name,
    d.compatibility_level   AS current_compat,
    CASE d.compatibility_level
        WHEN 170 THEN 'SQL Server 2025'
        WHEN 160 THEN 'SQL Server 2022'
        WHEN 150 THEN 'SQL Server 2019'
        WHEN 140 THEN 'SQL Server 2017'
        WHEN 130 THEN 'SQL Server 2016'
        WHEN 120 THEN 'SQL Server 2014'
        WHEN 110 THEN 'SQL Server 2012'
        WHEN 100 THEN 'SQL Server 2008/2008 R2'
        WHEN  90 THEN 'SQL Server 2005'
        WHEN  80 THEN 'SQL Server 2000'
        ELSE         'Unknown'
    END                     AS current_compat_version,
    @instance_compat        AS instance_native_compat,
    CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20))
                            AS instance_version,
    CASE
        WHEN @instance_compat IS NULL                        THEN 'UNKNOWN — update this script''s version table'
        WHEN d.compatibility_level < (@instance_compat - 20) THEN 'NEEDS UPGRADE'
        WHEN d.compatibility_level < @instance_compat        THEN 'BELOW NATIVE'
        WHEN d.compatibility_level = @instance_compat        THEN 'AT NATIVE'
        ELSE                                                      'ABOVE NATIVE'
    END                     AS compat_status,
    CASE @instance_compat
        WHEN 170 THEN 'See SQL Server 2025 documentation for compat level 170 changes'
        WHEN 160 THEN 'Parameter-sensitive plan optimization, DOP feedback, CE model 160'
        WHEN 150 THEN 'Scalar UDF inlining, table variable deferred compilation, batch mode on rowstore'
        WHEN 140 THEN 'Batch mode memory grant feedback, interleaved execution, adaptive joins'
        WHEN 130 THEN 'Live query statistics, DML with OUTPUT INTO reads inserted'
        ELSE NULL
    END                     AS features_unlocked_at_native_compat
FROM sys.databases d
WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
  AND d.state = 0
ORDER BY d.compatibility_level, d.name;
