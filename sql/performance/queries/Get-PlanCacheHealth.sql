/*
Script Name : Get-PlanCacheHealth
Category    : performance
Purpose     : Summarises plan cache composition by object type — highlights single-use
              plan bloat, ad-hoc SQL pressure, and total memory consumption. High
              single-use percentages indicate parameter sniffing or missing parameterisation.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-query-performance-deep-dive/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Three sections:
    1. By plan type — aggregate counts, single-use ratio, memory per objtype
    2. Top memory-consuming single-use ad-hoc plans — worst offenders for cleanup
    3. Overall cache health indicators
  Single-use plans (usecounts = 1) waste cache memory and indicate ad-hoc workloads.
  Remedies: OPTIMIZE FOR AD HOC WORKLOADS, sp_executesql, or forced parameterisation.
*/

-- 1. By plan type
SELECT
    cp.objtype AS plan_type,
    COUNT(*) AS plan_count,
    SUM(cp.usecounts) AS total_use_count,
    SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END) AS single_use_plan_count,
    CAST(
        100.0 * SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
    AS decimal(5,1)) AS single_use_pct,
    CAST(SUM(cp.size_in_bytes) / 1048576.0 AS decimal(10,1)) AS total_mb,
    CAST(SUM(CASE WHEN cp.usecounts = 1 THEN cp.size_in_bytes ELSE 0 END) / 1048576.0 AS decimal(10,1)) AS single_use_mb,
    CASE
        WHEN CAST(
                100.0 * SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END)
                / NULLIF(COUNT(*), 0)
             AS decimal(5,1)) > 60
            AND cp.objtype = 'Adhoc'
            THEN 'WARN - high ad-hoc single-use ratio; consider OPTIMIZE FOR AD HOC WORKLOADS'
        ELSE 'OK'
    END AS recommendation
FROM sys.dm_exec_cached_plans cp
GROUP BY cp.objtype
ORDER BY total_mb DESC;
