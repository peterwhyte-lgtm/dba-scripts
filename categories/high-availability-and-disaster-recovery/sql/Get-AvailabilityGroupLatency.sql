/*
Script Name : Get-AvailabilityGroupLatency
Description : Returns Availability Group Latency for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Quick AG latency review for replica health and synchronization timing.
-- Useful for HA/DR troubleshooting and failover readiness checks.

SELECT
    ag.name AS ag_name,
    ar.replica_server_name,
    ar.role_desc,
    drs.database_id,
    db_name(drs.database_id) AS database_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.log_send_queue_size,
    drs.log_send_rate,
    drs.redo_queue_size,
    drs.redo_rate
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id;




