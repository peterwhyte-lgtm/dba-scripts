/*
Script Name : Test-MaxdopRecommendation
Category    : lab
Purpose     : Prove the recommended_maxdop logic in Get-MaxdopConfiguration against every
              branch of Microsoft's published guidance table, not just the topology this
              machine happens to have.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-maxdop-configuration/)
Requires    : Nothing. Reads no server state, it feeds synthetic topologies through the CASE.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
--
-- The lab is 1 NUMA node with 8 logical processors, which exercises exactly ONE of the four
-- branches. A rule that is only ever run against the case it happens to satisfy is not tested.
-- Every `expected` value below is hand-derived from Microsoft's 2016+ table, so a change to
-- the CASE that breaks the multi-NUMA halving shows up here rather than in a reader's output.
SET NOCOUNT ON;

;WITH topology(label, cpu_count, numa_node_count, expected) AS (
    SELECT 'single NUMA, 4 logical  (<=8, use count)',        4,  1,  4  UNION ALL
    SELECT 'single NUMA, 8 logical  (<=8, use count)',        8,  1,  8  UNION ALL
    SELECT 'single NUMA, 24 logical (>8, cap 8)',            24,  1,  8  UNION ALL
    SELECT 'multi NUMA, 2x8=16      (<=16/node, use node)',  16,  2,  8  UNION ALL
    SELECT 'multi NUMA, 2x16=32     (<=16/node, use node)',  32,  2, 16  UNION ALL
    SELECT 'multi NUMA, 2x20=40     (>16/node, half=10)',    40,  2, 10  UNION ALL
    SELECT 'multi NUMA, 4x24=96     (>16/node, half=12)',    96,  4, 12  UNION ALL
    SELECT 'multi NUMA, 2x40=80     (>16/node, half=20>16)', 80,  2, 16
)
SELECT
    label,
    cpu_count,
    numa_node_count,
    expected,
    CASE
        WHEN numa_node_count <= 1 THEN
            CASE WHEN cpu_count <= 8 THEN cpu_count ELSE 8 END
        ELSE
            CASE
                WHEN cpu_count / numa_node_count <= 16
                    THEN cpu_count / numa_node_count
                ELSE CASE WHEN (cpu_count / numa_node_count) / 2 > 16
                          THEN 16
                          ELSE (cpu_count / numa_node_count) / 2 END
            END
    END AS computed,
    CASE WHEN expected =
        CASE
            WHEN numa_node_count <= 1 THEN
                CASE WHEN cpu_count <= 8 THEN cpu_count ELSE 8 END
            ELSE
                CASE
                    WHEN cpu_count / numa_node_count <= 16
                        THEN cpu_count / numa_node_count
                    ELSE CASE WHEN (cpu_count / numa_node_count) / 2 > 16
                              THEN 16
                              ELSE (cpu_count / numa_node_count) / 2 END
                END
        END
    THEN 'PASS' ELSE '*** FAIL ***' END AS result
FROM topology;
