/*
Script Name : Create-IndexProblemScenario
Category    : lab
Purpose     : Build a database that trips every detection in Get-DuplicateIndexes,
              Get-IndexDesignIssues and Get-UnusedIndexes, so all three can be demonstrated
              against visible findings instead of an empty result set.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-duplicate-indexes/)
Requires    : sysadmin on a LAB instance. Creates one database.
*/
-- SAFE:CreatesObjects
-- IMPACT:High
--
-- ⚠ LAB ONLY. Creates a database called zzidx_db and nothing outside it. Removed by
--   Create-IndexProblemScenario's partner, Remove-IndexProblemScenario.sql.
--
-- WHAT IT TRIPS, and why each threshold was chosen by reading the two scripts rather than
-- guessing at what "looks broken":
--
--   Get-UnusedIndexes  (SCOPE:CurrentDatabase - run it INSIDE zzidx_db, not master)
--     34 nonclustered indexes with reads = 0 and writes > 0, each with a DROP statement.
--
--   Get-DuplicateIndexes
--     EXACT_DUPLICATE   dbo.Orders has IX_Orders_Cust_Date and IX_Orders_Duplicate, identical
--                       key lists. Both unused, so the recommendation column reads
--                       "DROP - both unused".
--     PREFIX_OVERLAP    IX_Orders_CustOnly (CustomerId) is a left-prefix of
--                       IX_Orders_Cust_Date (CustomerId, OrderDate).
--
--   Get-IndexDesignIssues   thresholds are >10 INFO, >20 WARN, >30 CRITICAL for index count;
--                           >450 INFO, >900 WARN, >1700 CRITICAL for key bytes.
--     TOO_MANY_INDEXES    dbo.OverIndexed carries 31 nonclustered indexes plus its clustered
--                         PK, which clears the >30 CRITICAL line.
--     WIDE_KEY_COLUMNS    dbo.WideKeys is indexed on an NVARCHAR(500), so 1000 bytes: over
--                         the 900 WARN line and under the 1700 hard limit, which is the
--                         widest a nonclustered key is allowed to be. Going for CRITICAL
--                         would need >1700 and SQL Server refuses to create it.
--     MISSING_INDEX_FLOOD dbo.Unindexed has no nonclustered indexes and 50,000 rows. The
--                         queries at the bottom make the optimizer want six different
--                         indexes on it, which clears the >=5 line.
--
-- The missing-index queries are the one part that is not purely declarative: the DMV only
-- fills in if the optimizer actually judges an index worthwhile, which needs real row counts.
-- That is why the table is populated rather than empty.

SET NOCOUNT ON;
USE master;
GO

IF DB_ID('zzidx_db') IS NOT NULL
BEGIN
    ALTER DATABASE zzidx_db SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE zzidx_db;
END
CREATE DATABASE zzidx_db;
GO
USE zzidx_db;
GO

-- ---------------------------------------------------------------- duplicate + overlap
CREATE TABLE dbo.Orders (
    OrderId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED,
    CustomerId INT            NOT NULL,
    OrderDate  DATE           NOT NULL,
    Total      DECIMAL(10, 2) NOT NULL
);
INSERT INTO dbo.Orders (CustomerId, OrderDate, Total)
SELECT TOP (2000) ABS(CHECKSUM(NEWID())) % 500, DATEADD(DAY, -(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) % 365), '2026-09-01'), 10.00
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

CREATE NONCLUSTERED INDEX IX_Orders_Cust_Date ON dbo.Orders (CustomerId, OrderDate);
CREATE NONCLUSTERED INDEX IX_Orders_Duplicate ON dbo.Orders (CustomerId, OrderDate);  -- EXACT
CREATE NONCLUSTERED INDEX IX_Orders_CustOnly  ON dbo.Orders (CustomerId);             -- PREFIX
GO

-- ---------------------------------------------------------------- wide key
CREATE TABLE dbo.WideKeys (
    Id      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WideKeys PRIMARY KEY CLUSTERED,
    LongRef NVARCHAR(500) NOT NULL   -- 1000 bytes, over the 900 WARN line, under the 1700 cap
);
CREATE NONCLUSTERED INDEX IX_WideKeys_LongRef ON dbo.WideKeys (LongRef);
GO

-- ---------------------------------------------------------------- 31 indexes on one table
CREATE TABLE dbo.OverIndexed (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OverIndexed PRIMARY KEY CLUSTERED,
    C01 INT, C02 INT, C03 INT, C04 INT, C05 INT, C06 INT, C07 INT, C08 INT,
    C09 INT, C10 INT, C11 INT, C12 INT, C13 INT, C14 INT, C15 INT, C16 INT,
    C17 INT, C18 INT, C19 INT, C20 INT, C21 INT, C22 INT, C23 INT, C24 INT,
    C25 INT, C26 INT, C27 INT, C28 INT, C29 INT, C30 INT, C31 INT
);
GO
DECLARE @i INT = 1, @s NVARCHAR(400);
WHILE @i <= 31
BEGIN
    SET @s = N'CREATE NONCLUSTERED INDEX IX_OverIndexed_C' + RIGHT('0' + CAST(@i AS VARCHAR(2)), 2)
           + N' ON dbo.OverIndexed (C' + RIGHT('0' + CAST(@i AS VARCHAR(2)), 2) + N');';
    EXEC sp_executesql @s;
    SET @i += 1;
END
GO

-- ---------------------------------------------------------------- missing index flood
CREATE TABLE dbo.Unindexed (
    Id  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Unindexed PRIMARY KEY CLUSTERED,
    A INT NOT NULL, B INT NOT NULL, C INT NOT NULL,
    D INT NOT NULL, E INT NOT NULL, F INT NOT NULL,
    Padding CHAR(200) NOT NULL DEFAULT ('x')
);
INSERT INTO dbo.Unindexed (A, B, C, D, E, F)
SELECT TOP (50000)
    ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 1000,
    ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 1000,
    ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 1000
FROM sys.all_objects a CROSS JOIN sys.all_objects b CROSS JOIN sys.all_objects c;

-- Six different equality predicates, so the optimizer asks for six different indexes.
--
-- THE `ORDER BY` IS LOAD-BEARING, and this took two attempts to get right. SQL Server does NOT
-- record missing-index data for a TRIVIALLY optimised plan, and a bare
-- `SELECT ... WHERE A = 7` over a single-index table is exactly that. The first version of this
-- script used `SELECT COUNT(*) ... WHERE A = 7 AND Padding > ''` and produced ZERO
-- recommendations, which would have shipped a scenario that silently failed to demonstrate the
-- third check. Adding an ORDER BY on a different column forces a sort, defeats the trivial
-- plan, and the DMV fills in. Measured: 0 recommendations before, 7 after.
DECLARE @sink INT;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE A = 7   ORDER BY B;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE B = 11  ORDER BY C;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE C = 23  ORDER BY D;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE D = 42  ORDER BY E;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE E = 99  ORDER BY F;
SELECT TOP (100) @sink = Id FROM dbo.Unindexed WHERE F = 123 ORDER BY A;
GO

-- ---------------------------------------------------------------- writes, for Get-UnusedIndexes
-- Get-UnusedIndexes wants reads = 0 AND writes > 0, so an index that was built and then never
-- touched again does NOT appear. Building the indexes after the initial load left every
-- user_updates at 0 and the script returned nothing, which is a scenario that silently fails to
-- demonstrate the thing it exists for. INSERTs fix it correctly: every index on the table is
-- maintained, so writes go up, and none is seeked, so reads stay at 0. An UPDATE with a WHERE
-- would have seeked an index and spoiled the reads = 0 half. Measured: 0 qualifying indexes
-- before, 34 after.
INSERT INTO dbo.Orders (CustomerId, OrderDate, Total)
SELECT TOP (500) ABS(CHECKSUM(NEWID())) % 500, '2026-09-01', 25.00
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

INSERT INTO dbo.WideKeys (LongRef)
SELECT TOP (200) REPLICATE(N'x', 200) + CAST(ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS NVARCHAR(10))
FROM sys.all_objects;

INSERT INTO dbo.OverIndexed
    (C01,C02,C03,C04,C05,C06,C07,C08,C09,C10,C11,C12,C13,C14,C15,C16,
     C17,C18,C19,C20,C21,C22,C23,C24,C25,C26,C27,C28,C29,C30,C31)
SELECT TOP (500) 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
                 21,22,23,24,25,26,27,28,29,30,31
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
GO

-- ---------------------------------------------------------------- prove the scenario is set
SELECT 'indexes on dbo.OverIndexed' AS check_name,
       COUNT(*) AS value, '32 expected (31 NC + clustered PK)' AS expected
FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.OverIndexed') AND type IN (1, 2)
UNION ALL
SELECT 'missing index recs for dbo.Unindexed',
       COUNT(*), '>= 5 needed to trip MISSING_INDEX_FLOOD'
FROM sys.dm_db_missing_index_details
WHERE database_id = DB_ID() AND object_id = OBJECT_ID('dbo.Unindexed')
UNION ALL
SELECT 'rows in dbo.Unindexed', COUNT(*), '50000' FROM dbo.Unindexed
UNION ALL
SELECT 'indexes unused but written (Get-UnusedIndexes)', COUNT(*), '34 expected'
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
LEFT JOIN sys.dm_db_index_usage_stats s
    ON s.object_id = i.object_id AND s.index_id = i.index_id AND s.database_id = DB_ID()
WHERE i.type_desc <> 'HEAP' AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
  AND t.is_ms_shipped = 0
  AND ISNULL(s.user_seeks,0) + ISNULL(s.user_scans,0) + ISNULL(s.user_lookups,0) = 0
  AND ISNULL(s.user_updates,0) > 0;
