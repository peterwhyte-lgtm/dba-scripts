/*
Script Name : Get-BackupRestoreCompletionTime
Category    : backups-and-recovery
Purpose     : Monitor active backup and restore operations with estimated completion time.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    r.command,
    s.text AS sql_text,
    r.start_time,
    r.percent_complete,
    r.estimated_completion_time / 1000 / 60 AS est_minutes_remaining
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS s
WHERE r.command IN ('BACKUP DATABASE', 'RESTORE DATABASE');



