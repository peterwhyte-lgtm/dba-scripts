/*
Script Name : Get-MemoryConfiguration
Category    : configuration-and-environment
Purpose     : Show configured memory limits alongside current OS-level memory availability.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    (SELECT value_in_use FROM sys.configurations WHERE name = 'min server memory (MB)')         AS min_server_memory_mb,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max server memory (MB)')         AS max_server_memory_mb,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'optimize for ad hoc workloads')  AS optimize_for_ad_hoc,
    sm.total_physical_memory_kb     / 1024                                                      AS total_physical_memory_mb,
    sm.available_physical_memory_kb / 1024                                                      AS available_physical_memory_mb,
    sm.system_memory_state_desc
FROM sys.dm_os_sys_memory AS sm;
