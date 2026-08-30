/*
Script Name : Get-LogReuseWaits
Category    : monitoring
Purpose     : Reports why each database's transaction log cannot truncate and reuse
              space — the log_reuse_wait_desc reason per database, with recovery model,
              log size, and last log backup for context. This is the first question to
              answer when a log file is full or growing and won't shrink.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-log-reuse-waits/)
Requires    : VIEW ANY DATABASE, db_datareader on msdb
Notes       : NOTHING / CHECKPOINT are healthy. LOG_BACKUP means the FULL/BULK_LOGGED
              log is waiting on a log backup (the most common cause of a full log).
              ACTIVE_TRANSACTION points at a long-running or orphaned transaction —
              run Get-OpenTransactions next. AVAILABILITY_REPLICA / DATABASE_MIRRORING /
              REPLICATION mean a partner or agent hasn't consumed the log yet.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

;WITH LogBackup AS
(
    SELECT
        database_name,
        MAX(backup_finish_date) AS last_log_backup
    FROM msdb.dbo.backupset
    /* The status column comes from log_reuse_wait_desc and is already copy-only proof, but
       this date sits next to it as supporting evidence. A copy-only log backup would show a
       recent date beside "ACTION: take a log backup" and send the reader hunting a phantom. */
    WHERE type = 'L'
      AND is_copy_only = 0
    GROUP BY database_name
)

SELECT
    d.name AS database_name,
    d.recovery_model_desc AS recovery_model,
    d.log_reuse_wait_desc AS log_reuse_wait,
    CAST(SUM(CAST(mf.size AS BIGINT)) * 8.0 / 1024
        AS DECIMAL(18,1)) AS log_size_mb,
    lb.last_log_backup,
    CASE
        WHEN lb.last_log_backup IS NULL THEN NULL
        ELSE DATEDIFF(MINUTE, lb.last_log_backup, GETDATE())
    END AS minutes_since_last_log_backup,
    CASE d.log_reuse_wait_desc
        WHEN 'NOTHING' THEN 'OK'
        WHEN 'CHECKPOINT' THEN 'OK'
        WHEN 'LOG_BACKUP' THEN 'ACTION: take a log backup'
        WHEN 'ACTIVE_TRANSACTION' THEN 'INVESTIGATE: long-running or orphaned transaction'
        WHEN 'ACTIVE_BACKUP_OR_RESTORE' THEN 'MONITOR: backup or restore in progress'
        WHEN 'AVAILABILITY_REPLICA' THEN 'INVESTIGATE: AG secondary has not hardened the log'
        WHEN 'DATABASE_MIRRORING' THEN 'INVESTIGATE: mirroring partner is behind'
        WHEN 'REPLICATION' THEN 'INVESTIGATE: replication has not drained the log'
        WHEN 'OLDEST_PAGE' THEN 'MONITOR: indirect checkpoint / oldest dirty page'
        WHEN 'XTP_CHECKPOINT' THEN 'MONITOR: in-memory OLTP checkpoint'
        ELSE 'REVIEW'
    END AS status
FROM sys.databases AS d
JOIN sys.master_files AS mf
    ON mf.database_id = d.database_id
    AND mf.type_desc = 'LOG'
LEFT JOIN LogBackup AS lb
    ON lb.database_name = d.name
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4
GROUP BY
    d.name,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    lb.last_log_backup
ORDER BY
    CASE WHEN d.log_reuse_wait_desc = 'NOTHING' THEN 1 ELSE 0 END,
    log_size_mb DESC;
