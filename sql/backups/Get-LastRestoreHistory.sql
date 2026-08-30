/*
Script Name : Get-LastRestoreHistory
Category    : backups
Purpose     : Full restore history from msdb — when each database was last restored, from which backup, and by whom. Use to verify DR restore tests have actually been run.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-last-restore-history/)
Requires    : msdb access (db_datareader on msdb or sysadmin)
Notes       : A database only appears here if it has ever been restored. An instance with no
              restore history returns an explicit NO RESTORE HISTORY row rather than an empty
              result set — zero restores is the finding, not a blank screen.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Empty history is the headline finding, so say it, don't return nothing ─ */
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.restorehistory)
BEGIN
    SELECT
        CAST('NO RESTORE HISTORY - no restore has ever been recorded on this instance'
             AS NVARCHAR(128))          AS database_name,
        CAST(NULL AS DATETIME)          AS restore_date,
        CAST(NULL AS INT)               AS days_since_restore,
        CAST(NULL AS NVARCHAR(12))      AS restore_type,
        CAST(NULL AS NVARCHAR(128))     AS source_database,
        CAST(NULL AS DATETIME)          AS backup_taken_date,
        CAST(NULL AS INT)               AS backup_age_at_restore_days,
        CAST(NULL AS NVARCHAR(128))     AS user_name,
        CAST(NULL AS BIT)               AS with_recovery,
        CAST(NULL AS BIT)               AS with_replace;
    RETURN;
END

/* ── Most recent restore per database ────────────────────────────────────── */
;WITH ranked AS (
    SELECT
        rh.restore_history_id,
        rh.destination_database_name,
        rh.restore_date,
        DATEDIFF(DAY, rh.restore_date, GETDATE()) AS days_since_restore,
        CASE rh.restore_type
            WHEN 'D' THEN 'Full'
            WHEN 'I' THEN 'Differential'
            WHEN 'L' THEN 'Log'
            WHEN 'F' THEN 'File'
            WHEN 'P' THEN 'Page'
            WHEN 'R' THEN 'Revert'
            ELSE rh.restore_type
        END AS restore_type,
        bs.database_name AS source_database,
        bs.backup_finish_date AS backup_taken_date,
        DATEDIFF(DAY, bs.backup_finish_date, rh.restore_date) AS backup_age_at_restore_days,
        rh.user_name,
        rh.recovery AS with_recovery,
        rh.replace AS with_replace,
        ROW_NUMBER() OVER (
            PARTITION BY rh.destination_database_name
            ORDER BY rh.restore_date DESC
        ) AS rn
    FROM msdb.dbo.restorehistory rh
    LEFT JOIN msdb.dbo.backupset bs ON bs.backup_set_id = rh.backup_set_id
)
SELECT
    destination_database_name AS database_name,
    restore_date,
    days_since_restore,
    restore_type,
    source_database,
    backup_taken_date,
    backup_age_at_restore_days,
    user_name,
    with_recovery,
    with_replace
FROM ranked
WHERE rn = 1
ORDER BY restore_date DESC;
