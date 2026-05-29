/*
Script Name : Get-MemoryConfiguration
Description : Returns Memory Configuration for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Review memory configuration and basic usage counters.
-- Useful for baseline reviews and capacity planning.

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




