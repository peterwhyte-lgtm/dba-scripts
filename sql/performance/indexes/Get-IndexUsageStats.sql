/*
Script Name : Get-IndexUsageStats
Category    : performance-troubleshooting
Purpose     : Show how indexes across all user databases are being used — seeks, scans, lookups, updates.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-index-usage-stats/)
Requires    : VIEW SERVER STATE, VIEW ANY DATABASE
Notes       : Usage counters reset on SQL Server restart. High user_updates with low reads =
              candidate for removal. high user_scans = possible missing index on that table.
*/
-- Blog: https://sqldba.blog/dba-scripts-get-index-usage-stats/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    DB_NAME(ius.database_id)                                                AS database_name,
    OBJECT_SCHEMA_NAME(ius.object_id, ius.database_id)                     AS schema_name,
    OBJECT_NAME(ius.object_id, ius.database_id)                            AS table_name,
    ius.index_id,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.user_seeks + ius.user_scans + ius.user_lookups                      AS total_reads,
    CASE
        WHEN ius.user_seeks + ius.user_scans + ius.user_lookups = 0
         AND ius.user_updates > 0
            THEN 'WRITE_ONLY'
        WHEN ius.user_scans > ius.user_seeks * 10
            THEN 'SCAN_HEAVY'
        ELSE 'NORMAL'
    END                                                                     AS usage_pattern,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_update
FROM sys.dm_db_index_usage_stats AS ius
WHERE ius.database_id > 4
ORDER BY ius.user_updates DESC, total_reads DESC;
