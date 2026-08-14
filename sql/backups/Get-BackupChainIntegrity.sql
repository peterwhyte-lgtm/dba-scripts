/*
Script Name : Get-BackupChainIntegrity
Category    : backups
Purpose     : LSN continuity analysis for each user database. Verifies the log backup chain
              from the most recent full backup to now is unbroken. A gap in the log chain
              means point-in-time restore is impossible for that window — coverage scripts
              only check recency, not continuity. Also surfaces damaged backup sets.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-backup-chain-integrity/)
Requires    : SELECT on msdb, VIEW ANY DATABASE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH
last_full AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_set_id) AS backup_set_id
    FROM msdb.dbo.backupset AS bs
    WHERE bs.type = 'D'
      AND bs.database_name NOT IN ('master','model','msdb','tempdb')
    GROUP BY bs.database_name
),
full_details AS (
    SELECT
        bs.database_name,
        bs.backup_set_id AS full_backup_set_id,
        bs.backup_start_date AS full_backup_start,
        bs.backup_finish_date AS full_backup_finish,
        bs.first_lsn AS full_first_lsn,
        bs.last_lsn AS full_last_lsn,
        bs.is_damaged AS full_is_damaged,
        bs.has_incomplete_metadata AS full_incomplete_metadata,
        bs.compressed_backup_size / 1024.0 / 1024.0 AS full_backup_size_mb,
        bmf.physical_device_name AS full_backup_file
    FROM last_full lf
    JOIN msdb.dbo.backupset AS bs ON bs.backup_set_id = lf.backup_set_id
    LEFT JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
),
log_chain AS (
    SELECT
        bs.database_name,
        bs.backup_set_id,
        bs.backup_start_date,
        bs.first_lsn,
        bs.last_lsn,
        bs.is_damaged,
        ROW_NUMBER() OVER (PARTITION BY bs.database_name ORDER BY bs.first_lsn) AS log_seq,
        LAG(bs.last_lsn) OVER (PARTITION BY bs.database_name ORDER BY bs.first_lsn) AS prev_last_lsn
    FROM msdb.dbo.backupset AS bs
    JOIN full_details AS fd ON fd.database_name = bs.database_name
    WHERE bs.type = 'L'
      AND bs.first_lsn >= fd.full_last_lsn
),
log_gaps AS (
    SELECT
        database_name,
        COUNT(*) AS log_backup_count,
        SUM(CASE WHEN is_damaged = 1 THEN 1 ELSE 0 END) AS damaged_log_backups,
        SUM(CASE
            WHEN log_seq > 1 AND prev_last_lsn IS NOT NULL AND first_lsn > prev_last_lsn + 1
            THEN 1 ELSE 0 END) AS chain_gaps,
        MIN(CASE
            WHEN log_seq > 1 AND prev_last_lsn IS NOT NULL AND first_lsn > prev_last_lsn + 1
            THEN backup_start_date END) AS first_gap_at
    FROM log_chain
    GROUP BY database_name
),
last_log AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_finish_date) AS last_log_backup_finish,
        MAX(bs.last_lsn) AS last_log_lsn
    FROM msdb.dbo.backupset AS bs
    WHERE bs.type = 'L'
      AND bs.database_name NOT IN ('master','model','msdb','tempdb')
    GROUP BY bs.database_name
),
-- Combine everything before ordering (avoids alias-in-UNION ORDER BY restriction)
combined AS (
    SELECT
        fd.database_name,
        fd.full_backup_start,
        fd.full_backup_finish,
        CAST(fd.full_backup_size_mb AS DECIMAL(12,2)) AS full_backup_size_mb,
        DATEDIFF(HOUR, fd.full_backup_finish, GETDATE()) AS full_backup_age_hours,
        fd.full_is_damaged,
        fd.full_incomplete_metadata,
        ISNULL(lg.log_backup_count, 0) AS log_backups_since_full,
        ISNULL(lg.damaged_log_backups, 0) AS damaged_log_backups,
        ISNULL(lg.chain_gaps, 0) AS log_chain_gaps,
        lg.first_gap_at,
        ll.last_log_backup_finish,
        DATEDIFF(MINUTE, ll.last_log_backup_finish, GETDATE()) AS log_backup_age_minutes,
        d.recovery_model_desc,
        d.log_reuse_wait_desc,
        CASE
            WHEN fd.full_is_damaged = 1
            THEN 'CRITICAL — last full backup is marked damaged in msdb'
            WHEN ISNULL(lg.chain_gaps, 0) > 0
            THEN 'CRITICAL — ' + CAST(lg.chain_gaps AS VARCHAR) +
                 ' gap(s) in log chain since last full; PITR impossible for those windows (gap starts ' +
                 CONVERT(VARCHAR(20), lg.first_gap_at, 120) + ')'
            WHEN d.recovery_model_desc = 'FULL' AND ll.last_log_backup_finish IS NULL
            THEN 'WARN — FULL recovery model but no log backups since last full'
            WHEN d.recovery_model_desc = 'FULL'
                 AND DATEDIFF(MINUTE, ll.last_log_backup_finish, GETDATE()) > 60
            THEN 'WARN — last log backup is ' +
                 CAST(DATEDIFF(MINUTE, ll.last_log_backup_finish, GETDATE()) AS VARCHAR) +
                 ' minutes old; RPO exposure growing'
            WHEN ISNULL(lg.damaged_log_backups, 0) > 0
            THEN 'WARN — ' + CAST(lg.damaged_log_backups AS VARCHAR) + ' log backup(s) marked damaged'
            ELSE 'OK — chain is intact'
        END AS chain_status,
        LEFT(fd.full_backup_file, 200) AS full_backup_file_path
    FROM full_details AS fd
    LEFT JOIN log_gaps AS lg ON lg.database_name = fd.database_name
    LEFT JOIN last_log AS ll ON ll.database_name = fd.database_name
    LEFT JOIN sys.databases AS d ON d.name = fd.database_name

    UNION ALL

    SELECT
        d.name, NULL, NULL, NULL, NULL, NULL, NULL,
        0, 0, 0, NULL, NULL, NULL,
        d.recovery_model_desc, d.log_reuse_wait_desc,
        'CRITICAL — no full backup on record for this database',
        NULL
    FROM sys.databases AS d
    WHERE d.database_id > 4
      AND d.state = 0
      AND d.name NOT IN (SELECT database_name FROM full_details)
)
SELECT *
FROM combined
ORDER BY
    CASE WHEN chain_status LIKE 'CRITICAL%' THEN 1
         WHEN chain_status LIKE 'WARN%' THEN 2
         ELSE 3 END,
    database_name;
