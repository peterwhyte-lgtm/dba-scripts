/*
Script Name : Check MAXDOP Configuration
Description : Returns Maxdop Configuration for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

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



