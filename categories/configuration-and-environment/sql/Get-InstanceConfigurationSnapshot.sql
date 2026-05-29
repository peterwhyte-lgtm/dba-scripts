/*
Script Name : Get-InstanceConfigurationSnapshot
Description : Returns Instance Configuration Snapshot for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Collect a quick instance configuration snapshot for environment review.
-- This is useful for baseline checks, audits, and incident prep.

SELECT
    name,
    value_in_use,
    value,
    description
FROM sys.configurations
ORDER BY name;

SELECT
    SERVERPROPERTY('MachineName') AS machine_name,
    SERVERPROPERTY('InstanceName') AS instance_name,
    SERVERPROPERTY('Edition') AS edition,
    SERVERPROPERTY('ProductVersion') AS product_version,
    SERVERPROPERTY('ProductLevel') AS product_level,
    SERVERPROPERTY('Collation') AS collation_name;




