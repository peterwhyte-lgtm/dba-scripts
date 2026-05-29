/*
Script Name : Get-MemoryConfiguration
Category    : configuration-and-environment
Purpose     : Review min/max server memory configuration and available physical memory status.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    name,
    value_in_use,
    value
FROM sys.configurations
WHERE name IN ('max server memory (MB)', 'min server memory (MB)', 'optimize for ad hoc workloads');

SELECT
    total_physical_memory_kb / 1024 AS total_physical_memory_mb,
    available_physical_memory_kb / 1024 AS available_physical_memory_mb,
    system_memory_state_desc
FROM sys.dm_os_sys_memory;




