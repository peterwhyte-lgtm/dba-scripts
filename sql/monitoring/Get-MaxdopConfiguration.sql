/*
Script Name : Get-MaxdopConfiguration
Category    : configuration-and-environment
Purpose     : Check MAXDOP configuration settings and CPU topology.
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
    value,
    description
FROM sys.configurations
WHERE name = 'max degree of parallelism';

SELECT
    cpu_count,
    hyperthread_ratio,
    sockets,
    cores_per_socket
FROM sys.dm_os_sys_info;



