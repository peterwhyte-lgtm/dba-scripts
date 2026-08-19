/*
Script Name : Get-AgFailoverReadiness
Category    : high-availability
Purpose     : Per-AG, per-database failover readiness with quantified RPO and RTO estimates.
              Answers "would a failover succeed RIGHT NOW and what would it cost?"
              RTO = estimated seconds to drain redo queue at current redo rate.
              RPO = log send queue size (data that would be lost if primary fails now).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/)
Requires    : VIEW SERVER STATE, VIEW ANY DATABASE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT 'This instance is not a member of an Availability Group (or AG feature is disabled).' AS info;
END
ELSE
BEGIN
    WITH ag_readiness AS (
    SELECT
        ag.name AS ag_name,
        ar.replica_server_name,
        agl.dns_name AS listener_name,
        agl.port AS listener_port,
        DB_NAME(drs.database_id) AS database_name,
        drs.is_local,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc AS replica_health,
        drs.synchronization_state_desc AS db_sync_state,
        drs.database_state_desc,
        -- RPO exposure: data that could be lost if primary fails right now
        drs.log_send_queue_size AS log_send_queue_kb,
        CAST(drs.log_send_queue_size / 1024.0 AS DECIMAL(10,2)) AS log_send_queue_mb,
        -- RTO estimate: seconds to drain the redo queue at current redo rate
        drs.redo_queue_size AS redo_queue_kb,
        CAST(drs.redo_queue_size / 1024.0 AS DECIMAL(10,2)) AS redo_queue_mb,
        drs.redo_rate AS redo_rate_kb_per_sec,
        CASE
            WHEN drs.redo_rate > 0 AND drs.redo_queue_size > 0
            THEN CAST(drs.redo_queue_size / drs.redo_rate AS INT)
            ELSE NULL
        END AS estimated_rto_seconds,
        drs.secondary_lag_seconds,
        drs.last_hardened_time,
        drs.last_received_time,
        -- Readiness: SYNCHRONIZED = ready for synchronous failover
        -- (is_failover_ready removed in SQL 2022+; derived from sync state)
        -- COLLATE DATABASE_DEFAULT on catalog columns avoids collation conflicts with literals
        CASE
            WHEN ars.role_desc COLLATE DATABASE_DEFAULT = 'PRIMARY'
            THEN 'PRIMARY - this is the source'
            WHEN drs.database_state_desc COLLATE DATABASE_DEFAULT <> 'ONLINE'
            THEN 'CRITICAL - database is ' + (drs.database_state_desc COLLATE DATABASE_DEFAULT) + ' on this replica'
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZED'
                 AND ar.availability_mode_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONOUS_COMMIT'
            THEN 'OK - SYNCHRONIZED; ready for automatic/manual failover (zero data loss)'
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZING'
                 AND drs.redo_rate > 0
                 AND drs.redo_queue_size / drs.redo_rate < 60
            THEN 'OK - SYNCHRONIZING; est. RTO ' +
                 CAST(drs.redo_queue_size / NULLIF(drs.redo_rate, 0) AS VARCHAR) + 's to drain redo queue'
            WHEN drs.redo_queue_size > 1048576
            THEN 'WARN - redo queue > 1 GB; RTO will be minutes at best'
            WHEN ar.availability_mode_desc COLLATE DATABASE_DEFAULT = 'ASYNCHRONOUS_COMMIT'
            THEN 'INFO - async replica; manual forced failover only (data loss likely: ' +
                 CAST(CAST(drs.log_send_queue_size / 1024.0 AS INT) AS VARCHAR) + ' MB RPO exposure)'
            ELSE 'INFO - ' + (drs.synchronization_state_desc COLLATE DATABASE_DEFAULT)
        END AS readiness_status,
        -- Numeric sort key avoids collation conflict in ORDER BY string comparison
        CASE
            WHEN ars.role_desc COLLATE DATABASE_DEFAULT = 'PRIMARY' THEN 5
            WHEN drs.database_state_desc COLLATE DATABASE_DEFAULT <> 'ONLINE' THEN 1
            WHEN drs.redo_queue_size > 1048576 THEN 2
            WHEN drs.synchronization_state_desc COLLATE DATABASE_DEFAULT = 'SYNCHRONIZED' THEN 4
            ELSE 3
        END AS sort_priority,
        ar.availability_mode_desc COLLATE DATABASE_DEFAULT AS commit_mode,
        ar.failover_mode_desc COLLATE DATABASE_DEFAULT AS failover_mode
    FROM sys.availability_groups AS ag
    JOIN sys.availability_replicas AS ar ON ar.group_id = ag.group_id
    JOIN sys.dm_hadr_availability_replica_states AS ars ON ars.replica_id = ar.replica_id
    JOIN sys.dm_hadr_database_replica_states AS drs ON drs.replica_id = ar.replica_id
    LEFT JOIN sys.availability_group_listeners AS agl ON agl.group_id = ag.group_id
    )
    SELECT * FROM ag_readiness
    ORDER BY sort_priority, ag_name, database_name, replica_server_name;
END;
