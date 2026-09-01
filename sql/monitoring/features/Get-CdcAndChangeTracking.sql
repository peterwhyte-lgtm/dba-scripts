/*
Script Name : Get-CdcAndChangeTracking
Category    : monitoring
Purpose     : CDC (Change Data Capture) and Change Tracking enabled databases with retention,
              cleanup settings, and latency indicators. Both features impact transaction log
              growth and can stall if cleanup jobs are absent or delayed.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-cdc-and-change-tracking/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE, SELECT on msdb
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- msdb.dbo.cdc_jobs only exists when CDC has been configured (absent on fresh instances
-- or SQL Server 2025+). Use a temp table + dynamic SQL to avoid parse-time failures.
CREATE TABLE #cdc_ct (
    feature              NVARCHAR(50),
    database_name        SYSNAME,
    feature_enabled      BIT,
    job_type             NVARCHAR(50),
    max_trans_per_scan   INT,
    max_scans            INT,
    continuous_mode      BIT,
    polling_interval_sec INT,
    retention_minutes    INT,
    retention_hours      DECIMAL(10,1),
    cleanup_threshold    INT,
    status               NVARCHAR(200)
);

-- CDC: join to cdc_jobs only if the table exists
IF OBJECT_ID('msdb.dbo.cdc_jobs', 'U') IS NOT NULL
BEGIN
    INSERT INTO #cdc_ct
    EXEC sys.sp_executesql N'
    SELECT ''CDC'', d.name, d.is_cdc_enabled,
        cj.job_type, cj.maxtrans, cj.maxscans, cj.continuous, cj.pollinginterval,
        cj.retention, CAST(cj.retention / 60.0 AS DECIMAL(10,1)), cj.threshold,
        CASE
            WHEN d.is_cdc_enabled = 0
                THEN ''INFO - CDC not enabled on this database''
            WHEN cj.job_type = ''capture'' AND cj.retention IS NULL
                THEN ''WARN - capture job exists but no cleanup job found; log growth risk''
            WHEN cj.retention < 1440
                THEN ''WARN - retention < 24 hours; downstream consumers may miss changes''
            ELSE ''OK''
        END
    FROM sys.databases AS d
    LEFT JOIN msdb.dbo.cdc_jobs AS cj ON cj.database_id = d.database_id
    WHERE d.database_id > 4
      AND (d.is_cdc_enabled = 1 OR cj.database_id IS NOT NULL);
    ';
END
ELSE IF EXISTS (SELECT 1 FROM sys.databases WHERE database_id > 4 AND is_cdc_enabled = 1)
BEGIN
    INSERT INTO #cdc_ct (feature, database_name, feature_enabled, status)
    SELECT 'CDC', d.name, d.is_cdc_enabled, 'OK - CDC enabled'
    FROM sys.databases AS d
    WHERE d.database_id > 4 AND d.is_cdc_enabled = 1;
END

-- Change Tracking (sys.change_tracking_databases is always available SQL 2008+)
INSERT INTO #cdc_ct (feature, database_name, feature_enabled, retention_minutes, retention_hours, status)
SELECT
    'CHANGE_TRACKING',
    DB_NAME(ct.database_id),
    1,
    ct.retention_period * CASE ct.retention_period_units
                               WHEN 1 THEN 1
                               WHEN 2 THEN 60
                               WHEN 3 THEN 1440
                               ELSE 1
                           END,
    CAST(ct.retention_period * CASE ct.retention_period_units
                                    WHEN 1 THEN 1.0/60
                                    WHEN 2 THEN 1
                                    WHEN 3 THEN 24
                                    ELSE 1.0/60
                                END AS DECIMAL(10,1)),
    CASE
        WHEN ct.retention_period * CASE ct.retention_period_units
                                        WHEN 1 THEN 1
                                        WHEN 2 THEN 60
                                        WHEN 3 THEN 1440
                                        ELSE 1
                                    END < 1440
            THEN 'WARN - retention < 24 hours; consumers may miss changes between syncs'
        ELSE 'OK - Change Tracking enabled'
    END
FROM sys.change_tracking_databases AS ct;

SELECT * FROM #cdc_ct ORDER BY feature, database_name;
DROP TABLE #cdc_ct;
