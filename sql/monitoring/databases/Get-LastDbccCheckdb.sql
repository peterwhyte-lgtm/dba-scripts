/*
Script Name : Get-LastDbccCheckdb
Category    : maintenance-and-reliability
Purpose     : Show when each user database last had a successful DBCC CHECKDB run.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-last-dbcc-checkdb/)
Requires    : VIEW ANY DATABASE
Notes       : Uses DATABASEPROPERTYEX('LastGoodCheckDbTime') — available SQL Server 2016 SP2+.
              Returns 1900-01-01 (not NULL) when CHECKDB has never completed successfully;
              the script maps that sentinel to NULL / NEVER_RUN.
              Microsoft recommends running CHECKDB at least weekly.
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    d.name                                              AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    x.last_good_checkdb,
    DATEDIFF(DAY, x.last_good_checkdb, GETDATE())       AS days_since_checkdb,
    CASE
        WHEN x.last_good_checkdb IS NULL
            THEN 'NEVER_RUN'
        WHEN DATEDIFF(DAY, x.last_good_checkdb, GETDATE()) > 7
            THEN 'STALE'
        ELSE 'OK'
    END                                                 AS checkdb_status
FROM sys.databases AS d
CROSS APPLY (
    -- LastGoodCheckDbTime reports 1900-01-01 when CHECKDB has never run; treat as NULL
    SELECT NULLIF(
        CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME),
        '19000101') AS last_good_checkdb
) AS x
WHERE d.database_id > 4
ORDER BY last_good_checkdb ASC;
