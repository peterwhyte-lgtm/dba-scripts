/*
Script Name : Get-MissingIndexes
Category    : performance-troubleshooting
Purpose     : Identify candidate missing indexes from DMVs for performance tuning.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE, VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Index suggestions are guidance only. Review carefully before creating any index.

SELECT
    mig.index_group_handle,
    mig.index_handle,
    mid.statement,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_group_stats migs
JOIN sys.dm_db_missing_index_groups mig ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
ORDER BY migs.avg_user_impact DESC, migs.user_seeks DESC;




