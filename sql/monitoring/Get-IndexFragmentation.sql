/*
Script Name : Get-IndexFragmentation
Category    : maintenance-and-reliability
Purpose     : Indexes with significant fragmentation (>= 10%, >= 1000 pages) with recommended action.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW DATABASE STATE
Notes       : Run against the target database. Fragmentation on tables under 1000 pages
              is unlikely to affect query performance — those are excluded.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    s.name                                                          AS schema_name,
    t.name                                                          AS table_name,
    i.name                                                          AS index_name,
    i.type_desc                                                     AS index_type,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1))         AS fragmentation_pct,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= 10 THEN 'REORGANIZE'
    END                                                             AS recommended_action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
JOIN sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables  AS t ON i.object_id   = t.object_id
JOIN sys.schemas AS s ON t.schema_id   = s.schema_id
WHERE i.name IS NOT NULL
  AND ips.page_count                  >= 1000
  AND ips.avg_fragmentation_in_percent >= 10
ORDER BY ips.avg_fragmentation_in_percent DESC;
