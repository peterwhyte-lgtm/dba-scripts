/*
Script Name : Get-OsConfigurationChecks
Category    : monitoring
Purpose     : DMV-accessible OS and hardware configuration checks: Lock Pages in Memory,
              NUMA topology, scheduler affinity, and Instant File Initialization (SQL 2019+).
              Surfaces common misconfigurations invisible from inside SQL Server.
              Pair with Test-OsConfiguration.ps1 for power plan and page file checks.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-cpu-topology-and-os-config/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-cpu-topology-and-os-config/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH numa_summary AS (
    SELECT
        COUNT(DISTINCT node_id) AS numa_node_count,
        SUM(online_scheduler_count) AS online_schedulers
    FROM sys.dm_os_nodes
    WHERE node_state_desc NOT LIKE '%DAC%'
),
offline_schedulers AS (
    SELECT COUNT(*) AS offline_count
    FROM sys.dm_os_schedulers
    WHERE status = 'VISIBLE OFFLINE'
      AND scheduler_id < 255
),
cfg AS (
    SELECT
        MAX(CASE WHEN name = 'max server memory (MB)' THEN CAST(value_in_use AS BIGINT) END) AS max_server_memory_mb,
        MAX(CASE WHEN name = 'min server memory (MB)' THEN CAST(value_in_use AS BIGINT) END) AS min_server_memory_mb
    FROM sys.configurations
)
SELECT
    osi.cpu_count AS logical_cpu_count,
    osi.cpu_count / NULLIF(osi.hyperthread_ratio, 0) AS physical_cpu_count,
    osi.hyperthread_ratio AS cores_per_socket,
    n.numa_node_count,
    n.online_schedulers AS sql_online_schedulers,
    os_off.offline_count AS sql_offline_schedulers,
    CASE
        WHEN os_off.offline_count > 0
        THEN 'WARN — ' + CAST(os_off.offline_count AS VARCHAR) +
             ' scheduler(s) offline; CPU affinity mask may be limiting SQL Server'
        ELSE 'OK'
    END AS scheduler_status,
    CASE
        WHEN n.numa_node_count > (osi.cpu_count / NULLIF(osi.hyperthread_ratio, 0))
        THEN 'INFO — soft-NUMA active (' + CAST(n.numa_node_count AS VARCHAR) +
             ' SQL NUMA nodes vs ' + CAST(osi.cpu_count / NULLIF(osi.hyperthread_ratio, 0) AS VARCHAR) + ' sockets)'
        WHEN n.numa_node_count = 1 AND osi.cpu_count > 8
        THEN 'INFO — single NUMA node with ' + CAST(osi.cpu_count AS VARCHAR) +
             ' CPUs; consider soft-NUMA for NUMA-aware memory allocation'
        ELSE 'OK'
    END AS numa_status,
    osi.sql_memory_model_desc AS memory_model,
    CASE osi.sql_memory_model_desc
        WHEN 'CONVENTIONAL'
        THEN 'WARN — LPIM not active; OS can page out SQL buffer pool under memory pressure'
        WHEN 'LOCK_PAGES' THEN 'OK — Lock Pages in Memory is active'
        WHEN 'LARGE_PAGES' THEN 'OK — Large Pages active (implies LPIM)'
        ELSE 'UNKNOWN'
    END AS lpim_status,
    CAST(osi.physical_memory_kb / 1024.0 / 1024 AS DECIMAL(10,2)) AS physical_memory_gb,
    c.max_server_memory_mb,
    c.min_server_memory_mb,
    CAST(osi.physical_memory_kb / 1024 -
         CASE WHEN osi.physical_memory_kb / 1024 > 16384 THEN 4096
              WHEN osi.physical_memory_kb / 1024 > 4096 THEN 2048
              ELSE 1024 END AS BIGINT) AS recommended_max_mem_mb,
    CASE
        WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15
        THEN ISNULL(
                (SELECT TOP 1 CAST(instant_file_initialization_enabled AS NVARCHAR(5))
                 FROM sys.dm_server_services
                 WHERE servicename LIKE 'SQL Server (%'
                   AND filename NOT LIKE '%sqlagent%'
                   AND filename NOT LIKE '%OLAP%'),
                'N/A')
        ELSE 'N/A (pre-2019)'
    END AS ifi_enabled,
    CASE
        WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15
             AND EXISTS (
                SELECT 1 FROM sys.dm_server_services
                WHERE servicename LIKE 'SQL Server (%'
                  AND filename NOT LIKE '%sqlagent%'
                  AND instant_file_initialization_enabled = 'Y')
        THEN 'OK — IFI active; autogrowth and data file creation do not zero pages'
        WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15
        THEN 'WARN — IFI not enabled; autogrowth events stall while OS zeroes pages'
        ELSE 'INFO — IFI cannot be confirmed via SQL on pre-2019 instances; verify SE_MANAGE_VOLUME_NAME Windows privilege'
    END AS ifi_status,
    osi.sqlserver_start_time AS sql_start_time,
    DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()) AS uptime_days
FROM sys.dm_os_sys_info AS osi
CROSS JOIN numa_summary AS n
CROSS JOIN offline_schedulers AS os_off
CROSS JOIN cfg AS c;
