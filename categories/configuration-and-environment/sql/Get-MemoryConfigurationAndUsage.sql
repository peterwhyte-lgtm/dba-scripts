/*
Script Name : Get Memory Configuration and Usage
Description : Returns Memory Configuration And Usage for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

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



