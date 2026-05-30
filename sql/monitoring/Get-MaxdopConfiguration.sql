/*
Script Name : Get-MaxdopConfiguration
Category    : configuration-and-environment
Purpose     : Show MAXDOP and cost threshold settings alongside current CPU topology.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism')     AS maxdop,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism') AS cost_threshold_for_parallelism,
    osi.cpu_count                                                                               AS logical_cpu_count,
    osi.hyperthread_ratio,
    osi.cpu_count / osi.hyperthread_ratio                                                       AS physical_cpu_count,
    osi.scheduler_count                                                                         AS online_schedulers,
    osi.numa_node_count
FROM sys.dm_os_sys_info AS osi;
