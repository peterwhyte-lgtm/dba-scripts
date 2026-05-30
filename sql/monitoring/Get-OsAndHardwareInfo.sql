/*
Script Name : Get-OsAndHardwareInfo
Category    : configuration-and-environment
Purpose     : Show OS version, hardware specs (CPU, RAM), and SQL Server uptime in one row.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    SERVERPROPERTY('MachineName')                                          AS machine_name,
    SERVERPROPERTY('ServerName')                                           AS server_name,
    SERVERPROPERTY('Edition')                                              AS sql_edition,
    SERVERPROPERTY('ProductVersion')                                       AS sql_version,
    SERVERPROPERTY('ProductLevel')                                         AS sql_product_level,
    SERVERPROPERTY('ProductUpdateLevel')                                   AS sql_cu_level,
    SERVERPROPERTY('IsClustered')                                          AS is_clustered,
    wni.windows_release                                                    AS os_release,
    wni.windows_service_pack_level                                         AS os_service_pack,
    wni.windows_sku                                                        AS os_sku,
    osi.cpu_count                                                          AS logical_cpu_count,
    osi.hyperthread_ratio                                                   AS hyperthread_ratio,
    osi.cpu_count / osi.hyperthread_ratio                                  AS physical_cpu_count,
    CAST(osi.physical_memory_kb / 1024.0 / 1024 AS DECIMAL(10,2))         AS physical_memory_gb,
    CAST(osi.committed_kb / 1024.0 AS DECIMAL(12,2))                      AS sql_committed_mb,
    osi.sqlserver_start_time                                               AS sql_start_time,
    DATEDIFF(DAY,  osi.sqlserver_start_time, GETDATE())                    AS uptime_days,
    DATEDIFF(HOUR, osi.sqlserver_start_time, GETDATE()) % 24              AS uptime_hours_remainder
FROM sys.dm_os_sys_info      AS osi
CROSS JOIN sys.dm_os_windows_info AS wni;
