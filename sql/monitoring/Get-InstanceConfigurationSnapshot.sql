/*
Script Name : Get-InstanceConfigurationSnapshot
Category    : configuration-and-environment
Purpose     : Capture all sp_configure settings for baseline review and change tracking.
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
    value         AS configured_value,
    value_in_use  AS running_value,
    minimum,
    maximum,
    description,
    CASE WHEN value <> value_in_use THEN 1 ELSE 0 END AS pending_restart
FROM sys.configurations
ORDER BY name;
