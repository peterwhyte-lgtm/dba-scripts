/*
Script Name : Get-TransactionLogSizeAndUsage
Category    : storage-capacity-management
Purpose     : Show transaction log size, used space, free space, and percent used per database.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-transaction-log-size-and-usage/)
Requires    : VIEW SERVER STATE (DBCC SQLPERF), read on msdb.dbo.backupset
Notes       : Usage figures come from DBCC SQLPERF(LOGSPACE), which reports every database.
              FILEPROPERTY is current-database-scoped and silently returned 0 for all other
              databases (fixed 2026-07-19). Offline databases show NULL usage.
HealthCheck : Yes
*/
-- Blog: https://sqldba.blog/dba-scripts-get-transaction-log-size-and-usage/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @logspace TABLE
(
    database_name       sysname NOT NULL PRIMARY KEY,
    log_size_mb         FLOAT   NOT NULL,
    log_space_used_pct  FLOAT   NOT NULL,
    status              INT     NOT NULL
);

INSERT INTO @logspace (database_name, log_size_mb, log_space_used_pct, status)
EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');

;WITH LogBackup AS
(
    SELECT
        database_name,
        MAX(backup_finish_date) AS last_log_backup
    FROM msdb.dbo.backupset
    WHERE type = 'L'
    GROUP BY database_name
)

SELECT
    d.name AS database_name,

    d.state_desc,

    d.recovery_model_desc,

    d.log_reuse_wait_desc,

    COUNT(mf.file_id) AS log_file_count,

    STRING_AGG(mf.physical_name, '; ') AS log_file_paths,

    CAST(
        SUM(CAST(mf.size AS BIGINT)) * 8.0 / 1024
        AS DECIMAL(18,1)
    ) AS log_size_mb,

    CAST(
        MAX(ls.log_size_mb) * MAX(ls.log_space_used_pct) / 100.0
        AS DECIMAL(18,1)
    ) AS log_used_mb,

    CAST(
        MAX(ls.log_size_mb) * (100.0 - MAX(ls.log_space_used_pct)) / 100.0
        AS DECIMAL(18,1)
    ) AS log_free_mb,

    CAST(
        MAX(ls.log_space_used_pct)
        AS DECIMAL(5,1)
    ) AS log_used_pct,

    CASE
        WHEN COUNT(DISTINCT mf.is_percent_growth) > 1
            THEN 'Mixed'

        WHEN MAX(CAST(mf.is_percent_growth AS INT)) = 1
            THEN CAST(MAX(mf.growth) AS VARCHAR(20)) + '%'

        ELSE
            CAST(
                (MAX(CAST(mf.growth AS BIGINT)) * 8) / 1024
                AS VARCHAR(20)
            ) + ' MB'
    END AS autogrowth_setting,

    CASE
        WHEN COUNT(DISTINCT mf.is_percent_growth) > 1
            THEN 'Mixed'

        WHEN MAX(CAST(mf.is_percent_growth AS INT)) = 1
            THEN 'Percent'

        ELSE
            'Fixed MB'
    END AS autogrowth_type,

    CASE
        WHEN MAX(mf.max_size) = -1
            THEN 'Unlimited'

        ELSE
            CAST(
                (MAX(CAST(mf.max_size AS BIGINT)) * 8) / 1024
                AS VARCHAR(20)
            ) + ' MB'
    END AS max_size,

    lb.last_log_backup,

    CASE
        WHEN lb.last_log_backup IS NULL
            THEN NULL

        ELSE
            DATEDIFF(
                MINUTE,
                lb.last_log_backup,
                GETDATE()
            )
    END AS minutes_since_last_log_backup
FROM sys.master_files AS mf
JOIN sys.databases AS d
    ON mf.database_id = d.database_id
LEFT JOIN @logspace AS ls
    ON ls.database_name = d.name
LEFT JOIN LogBackup AS lb
    ON d.name = lb.database_name
WHERE mf.type_desc = 'LOG'
AND d.database_id > 4
GROUP BY
    d.name,
    d.state_desc,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    lb.last_log_backup
ORDER BY
    log_used_pct DESC,
    log_size_mb DESC;
