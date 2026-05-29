/*
Script Name : Get SQL Server Version and Edition
Description : Returns Version And Edition for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    SERVERPROPERTY('MachineName') AS machine_name,
    SERVERPROPERTY('ServerName') AS server_name,
    SERVERPROPERTY('InstanceName') AS instance_name,
    SERVERPROPERTY('ProductVersion') AS product_version,
    SERVERPROPERTY('ProductLevel') AS product_level,
    SERVERPROPERTY('Edition') AS edition,
    SERVERPROPERTY('IsClustered') AS is_clustered;



