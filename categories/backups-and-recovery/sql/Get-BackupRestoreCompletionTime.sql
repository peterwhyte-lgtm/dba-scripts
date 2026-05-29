/*
Script Name : Estimate Backup and Restore Completion Time
Description : Returns Backup Restore Completion Time for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    r.command,
    s.text AS sql_text,
    r.start_time,
    r.percent_complete,
    r.estimated_completion_time / 1000 / 60 AS est_minutes_remaining
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS s
WHERE r.command IN ('BACKUP DATABASE', 'RESTORE DATABASE');



