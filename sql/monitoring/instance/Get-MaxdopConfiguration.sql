/*
Script Name : Get-MaxdopConfiguration
Category    : configuration-and-environment
Purpose     : Show MAXDOP and cost threshold settings alongside current CPU topology.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-maxdop-configuration/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* RECOMMENDED MAXDOP IS COMPUTED, NOT GUESSED. The rule below is Microsoft's published table
   on "Configure the max degree of parallelism Server Configuration Option", for SQL Server
   2016 and later, verified against the live page 2026-09-01:

     single NUMA node, <= 8 logical processors  -> at or under the logical processor count
     single NUMA node,  > 8 logical processors  -> 8
     multiple NUMA nodes, <= 16 per node        -> at or under the logical processors per node
     multiple NUMA nodes,  > 16 per node        -> half the processors per node, capped at 16

   NOTE the 2016 change. Through SQL Server 2014 the multi-NUMA branch simply capped at 8, and
   a great deal of advice still in circulation quotes that older table. This computes the
   CURRENT rule.

   Cost threshold deliberately gets no recommended number. Microsoft does not publish one:
   "The default value of 5 is a starting point, not a recommendation. On modern SQL Server
   systems, raising it can help to keep smaller OLTP queries executing with serial plans."
   The widely repeated "set it to 50" is community advice, not documentation, so this script
   reports the value and says whether it is still the default rather than inventing a target. */
SELECT
    (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism')     AS maxdop,
    (SELECT value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism') AS cost_threshold_for_parallelism,
    osi.cpu_count                                                                               AS logical_cpu_count,
    osi.hyperthread_ratio,
    osi.cpu_count / osi.hyperthread_ratio                                                       AS physical_cpu_count,
    osi.scheduler_count                                                                         AS online_schedulers,
    osi.numa_node_count,
    osi.cpu_count / NULLIF(osi.numa_node_count, 0)                                              AS logical_cpus_per_numa_node,
    CASE
        WHEN osi.numa_node_count <= 1 THEN
            CASE WHEN osi.cpu_count <= 8 THEN osi.cpu_count ELSE 8 END
        ELSE
            CASE
                WHEN osi.cpu_count / osi.numa_node_count <= 16
                    THEN osi.cpu_count / osi.numa_node_count
                ELSE CASE WHEN (osi.cpu_count / osi.numa_node_count) / 2 > 16
                          THEN 16
                          ELSE (osi.cpu_count / osi.numa_node_count) / 2 END
            END
    END                                                                                         AS recommended_maxdop,
    CASE
        WHEN (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism')
             = CASE
                 WHEN osi.numa_node_count <= 1 THEN
                     CASE WHEN osi.cpu_count <= 8 THEN osi.cpu_count ELSE 8 END
                 ELSE
                     CASE
                         WHEN osi.cpu_count / osi.numa_node_count <= 16
                             THEN osi.cpu_count / osi.numa_node_count
                         ELSE CASE WHEN (osi.cpu_count / osi.numa_node_count) / 2 > 16
                                   THEN 16
                                   ELSE (osi.cpu_count / osi.numa_node_count) / 2 END
                     END
               END
        THEN 'OK: matches the current Microsoft guidance table'
        WHEN (SELECT value_in_use FROM sys.configurations WHERE name = 'max degree of parallelism') = 0
        THEN 'REVIEW: MAXDOP 0 lets one query use every processor. Microsoft: not recommended for most cases'
        ELSE 'REVIEW: does not match the guidance table for this CPU topology'
    END                                                                                         AS maxdop_verdict,
    CASE
        WHEN (SELECT value_in_use FROM sys.configurations WHERE name = 'cost threshold for parallelism') = 5
        THEN 'REVIEW: still the default 5. Microsoft calls 5 "a starting point, not a recommendation"'
        ELSE 'OK: moved off the default. Microsoft publishes no target value, so tune and measure'
    END                                                                                         AS cost_threshold_verdict
FROM sys.dm_os_sys_info AS osi;
