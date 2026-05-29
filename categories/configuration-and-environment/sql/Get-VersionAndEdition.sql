/*
Script Name : Get SQL Server Version and Edition
Description : Returns core instance version, edition, and cluster details for operational reviews.
Use        : Patch validation, support checks, and environment reporting.
*/

SELECT
    SERVERPROPERTY('MachineName') AS machine_name,
    SERVERPROPERTY('ServerName') AS server_name,
    SERVERPROPERTY('InstanceName') AS instance_name,
    SERVERPROPERTY('ProductVersion') AS product_version,
    SERVERPROPERTY('ProductLevel') AS product_level,
    SERVERPROPERTY('Edition') AS edition,
    SERVERPROPERTY('BuildClrVersion') AS clr_version,
    SERVERPROPERTY('IsClustered') AS is_clustered,
    SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS physical_hostname;



