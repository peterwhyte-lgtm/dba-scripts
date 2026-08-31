/*
Script Name : Get-ResourceGovernorConfig
Category    : monitoring
Purpose     : Resource Governor configuration, enabled state, resource pools, workload groups,
              and classifier function. An active but misconfigured RG can silently throttle
              queries or starve the DBA's own sessions on an inherited server.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-trace-flags-and-resource-governor/)
Requires    : VIEW SERVER STATE
Notes       : The classifier function lives in master (Microsoft require it), so the OBJECT_NAME
              and OBJECT_SCHEMA_NAME calls below pass DB_ID(N'master') explicitly. Without that
              second argument they resolve against the CURRENT database and the classifier name
              comes back NULL whenever this is run from a user database - which is how most
              people will run it, and it is the column the WARN verdict depends on.

              BLIND SPOT: sys.resource_governor_resource_pools and
              sys.resource_governor_workload_groups are catalog views holding the STORED
              configuration. Microsoft: the matching dm_ views "show the in-memory
              configuration". After an ALTER RESOURCE GOVERNOR without a RECONFIGURE the two
              disagree, and this script reports the stored side. If a pool here does not match
              the behaviour you are seeing, check whether RECONFIGURE was ever run.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    c.is_enabled AS rg_enabled,
    CASE WHEN c.is_enabled = 1 THEN 'ENABLED' ELSE 'DISABLED' END AS rg_state,
    CASE
        WHEN c.classifier_function_id IS NOT NULL
        THEN OBJECT_SCHEMA_NAME(c.classifier_function_id, DB_ID(N'master')) + '.'
             + OBJECT_NAME(c.classifier_function_id, DB_ID(N'master'))
        ELSE NULL
    END AS classifier_function,
    p.name AS pool_name,
    p.min_cpu_percent AS pool_min_cpu_pct,
    p.max_cpu_percent AS pool_max_cpu_pct,
    p.min_memory_percent AS pool_min_mem_pct,
    p.max_memory_percent AS pool_max_mem_pct,
    g.name AS workload_group,
    g.importance AS group_importance,
    g.request_max_cpu_time_sec AS group_max_cpu_sec,
    g.request_max_memory_grant_percent AS group_max_mem_grant_pct,
    g.max_dop AS group_max_dop,
    g.group_max_requests AS group_max_requests,
    rs_g.total_request_count AS group_total_requests,
    rs_g.active_request_count AS group_active_requests,
    CASE
        WHEN c.is_enabled = 0
            THEN 'INFO - Resource Governor is disabled; all sessions use default pool'
        WHEN c.classifier_function_id IS NULL
            THEN 'WARN - RG enabled but no classifier function; all connections go to default pool'
        WHEN p.name = 'default' AND g.name = 'default'
            THEN 'INFO - sessions landing in default pool/group; verify classifier is routing correctly'
        ELSE 'OK'
    END AS status
FROM sys.resource_governor_configuration AS c
CROSS JOIN sys.resource_governor_resource_pools AS p
JOIN sys.resource_governor_workload_groups AS g ON g.pool_id = p.pool_id
LEFT JOIN sys.dm_resource_governor_workload_groups AS rs_g ON rs_g.group_id = g.group_id
ORDER BY
    p.name,
    g.name;
