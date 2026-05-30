/*
Script Name : Get-BackupRestoreProgress
Category    : performance-troubleshooting
Purpose     : Show active backup/restore progress and estimated completion for long-running operations.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT 
    er.command AS command,
    est.text AS sql_text,
    er.start_time AS start_time,
    er.percent_complete AS percent_complete,
    CAST(((DATEDIFF(SECOND, er.start_time, GETDATE())) / 3600) AS VARCHAR)
        + ' hour(s), ' 
        + CAST((DATEDIFF(SECOND, er.start_time, GETDATE()) % 3600) / 60 AS VARCHAR)
        + ' min, ' 
        + CAST((DATEDIFF(SECOND, er.start_time, GETDATE()) % 60) AS VARCHAR)
        + ' sec' AS running_time,
    CAST((er.estimated_completion_time / 3600000) AS VARCHAR)
        + ' hour(s), ' 
        + CAST((er.estimated_completion_time % 3600000) / 60000 AS VARCHAR)
        + ' min, ' 
        + CAST((er.estimated_completion_time % 60000) / 1000 AS VARCHAR)
        + ' sec' AS estimated_time_remaining,
    DATEADD(SECOND, er.estimated_completion_time / 1000, GETDATE()) AS estimated_completion_time
FROM sys.dm_exec_requests er
CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) est
WHERE er.command IN
(
    'RESTORE DATABASE',
    'BACKUP DATABASE',
    'RESTORE LOG',
    'BACKUP LOG',
    'DbccSpaceReclaim',
    'DbccFilesCompact'
);
