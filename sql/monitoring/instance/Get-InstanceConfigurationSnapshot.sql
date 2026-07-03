/*
Script Name : Get-InstanceConfigurationSnapshot
Category    : configuration-and-environment
Purpose     : Capture all sp_configure settings for baseline review and change tracking.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    name,
    value         AS configured_value,
    value_in_use  AS running_value,
    minimum,
    maximum,
    description,
    CASE WHEN value <> value_in_use THEN 1 ELSE 0 END AS pending_restart
FROM sys.configurations
ORDER BY name;
