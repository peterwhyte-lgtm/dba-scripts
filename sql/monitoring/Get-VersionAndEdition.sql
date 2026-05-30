/*
Script Name : Get-VersionAndEdition
Category    : configuration-and-environment
Purpose     : Display core instance version, edition, cluster status, and patch level.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : Public (no special permissions required)
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

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



