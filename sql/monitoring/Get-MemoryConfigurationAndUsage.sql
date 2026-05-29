/*
Script Name : Get-MemoryConfigurationAndUsage
Category    : configuration-and-environment
Purpose     : Display configured memory limits and current process memory allocation details.
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
    value_in_use
FROM sys.configurations
WHERE name IN ('min server memory (MB)', 'max server memory (MB)');

SELECT
    physical_memory_in_use_kb / 1024 AS physical_memory_in_use_mb,
    large_page_allocations_kb / 1024 AS large_page_allocations_mb,
    locked_page_allocations_kb / 1024 AS locked_page_allocations_mb,
    total_virtual_address_space_kb / 1024 AS total_virtual_address_space_mb
FROM sys.dm_os_process_memory;



