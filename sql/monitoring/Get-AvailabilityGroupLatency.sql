/*
Script Name : Get-AvailabilityGroupLatency
Category    : high-availability-and-disaster-recovery
Purpose     : Display AG replica synchronization timing, queue health, and replication rates.
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
    DB_NAME(drs.database_id) AS database_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.log_send_queue_size,
    drs.log_send_rate,
    drs.redo_queue_size,
    drs.redo_rate
FROM sys.dm_hadr_database_replica_states AS drs
INNER JOIN sys.availability_replicas AS ar
    ON drs.replica_id = ar.replica_id
INNER JOIN sys.availability_groups AS ag
    ON ar.group_id = ag.group_id
ORDER BY ag.name, database_name, ar.replica_server_name;





