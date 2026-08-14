/*
Script Name : Get-DeprecatedFeaturesInUse
Category    : migration
Purpose     : Lists deprecated SQL Server features used since the last service restart, ranked by usage count. Zero rows means no deprecated features have been called.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-version-upgrade-readiness/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    pc.instance_name AS deprecated_feature,
    pc.cntr_value AS usage_count_since_restart,
    CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(20)) AS instance_version,
    CAST(SERVERPROPERTY('ProductLevel') AS VARCHAR(20)) AS product_level,
    si.sqlserver_start_time AS last_restart,
    DATEDIFF(DAY, si.sqlserver_start_time, GETDATE()) AS days_since_restart
FROM sys.dm_os_performance_counters pc
CROSS JOIN (
    SELECT sqlserver_start_time FROM sys.dm_os_sys_info
) si
WHERE pc.object_name LIKE '%Deprecated Features%'
  AND pc.cntr_value > 0
ORDER BY pc.cntr_value DESC, pc.instance_name;
