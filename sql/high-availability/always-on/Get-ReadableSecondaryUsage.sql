/*
Script Name : Get-ReadableSecondaryUsage
Category    : high-availability
Purpose     : Shows Availability Group replica connection modes and read-only routing
              configuration. Identifies which replicas allow readable secondary access
              and whether routing is configured. Returns a status row on standalone
              instances (no AG).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-ag-failover-readiness-and-readable-secondary-usage/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
BEGIN
    SELECT
        GETDATE() AS collection_time,
        @@SERVERNAME AS server_name,
        'NO_AG' AS ag_name,
        NULL AS replica_server_name,
        NULL AS role_desc,
        NULL AS secondary_role_allow_connections_desc,
        NULL AS read_only_routing_url,
        NULL AS connected_state_desc,
        NULL AS synchronization_health_desc,
        NULL AS redo_queue_kb,
        NULL AS routing_configured;
    RETURN;
END

SELECT
    GETDATE() AS collection_time,
    @@SERVERNAME AS server_name,
    ag.name AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    ar.secondary_role_allow_connections_desc,
    ar.read_only_routing_url,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    drs_agg.total_redo_queue_kb,
    CASE
        WHEN ar.secondary_role_allow_connections_desc IN ('READ_ONLY', 'ALL')
             AND ar.read_only_routing_url IS NOT NULL
            THEN 'Yes — connections and routing configured'
        WHEN ar.secondary_role_allow_connections_desc IN ('READ_ONLY', 'ALL')
             AND ar.read_only_routing_url IS NULL
            THEN 'Partial — readable but no routing URL set'
        ELSE 'No — secondary not configured for reads'
    END AS routing_configured
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ars.replica_id = ar.replica_id
OUTER APPLY (
    SELECT SUM(drs.redo_queue_size) AS total_redo_queue_kb
    FROM sys.dm_hadr_database_replica_states drs
    WHERE drs.replica_id = ar.replica_id
) drs_agg
ORDER BY ag.name, ars.role_desc DESC, ar.replica_server_name;
