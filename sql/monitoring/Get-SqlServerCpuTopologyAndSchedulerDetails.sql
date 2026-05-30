/*
Script Name : Get-SqlServerCpuTopologyAndSchedulerDetails
Category    : configuration-and-environment
Purpose     : CPU topology, NUMA layout, scheduler summary, and parallelism configuration in one row.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    SERVERPROPERTY('MachineName')                                                   AS machine_name,
    SERVERPROPERTY('Edition')                                                       AS sql_edition,
    SERVERPROPERTY('ProductVersion')                                                AS sql_version,
    osi.cpu_count                                                                   AS logical_cpu_count,
    osi.hyperthread_ratio,
    osi.cpu_count / osi.hyperthread_ratio                                           AS physical_cpu_count,
    osi.socket_count                                                                AS sockets,
    osi.cores_per_socket,
    osi.numa_node_count,
    osi.scheduler_count                                                             AS online_schedulers,
    osi.scheduler_total_count                                                       AS total_schedulers,
    osi.max_workers_count,
    osi.virtual_machine_type_desc,
    osi.sqlserver_start_time,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism')     AS maxdop,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism') AS cost_threshold,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'affinity mask')                  AS affinity_mask
FROM sys.dm_os_sys_info AS osi;

/*
-- Per-NUMA node detail (run separately in SSMS):
SELECT node_id, node_state_desc, memory_node_id, online_scheduler_count,
       active_worker_count, avg_load_balance
FROM sys.dm_os_nodes
WHERE node_state_desc <> 'ONLINE DAC'
ORDER BY node_id;

-- Per-scheduler detail (run separately in SSMS):
SELECT scheduler_id, parent_node_id, status, is_idle,
       current_tasks_count, runnable_tasks_count, work_queue_count, load_factor
FROM sys.dm_os_schedulers
WHERE scheduler_id < 255 AND status = 'VISIBLE ONLINE'
ORDER BY parent_node_id, scheduler_id;
*/
