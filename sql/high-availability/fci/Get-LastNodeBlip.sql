/*
Script Name : Get-LastNodeBlip
Category    : high-availability
Purpose     : Returns SQL Server error log entries that mention failover, alongside the current
              instance start time. On an FCI, every node blip causes SQL Server to restart on the
              receiving node — sqlserver_start_time is when it last came online.
              If no rows are returned there are no 'failover' entries in the current error log
              archive; use the PowerShell Get-WinEvent approach to query the Windows Failover
              Clustering Operational log directly (see blog post).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-last-node-blip/)
Requires    : VIEW SERVER STATE, EXECUTE on xp_readerrorlog (sysadmin or securityadmin in practice)
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo NVARCHAR(100),
    [Text] NVARCHAR(MAX)
);

INSERT INTO #ErrorLog
EXEC xp_readerrorlog 0, 1, N'failover';

IF NOT EXISTS (SELECT 1 FROM #ErrorLog)
BEGIN
    -- Keep the context row even when the log is quiet, so a CSV/AI reader can
    -- distinguish "no failover entries" from "collection failed".
    SELECT
        'No failover-related entries in the current error log archive.' AS status,
        CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256)) AS server_name,
        CAST(SERVERPROPERTY('IsClustered') AS BIT) AS is_clustered,
        osi.sqlserver_start_time AS instance_last_started,
        DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()) AS days_up
    FROM sys.dm_os_sys_info osi;
END
ELSE
BEGIN
    SELECT
        e.LogDate AS event_time,
        CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256)) AS server_name,
        CAST(SERVERPROPERTY('IsClustered') AS BIT) AS is_clustered,
        osi.sqlserver_start_time AS instance_last_started,
        DATEDIFF(DAY, osi.sqlserver_start_time, GETDATE()) AS days_up,
        e.ProcessInfo AS source,
        e.[Text] AS message
    FROM #ErrorLog e
    CROSS JOIN sys.dm_os_sys_info osi
    ORDER BY e.LogDate DESC;
END

DROP TABLE #ErrorLog;
