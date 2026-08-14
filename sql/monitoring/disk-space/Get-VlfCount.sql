/*
Script Name : Get-VlfCount
Category    : monitoring
Purpose     : Reports virtual log file (VLF) count per database transaction log,
              ranked by severity. High VLF counts degrade recovery time, log backup
              performance, and redo during AG synchronisation. Often caused by many
              small autogrowth events accumulating over time.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-vlf-counts/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
Notes       : Target: < 50 VLFs per database. > 200 is elevated. > 1000 is severe.
              Fix: shrink the log to near-zero, then grow it in one large fixed-MB
              increment matching expected steady-state size.
              Run Get-TransactionLogSizeAndUsage first to size the target correctly.
              sys.dm_db_log_info path: SQL Server 2016 SP2+ / 2017 CU4+.
              Fallback cursor path (DBCC LOGINFO): SQL Server 2012+.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM sys.system_objects WHERE name = 'dm_db_log_info' AND type = 'IF')
BEGIN
    -- SQL Server 2016 SP2+ / 2017 CU4+: single query
    SELECT 
        d.name AS database_name,
        d.recovery_model_desc AS recovery_model,
        COUNT(*) AS vlf_count,
        CAST(SUM(li.vlf_size_mb) AS DECIMAL(10,2)) AS log_size_mb,
        CASE 
            WHEN COUNT(*) > 1000 THEN 'CRITICAL'
            WHEN COUNT(*) > 200 THEN 'HIGH'
            WHEN COUNT(*) > 50  THEN 'ELEVATED'
            ELSE 'OK'
        END AS status
    FROM sys.databases d
    CROSS APPLY sys.dm_db_log_info(d.database_id) li
    WHERE d.state_desc = 'ONLINE'
      AND d.database_id > 4
    GROUP BY d.name, d.database_id, d.recovery_model_desc
    ORDER BY vlf_count DESC;
END
ELSE
BEGIN
    -- SQL Server 2012 – 2016 SP1 fallback: cursor + DBCC LOGINFO
    CREATE TABLE #vlf (
        database_name    sysname      NOT NULL,
        recovery_model   VARCHAR(20)  NOT NULL,
        vlf_count        INT          NOT NULL,
        log_size_mb      DECIMAL(10,2) NOT NULL,
        status           VARCHAR(10)  NOT NULL
    );

    CREATE TABLE #loginfo (
        RecoveryUnitId INT NULL,
        FileId         INT NOT NULL,
        FileSize       BIGINT NOT NULL,
        StartOffset    BIGINT NOT NULL,
        FSeqNo         BIGINT NOT NULL,
        [Status]       TINYINT NOT NULL,
        Parity         TINYINT NOT NULL,
        CreateLSN      NUMERIC(25,0) NULL
    );

    DECLARE @dbname SYSNAME;
    DECLARE @cmd    NVARCHAR(512);

    DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT name 
        FROM sys.databases 
        WHERE state_desc = 'ONLINE' 
          AND database_id > 4;

    OPEN db_cur;
    FETCH NEXT FROM db_cur INTO @dbname;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #loginfo;
        
        SET @cmd = N'USE ' + QUOTENAME(@dbname) + N'; DBCC LOGINFO WITH NO_INFOMSGS;';
        
        BEGIN TRY
            INSERT INTO #loginfo 
            EXEC (@cmd);

            INSERT INTO #vlf (database_name, recovery_model, vlf_count, log_size_mb, status)
            SELECT 
                @dbname,
                (SELECT recovery_model_desc 
                 FROM sys.databases 
                 WHERE name = @dbname),
                COUNT(*),
                CAST(SUM(FileSize) / 1048576.0 AS DECIMAL(10,2)),
                CASE 
                    WHEN COUNT(*) > 1000 THEN 'CRITICAL'
                    WHEN COUNT(*) > 200 THEN 'HIGH'
                    WHEN COUNT(*) > 50  THEN 'ELEVATED'
                    ELSE 'OK'
                END
            FROM #loginfo;
        END TRY
        BEGIN CATCH
            -- Skip inaccessible databases
        END CATCH;

        FETCH NEXT FROM db_cur INTO @dbname;
    END

    CLOSE db_cur;
    DEALLOCATE db_cur;

    SELECT 
        database_name,
        recovery_model,
        vlf_count,
        log_size_mb,
        status
    FROM #vlf 
    ORDER BY vlf_count DESC;

    DROP TABLE #vlf;
    DROP TABLE #loginfo;
END
