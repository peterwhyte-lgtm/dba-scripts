/*
Script Name : Get-EditionFeatureUsage
Category    : migration
Purpose     : Audits Enterprise-only features in active use on this instance.
              Run before any edition downgrade (Enterprise → Standard, Standard → Web).
              Each row describes a feature, whether it is in use, and what breaks on the target edition.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-edition-feature-usage/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE, VIEW ANY DEFINITION
*/
-- Blog: https://sqldba.blog/dba-scripts-get-edition-feature-usage/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Returns one row per feature category with:
    in_use         — YES / NO / N/A (can't detect)
    blocks_downgrade — YES (will fail), WARN (degraded behaviour), NO
    detail          — what specifically was found
    action          — what to do before downgrade

  Standard Edition limits by version:
    ≤ SQL 2014 SP1      Row/page compression, partitioning, CDC: Enterprise only
    SQL 2016 SP1+       Row/page compression, partitioning, CDC, columnstore (non-clustered),
                        In-Memory OLTP (max 32 GB): available in Standard
    All versions        TDE, Database Snapshots, Resource Governor, AG readable secondaries,
                        parallel index rebuild, multiple-DB AG (> 1 per AG in Standard): Enterprise only
*/

-- ── Working storage ───────────────────────────────────────────────────────────
IF OBJECT_ID('tempdb..#findings') IS NOT NULL DROP TABLE #findings;
CREATE TABLE #findings (
    feature           NVARCHAR(80),
    in_use            NVARCHAR(5),
    blocks_downgrade  NVARCHAR(5),
    detail            NVARCHAR(MAX),
    action_required   NVARCHAR(MAX)
);

DECLARE @sql NVARCHAR(MAX);
DECLARE @cnt INT;
DECLARE @detail NVARCHAR(MAX);

-- ── 1. Transparent Data Encryption (TDE) ─────────────────────────────────────
-- Enterprise/Developer only. Standard cannot open a TDE-encrypted database.
SET @detail = '';
SELECT @cnt = COUNT(*), @detail = STRING_AGG(DB_NAME(database_id), ', ')
FROM sys.dm_database_encryption_keys
WHERE encryption_state > 1;   -- 1 = unencrypted, 2 = encrypting, 3 = encrypted

INSERT #findings VALUES (
    'Transparent Data Encryption (TDE)',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' encrypted database(s): ' + @detail
         ELSE 'No TDE-encrypted databases' END,
    CASE WHEN @cnt > 0 THEN 'Remove TDE before migration: ALTER DATABASE [name] SET ENCRYPTION OFF; then DROP DATABASE ENCRYPTION KEY'
         ELSE '' END
);

-- ── 2. Database Snapshots ─────────────────────────────────────────────────────
-- Enterprise only (all SQL versions). Standard cannot create or use snapshots.
SELECT @cnt = COUNT(*), @detail = ISNULL(STRING_AGG(name, ', '), '')
FROM sys.databases WHERE source_database_id IS NOT NULL;

INSERT #findings VALUES (
    'Database Snapshots',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' snapshot(s): ' + @detail
         ELSE 'No database snapshots' END,
    CASE WHEN @cnt > 0 THEN 'Snapshots cannot be created on Standard. Drop existing snapshots before migration or accept that they will not be available post-downgrade'
         ELSE '' END
);

-- ── 3. Resource Governor ──────────────────────────────────────────────────────
-- Enterprise only. Standard ignores Resource Governor configuration but it will exist in msdb.
SELECT @cnt = CASE WHEN is_enabled = 1 THEN 1 ELSE 0 END
FROM sys.resource_governor_configuration;

INSERT #findings VALUES (
    'Resource Governor',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'Resource Governor is enabled with active configuration'
         ELSE 'Resource Governor is not enabled' END,
    CASE WHEN @cnt > 0 THEN 'Resource Governor does not work on Standard Edition — workload classification and pooling will be lost post-downgrade. Remove pools and classifiers if not needed.'
         ELSE '' END
);

-- ── 4. Always On AG — readable secondaries ────────────────────────────────────
-- Readable secondaries are Enterprise only. Standard Basic AG secondary is not readable.
SELECT @cnt = COUNT(*), @detail = ISNULL(STRING_AGG(ag.name + ' → ' + ar.replica_server_name, ', '), '')
FROM sys.availability_replicas ar
INNER JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE ar.secondary_role_allow_connections > 0  -- NO=0, READ_ONLY=1, ALL=2
  AND ar.replica_server_name <> @@SERVERNAME;

INSERT #findings VALUES (
    'AG Readable Secondaries',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' readable secondary replica(s): ' + @detail
         ELSE 'No readable secondary replicas configured' END,
    CASE WHEN @cnt > 0 THEN 'Standard Basic AG secondaries are not readable. Applications using read-scale offloading must be redirected to the primary, or a different read-scale solution must be implemented.'
         ELSE '' END
);

-- ── 5. AG with multiple databases (Standard Basic AG limit: 1 database per AG) ─
SELECT @cnt = COUNT(*),
       @detail = ISNULL(
           STRING_AGG(sub.ag_name + ' (' + CAST(sub.db_count AS NVARCHAR) + ' dbs)', ', '),
           ''
       )
FROM (
    SELECT ag.name AS ag_name, COUNT(*) AS db_count
    FROM sys.availability_databases_cluster adc
    INNER JOIN sys.availability_groups ag ON adc.group_id = ag.group_id
    GROUP BY ag.group_id, ag.name
    HAVING COUNT(*) > 1
) sub;

INSERT #findings VALUES (
    'AG Multi-Database (> 1 DB per AG)',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' AG(s) with > 1 database: ' + @detail
         ELSE 'All AGs have 1 database or no AGs exist' END,
    CASE WHEN @cnt > 0 THEN 'Standard Basic AG supports exactly 1 database per AG. Split multi-database AGs into separate AGs (one per database) before downgrade.'
         ELSE '' END
);

-- ── 6. Row / Page Compression ─────────────────────────────────────────────────
-- Enterprise only before SQL 2016 SP1. Standard 2016 SP1+ supports it.
-- Flag as WARN — present but supported in modern Standard versions.
-- NOTE: this only reflects the current database context (the wrapper runs this
-- script against master), it is not a cross-database sweep. Run per user database
-- for a full inventory: SELECT name, data_compression_desc FROM sys.partitions
-- WHERE data_compression > 0.
SELECT @cnt = COUNT(DISTINCT p.object_id)
FROM sys.partitions p
WHERE p.data_compression > 0
  AND p.rows > 0;

INSERT #findings VALUES (
    'Row / Page Compression',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' compressed object(s) in the current database context (run per user database for a full inventory)'
         ELSE 'No row/page compression detected in the current database context (run per user database for a full inventory)' END,
    CASE WHEN @cnt > 0 THEN 'Supported in Standard 2016 SP1+. If downgrading to Standard 2014 or earlier, compression must be removed. Run: SELECT name, data_compression_desc FROM sys.partitions WHERE data_compression > 0 in each user database.'
         ELSE '' END
);

-- ── 7. Clustered Columnstore Indexes ─────────────────────────────────────────
-- Clustered columnstore (type=5) is Enterprise only in SQL 2014.
-- SQL 2016 SP1+ Standard supports non-clustered columnstore (type=6).
SELECT @cnt = COUNT(*), @detail = ISNULL(STRING_AGG(OBJECT_NAME(object_id) + ' (' + type_desc + ')', ', '), '')
FROM sys.indexes
WHERE type IN (5)   -- 5 = CLUSTERED COLUMNSTORE
  AND OBJECT_ID < 2000000000;  -- exclude internal objects

INSERT #findings VALUES (
    'Clustered Columnstore Indexes',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' clustered columnstore index/indexes (in current DB context only): ' + LEFT(@detail, 500)
         ELSE 'No clustered columnstore indexes in system databases (run in each user database)' END,
    CASE WHEN @cnt > 0 THEN 'Clustered columnstore is Enterprise only in SQL 2014. SQL 2016 SP1+ Standard supports it. If downgrading to Standard 2014, rebuild as heap or B-tree index before migration.'
         ELSE '' END
);

-- ── 8. In-Memory OLTP (Memory-Optimized Tables) ───────────────────────────────
-- Enterprise only in SQL 2014. Standard 2016 SP1+ supports limited In-Memory (max 32 GB).
SELECT @cnt = COUNT(*), @detail = ISNULL(STRING_AGG(d.name, ', '), '')
FROM sys.databases d
INNER JOIN sys.filegroups fg ON d.database_id = DB_ID(d.name)
WHERE fg.type = 'FX';  -- FX = memory-optimized filegroup

INSERT #findings VALUES (
    'In-Memory OLTP (Memory-Optimized Tables)',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' database(s) with memory-optimized filegroup: ' + @detail
         ELSE 'No in-memory filegroups detected' END,
    CASE WHEN @cnt > 0 THEN 'Standard 2016 SP1+ supports In-Memory OLTP up to 32 GB. SQL 2014 Standard does not. If total memory-optimized data exceeds 32 GB, this cannot be migrated to Standard 2016 SP1+.'
         ELSE '' END
);

-- ── 9. Stretch Database ───────────────────────────────────────────────────────
-- Deprecated in SQL 2022. Enterprise only in SQL 2016–2019.
BEGIN TRY
    SELECT @cnt = COUNT(*) FROM sys.remote_data_archive_tables;
    SET @detail = CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' Stretch-enabled table(s) — query sys.remote_data_archive_tables for details' ELSE 'No Stretch Database tables' END;
END TRY
BEGIN CATCH
    SET @cnt = 0; SET @detail = 'sys.remote_data_archive_tables not available (Stretch not installed or SQL 2022+)';
END CATCH;

INSERT #findings VALUES (
    'Stretch Database',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    @detail,
    CASE WHEN @cnt > 0 THEN 'Stretch Database is deprecated (SQL 2022) and Enterprise only. Migrate data from Azure back to local tables before downgrade. Alter each table: ALTER TABLE [t] SET (REMOTE_DATA_ARCHIVE = OFF (MIGRATION_STATE = INBOUND));'
         ELSE '' END
);

-- ── 10. External Scripts / Machine Learning Services ─────────────────────────
-- R/Python extensions. Available on SQL Server ML Services (Enterprise focus, but Standard supports from 2016).
-- Flag as INFO since Standard does support it from 2016 SP1.
SELECT @cnt = CAST(value_in_use AS INT)
FROM sys.configurations WHERE name = 'external scripts enabled';

INSERT #findings VALUES (
    'External Scripts (ML Services / R / Python)',
    CASE WHEN @cnt = 1 THEN 'YES' ELSE 'NO' END,
    'NO',
    CASE WHEN @cnt = 1 THEN 'External scripts are enabled — ML Services (R/Python) is in use'
         ELSE 'External scripts are not enabled' END,
    CASE WHEN @cnt = 1 THEN 'Standard supports External Scripts from SQL 2016 SP1. No action required for Standard downgrade unless targeting SQL 2016 RTM or earlier.'
         ELSE '' END
);

-- ── 11. Parallel Index Rebuild / Online Operations ────────────────────────────
-- Cannot detect at-rest, only from job history / agent steps.
INSERT #findings VALUES (
    'Online Index Operations / Parallel Rebuild',
    'N/A',
    'WARN',
    'Cannot be detected statically — check SQL Agent jobs and maintenance plans for REBUILD WITH (ONLINE=ON)',
    'Online index operations (REBUILD WITH ONLINE=ON, REORGANIZE) are Enterprise only. On Standard, index rebuilds go offline. Review maintenance plans and set ONLINE=OFF or use REORGANIZE instead.'
);

-- ── 12. Change Data Capture ───────────────────────────────────────────────────
-- Enterprise only before SQL 2016 SP1. Standard 2016 SP1+ supports CDC.
SELECT @cnt = COUNT(*), @detail = ISNULL(STRING_AGG(d.name, ', '), '')
FROM sys.databases d
WHERE d.is_cdc_enabled = 1
  AND d.database_id > 4;

INSERT #findings VALUES (
    'Change Data Capture (CDC)',
    CASE WHEN @cnt > 0 THEN 'YES' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN 'WARN' ELSE 'NO' END,
    CASE WHEN @cnt > 0 THEN CAST(@cnt AS NVARCHAR) + ' database(s) with CDC enabled: ' + @detail
         ELSE 'CDC not enabled on any user databases' END,
    CASE WHEN @cnt > 0 THEN 'CDC is available in Standard from SQL 2016 SP1. No action needed if target is Standard 2016 SP1+. If target is Standard 2014 or earlier, CDC must be disabled before migration.'
         ELSE '' END
);

-- ── Output ────────────────────────────────────────────────────────────────────
SELECT
    feature,
    in_use,
    blocks_downgrade,
    detail,
    action_required
FROM #findings
ORDER BY
    CASE blocks_downgrade WHEN 'YES' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END,
    feature;

DROP TABLE #findings;
