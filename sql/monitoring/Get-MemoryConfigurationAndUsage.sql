/*
Script Name : Get-MemoryConfigurationAndUsage
Category    : configuration-and-environment
Purpose     : Show configured memory limits alongside current SQL Server memory consumption.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    (SELECT value_in_use FROM sys.configurations WHERE name = 'min server memory (MB)') AS min_server_memory_mb,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)') AS max_server_memory_mb,
    CAST(osi.physical_memory_kb / 1024.0 / 1024 AS DECIMAL(10,2))                      AS server_physical_memory_gb,
    pm.physical_memory_in_use_kb / 1024                                                 AS sql_memory_in_use_mb,
    pm.large_page_allocations_kb / 1024                                                 AS large_page_allocations_mb,
    pm.locked_page_allocations_kb / 1024                                                AS locked_page_allocations_mb,
    pm.total_virtual_address_space_kb / 1024                                            AS total_virtual_address_mb,
    CAST(osi.committed_kb / 1024.0 AS DECIMAL(12,2))                                   AS sql_committed_mb,
    osi.sqlserver_start_time                                                             AS sql_start_time
FROM sys.dm_os_process_memory AS pm
CROSS JOIN sys.dm_os_sys_info AS osi;
