/*
Script Name : Get-LastDbccCheckdb
Category    : maintenance-and-reliability
Purpose     : Show when each user database last had a successful DBCC CHECKDB run.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
Notes       : Uses DATABASEPROPERTYEX('LastGoodCheckDbTime') — available SQL Server 2012+.
              NULL means CHECKDB has never completed successfully on this instance for that database.
              Microsoft recommends running CHECKDB at least weekly.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    d.name                                                                  AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME)    AS last_good_checkdb,
    DATEDIFF(DAY,
        CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME),
        GETDATE())                                                           AS days_since_checkdb,
    CASE
        WHEN CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME) IS NULL
            THEN 'NEVER_RUN'
        WHEN DATEDIFF(DAY,
                CAST(DATABASEPROPERTYEX(d.name, 'LastGoodCheckDbTime') AS DATETIME),
                GETDATE()) > 7
            THEN 'STALE'
        ELSE 'OK'
    END                                                                     AS checkdb_status
FROM sys.databases AS d
WHERE d.database_id > 4
ORDER BY last_good_checkdb ASC;
