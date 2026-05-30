/*
Script Name : Get-MissingIndexes
Category    : performance-troubleshooting
Purpose     : Missing index candidates from DMVs, ranked by impact score (seeks x cost x impact).
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE, VIEW ANY DATABASE
Notes       : Impact scores reset on SQL Server restart. Review carefully — DMVs suggest
              individual queries; creating every suggestion causes index bloat and write overhead.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    mid.statement                                                                       AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    CAST(migs.avg_total_user_cost   AS DECIMAL(10,2))                                  AS avg_query_cost,
    CAST(migs.avg_user_impact       AS DECIMAL(5,1))                                   AS avg_improvement_pct,
    CAST(migs.user_seeks * migs.avg_total_user_cost * migs.avg_user_impact / 100.0
         AS DECIMAL(14,0))                                                              AS impact_score,
    'CREATE INDEX [ix_missing_' + REPLACE(REPLACE(ISNULL(mid.equality_columns,'') +
        ISNULL('_' + mid.inequality_columns,''), '[',''), ']','') + ']'
    + ' ON ' + mid.statement
    + ' (' + ISNULL(mid.equality_columns,'')
    + CASE WHEN mid.inequality_columns IS NOT NULL THEN
        CASE WHEN mid.equality_columns IS NOT NULL THEN ', ' ELSE '' END
        + mid.inequality_columns ELSE '' END + ')'
    + CASE WHEN mid.included_columns IS NOT NULL
        THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END
    + ';'                                                                               AS suggested_statement
FROM sys.dm_db_missing_index_group_stats AS migs
JOIN sys.dm_db_missing_index_groups      AS mig  ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details     AS mid  ON mig.index_handle  = mid.index_handle
ORDER BY impact_score DESC;
