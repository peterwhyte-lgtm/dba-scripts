/*
Script Name : Get-MigrationRiskAssessment
Category    : migration
Purpose     : Pre-migration risk scan — returns categorised HIGH/MEDIUM/INFO findings for compatibility, database settings, linked server dependencies, and sizing.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-migration-risk-assessment/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @instance_compat SMALLINT;
SELECT @instance_compat =
    CASE CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)
        WHEN 17 THEN 170 -- SQL Server 2025
        WHEN 16 THEN 160
        WHEN 15 THEN 150
        WHEN 14 THEN 140
        WHEN 13 THEN 130
        WHEN 12 THEN 120
        WHEN 11 THEN 110
        WHEN 10 THEN 100
        ELSE NULL -- newer than this script knows about; compat findings are skipped rather than guessed
    END;

SELECT
    risk_category,
    risk_level,
    object_name,
    finding,
    recommendation
FROM (

    -- Compatibility level below instance native
    SELECT
        'Compatibility Level' AS risk_category,
        CASE
            WHEN d.compatibility_level < 100 THEN 'HIGH'
            WHEN d.compatibility_level < (@instance_compat - 10) THEN 'MEDIUM'
            ELSE 'INFO'
        END AS risk_level,
        d.name AS object_name,
        'Compat level ' + CAST(d.compatibility_level AS VARCHAR(5)) +
            ' (instance native: ' + CAST(@instance_compat AS VARCHAR(5)) + ')' AS finding,
        'Test on non-prod with target compat level before cutover' AS recommendation
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
      AND d.compatibility_level < @instance_compat

    UNION ALL

    -- Page verification not CHECKSUM
    SELECT
        'Data Integrity',
        'MEDIUM',
        d.name,
        'Page verification: ' + d.page_verify_option_desc COLLATE DATABASE_DEFAULT,
        'Set CHECKSUM: ALTER DATABASE [' + d.name COLLATE DATABASE_DEFAULT + '] SET PAGE_VERIFY CHECKSUM WITH NO_WAIT'
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
      AND d.page_verify_option_desc <> 'CHECKSUM'

    UNION ALL

    -- AUTO_SHRINK
    SELECT
        'Database Settings',
        'HIGH',
        d.name,
        'AUTO_SHRINK is ON',
        'Disable: ALTER DATABASE [' + d.name COLLATE DATABASE_DEFAULT + '] SET AUTO_SHRINK OFF'
    FROM sys.databases d
    WHERE d.is_auto_shrink_on = 1
      AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0

    UNION ALL

    -- AUTO_CLOSE
    SELECT
        'Database Settings',
        'MEDIUM',
        d.name,
        'AUTO_CLOSE is ON',
        'Disable: ALTER DATABASE [' + d.name COLLATE DATABASE_DEFAULT + '] SET AUTO_CLOSE OFF'
    FROM sys.databases d
    WHERE d.is_auto_close_on = 1
      AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0

    UNION ALL

    -- Databases in non-ONLINE state
    SELECT
        'Database State',
        'HIGH',
        d.name,
        'State: ' + d.state_desc COLLATE DATABASE_DEFAULT,
        'Resolve before migration - cannot migrate non-ONLINE databases'
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state <> 0

    UNION ALL

    -- SIMPLE recovery (no log backup chain)
    SELECT
        'Recovery Model',
        'INFO',
        d.name,
        'Recovery model: SIMPLE - no log backup chain',
        'If point-in-time recovery is needed during migration window, switch to FULL and take a full backup first'
    FROM sys.databases d
    WHERE d.recovery_model_desc = 'SIMPLE'
      AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0

    UNION ALL

    -- Linked servers
    SELECT
        'External Dependencies',
        'HIGH',
        s.name,
        'Linked server: ' + s.name COLLATE DATABASE_DEFAULT + ' (' + ISNULL(s.product COLLATE DATABASE_DEFAULT, 'unknown product') + ' via ' + ISNULL(s.provider COLLATE DATABASE_DEFAULT, 'unknown provider') + ')',
        'Validate linked server connectivity from target server before cutover'
    FROM sys.servers s
    WHERE s.is_linked = 1

    UNION ALL

    -- Orphaned database owners (SID not resolvable)
    SELECT
        'Database Ownership',
        'MEDIUM',
        d.name,
        'Orphaned owner SID - login does not exist on this instance',
        'Fix: ALTER AUTHORIZATION ON DATABASE::[' + d.name COLLATE DATABASE_DEFAULT + '] TO sa'
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
      AND SUSER_SNAME(d.owner_sid) IS NULL

    UNION ALL

    -- Non-SA database owners (login may not exist on target server)
    SELECT
        'Database Ownership',
        'INFO',
        d.name,
        'Owner: ' + SUSER_SNAME(d.owner_sid) COLLATE DATABASE_DEFAULT,
        'Confirm login [' + SUSER_SNAME(d.owner_sid) COLLATE DATABASE_DEFAULT + '] exists on target server, or re-owner to sa'
    FROM sys.databases d
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
      AND SUSER_SNAME(d.owner_sid) IS NOT NULL
      AND SUSER_SNAME(d.owner_sid) <> 'sa'

    UNION ALL

    -- Databases in Availability Groups (returns 0 rows on non-AG instances)
    SELECT
        'Availability Groups',
        'HIGH',
        d.name,
        'Database is in an Availability Group',
        'AG migration requires coordinated removal from AG on all replicas - see migration\README.md'
    FROM sys.databases d
    JOIN sys.dm_hadr_database_replica_states hdrs ON d.database_id = hdrs.database_id
    WHERE hdrs.is_local = 1
      AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')

    UNION ALL

    -- Large databases (> 100 GB data files) — flag for migration window planning
    SELECT
        'Migration Sizing',
        'INFO',
        d.name,
        'Data size: ' + CAST(CAST(SUM(mf.size) * 8.0 / 1048576 AS DECIMAL(10,1)) AS VARCHAR(20)) + ' GB',
        'Estimate backup/restore duration and verify network bandwidth before scheduling window'
    FROM sys.databases d
    JOIN sys.master_files mf ON d.database_id = mf.database_id AND mf.type = 0
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state = 0
    GROUP BY d.name
    HAVING SUM(mf.size) * 8.0 / 1048576 > 100

) r
ORDER BY
    CASE r.risk_level WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
    r.risk_category,
    r.object_name;
