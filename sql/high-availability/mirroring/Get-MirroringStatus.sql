/*
Script Name : Get-MirroringStatus
Category    : high-availability
Purpose     : Shows health, state, and point-in-time latency for all mirrored databases on this
              instance. Run on the principal server. Reports operating mode, mirroring state,
              database size, log send queue, and redo queue.
              Note: Database Mirroring has been deprecated since SQL Server 2012. Always On
              Availability Groups are the supported replacement for new deployments.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/)
Requires    : VIEW SERVER STATE, VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256)) AS principal_server,
    m.mirroring_partner_instance AS mirror_server,
    DB_NAME(m.database_id) AS database_name,
    CAST(SUM(f.size * 8 / 1024.0 / 1024) AS DECIMAL(10,1)) AS database_size_gb,
    CASE m.mirroring_safety_level
        WHEN 1 THEN 'High Performance'
        WHEN 2 THEN 'High Safety'
        ELSE 'Unknown'
    END AS operating_mode,
    CASE m.mirroring_state
        WHEN 0 THEN 'Suspended'
        WHEN 1 THEN 'Disconnected'
        WHEN 2 THEN 'Synchronizing'
        WHEN 3 THEN 'Pending Failover'
        WHEN 4 THEN 'Synchronized'
        ELSE 'Unknown'
    END AS mirroring_state,
    m.mirroring_role_desc AS role,
    m.mirroring_witness_name AS witness_server,
    perf.log_send_queue_kb,
    perf.redo_queue_kb,
    RIGHT(
        m.mirroring_partner_name,
        CHARINDEX(':', REVERSE(m.mirroring_partner_name) + ':') - 1
    ) AS endpoint_port
FROM sys.database_mirroring m
JOIN sys.master_files f ON f.database_id = m.database_id
OUTER APPLY (
    SELECT
        MAX(CASE WHEN counter_name = N'Log Send Queue KB' THEN cntr_value END) AS log_send_queue_kb,
        MAX(CASE WHEN counter_name = N'Redo Queue KB' THEN cntr_value END) AS redo_queue_kb
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE N'%Database Mirroring%'
      AND instance_name = DB_NAME(m.database_id)
) perf
WHERE m.mirroring_guid IS NOT NULL
  AND m.mirroring_role_desc = N'PRINCIPAL'
GROUP BY
    m.database_id,
    m.mirroring_partner_instance,
    m.mirroring_safety_level,
    m.mirroring_state,
    m.mirroring_role_desc,
    m.mirroring_partner_name,
    m.mirroring_witness_name,
    perf.log_send_queue_kb,
    perf.redo_queue_kb
ORDER BY DB_NAME(m.database_id);
