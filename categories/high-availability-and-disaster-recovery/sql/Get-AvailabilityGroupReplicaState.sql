/*
Script Name : Get-AvailabilityGroupReplicaState
Description : Returns Availability Group Replica State for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Review Always On AG replica health and synchronization state.
-- Useful for HA/DR checks and failover readiness reviews.

SELECT
    ag.name AS ag_name,
    ar.replica_server_name,
    ar.role_desc,
    ar.operational_state_desc,
    ar.connected_state_desc,
    ar.synchronization_health_desc,
    ar.synchronization_state_desc,
    ar.last_connect_error_number,
    ar.last_connect_error_description,
    ar.last_connect_error_timestamp
FROM sys.availability_replicas ar
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
ORDER BY ag.name, ar.replica_server_name;




