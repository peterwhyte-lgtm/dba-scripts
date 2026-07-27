/*
Script Name : Get-DatabaseSnapshotInventory
Category    : monitoring
Purpose     : Lists all database snapshots with source database, age, and allocated size — snapshots silently consume filegroup space if forgotten.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-database-snapshot-inventory/)
Requires    : VIEW ANY DATABASE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-database-snapshot-inventory/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    s.name                                                              AS snapshot_name,
    src.name                                                            AS source_database,
    s.create_date,
    DATEDIFF(DAY, s.create_date, GETDATE())                            AS age_days,
    s.state_desc,
    src.recovery_model_desc,
    CAST(SUM(CAST(f.size AS BIGINT) * 8.0 / 1024) AS DECIMAL(20,2))   AS allocated_mb
FROM sys.databases   s
JOIN sys.databases   src ON src.database_id = s.source_database_id
JOIN sys.master_files f   ON f.database_id  = s.database_id
GROUP BY s.name, src.name, s.create_date, s.state_desc, src.recovery_model_desc
ORDER BY s.create_date ASC;
