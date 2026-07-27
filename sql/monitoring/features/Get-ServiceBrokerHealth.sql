/*
Script Name : Get-ServiceBrokerHealth
Category    : monitoring
Purpose     : Service Broker health across all user databases. Orphaned/disconnected
              conversation endpoints accumulate silently over months, eventually degrading
              SB infrastructure. SB is implicitly active on many instances (Database Mail,
              AG health checks use it). Surfaces conversation endpoint counts by state,
              transmission queue depth, and queue activation status.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
HealthCheck : Yes
*/
-- Blog: https://sqldba.blog/dba-scripts-get-service-broker-health-and-database-mail-queue/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #sb_health (
    database_name               SYSNAME,
    sb_enabled                  BIT,
    total_endpoints             INT,
    endpoints_active            INT,
    endpoints_error             INT,
    endpoints_disconnected      INT,
    endpoints_closed_stale      INT,
    transmission_queue_total    INT,
    transmission_queue_errors   INT,
    queues_active               INT,
    queues_disabled             INT,
    activated_tasks_running     INT,
    status                      NVARCHAR(500)
);

DECLARE @db  SYSNAME;
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    INSERT INTO #sb_health
    SELECT
        N' + QUOTENAME(@db, N'''') + N',
        d.is_broker_enabled,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.conversation_endpoints)
            AS total_endpoints,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.conversation_endpoints
         WHERE state_desc IN (''STARTED_OUTBOUND'',''STARTED_INBOUND'',''CONVERSING''))
            AS endpoints_active,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.conversation_endpoints
         WHERE state_desc LIKE ''%ERROR%'')
            AS endpoints_error,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.conversation_endpoints
         WHERE state_desc LIKE ''DISCONNECTED%'')
            AS endpoints_disconnected,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.conversation_endpoints
         WHERE state_desc = ''CLOSED''
           AND DATEDIFF(DAY, lifetime, GETDATE()) > 0)
            AS endpoints_closed_stale,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.transmission_queue)
            AS transmission_queue_total,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.transmission_queue
         WHERE transmission_status IS NOT NULL AND transmission_status <> '''')
            AS transmission_queue_errors,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.service_queues
         WHERE is_receive_enabled = 1)
            AS queues_active,
        (SELECT COUNT(*)
         FROM ' + QUOTENAME(@db) + N'.sys.service_queues
         WHERE is_receive_enabled = 0)
            AS queues_disabled,
        (SELECT COUNT(*)
         FROM sys.dm_broker_activated_tasks t
         WHERE t.database_id = DB_ID(N' + QUOTENAME(@db, N'''') + N'))
            AS activated_tasks_running,
        ''OK''
    FROM sys.databases d
    WHERE d.name = N' + QUOTENAME(@db, N'''') + N';';

    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;

    FETCH NEXT FROM db_cursor INTO @db;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

UPDATE #sb_health SET status =
    CASE
        WHEN sb_enabled = 0
            THEN 'INFO — Service Broker disabled on this database'
        WHEN endpoints_disconnected > 10000
            THEN 'CRITICAL — ' + CAST(endpoints_disconnected AS VARCHAR) +
                 ' disconnected endpoints; run END CONVERSATION ... WITH CLEANUP to reclaim resources'
        WHEN endpoints_disconnected > 1000
            THEN 'WARN — ' + CAST(endpoints_disconnected AS VARCHAR) +
                 ' disconnected endpoints accumulating; schedule cleanup'
        WHEN endpoints_error > 100
            THEN 'WARN — ' + CAST(endpoints_error AS VARCHAR) + ' conversation endpoints in ERROR state'
        WHEN transmission_queue_errors > 0
            THEN 'WARN — ' + CAST(transmission_queue_errors AS VARCHAR) +
                 ' messages stuck in transmission queue with delivery errors'
        WHEN transmission_queue_total > 1000
            THEN 'WARN — ' + CAST(transmission_queue_total AS VARCHAR) +
                 ' messages queued for transmission; check SB connectivity and activation'
        WHEN sb_enabled = 1
            THEN 'OK'
        ELSE 'OK'
    END;

SELECT
    database_name,
    sb_enabled,
    total_endpoints,
    endpoints_active,
    endpoints_error,
    endpoints_disconnected,
    endpoints_closed_stale,
    transmission_queue_total,
    transmission_queue_errors,
    queues_active,
    queues_disabled,
    activated_tasks_running,
    status
FROM #sb_health
ORDER BY
    CASE WHEN status LIKE 'CRITICAL%' THEN 1
         WHEN status LIKE 'WARN%'     THEN 2
         WHEN status LIKE 'INFO%'     THEN 3
         ELSE 4 END,
    database_name;

DROP TABLE #sb_health;
