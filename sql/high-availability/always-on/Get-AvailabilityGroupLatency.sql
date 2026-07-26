/*
Script Name : Get-AvailabilityGroupLatency
Category    : high-availability
Purpose     : Display AG replica synchronization timing, queue health, and replication rates.
Author      : Peter Whyte (https://sqldba.blog/script-check-always-on-availability-group-latency/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/script-check-always-on-availability-group-latency/
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
    ars.role_desc,
    DB_NAME(drs.database_id)         AS database_name,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.log_send_queue_size,
    drs.log_send_rate,
    drs.redo_queue_size,
    drs.redo_rate
FROM sys.dm_hadr_database_replica_states    AS drs
INNER JOIN sys.availability_replicas        AS ar  ON ar.replica_id  = drs.replica_id
INNER JOIN sys.availability_groups          AS ag  ON ag.group_id    = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states AS ars ON ars.replica_id = ar.replica_id
ORDER BY ag.name, database_name, ar.replica_server_name;

END

