/*
Script Name : Get-AvailabilityGroupReplicaState
Category    : high-availability-and-disaster-recovery
Purpose     : Show AG replica health, connection state, and synchronization status for failover readiness.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low


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
FROM sys.availability_replicas AS ar
INNER JOIN sys.availability_groups AS ag
    ON ar.group_id = ag.group_id
ORDER BY ag.name, ar.replica_server_name;





