/*
Script Name : Get-AvailabilityGroupReplicaState
Category    : high-availability
Purpose     : Show AG replica health, connection state, and synchronization status for failover readiness.
Author      : Peter Whyte (https://sqldba.blog/script-check-ag-replica-role-and-synchronization-state/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/script-check-ag-replica-role-and-synchronization-state/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF SERVERPROPERTY('IsHadrEnabled') = 0
    OR NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT 'Always On Availability Groups is not enabled or no groups are configured on this instance.' AS status;
END
ELSE
BEGIN
    SELECT
        ag.name                          AS ag_name,
        ar.replica_server_name,
        ar.availability_mode_desc        AS commit_mode,
        ar.failover_mode_desc,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc,
        ars.recovery_health_desc,
        ars.last_connect_error_number,
        ars.last_connect_error_description,
        ars.last_connect_error_timestamp
    FROM sys.availability_replicas                      AS ar
    JOIN sys.availability_groups                        AS ag  ON ag.group_id   = ar.group_id
    JOIN sys.dm_hadr_availability_replica_states        AS ars ON ars.replica_id = ar.replica_id
    ORDER BY ag.name, ar.replica_server_name;
END
