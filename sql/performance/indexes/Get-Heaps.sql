/*
Script Name : Get-Heaps
Category    : performance
Purpose     : Lists tables with no clustered index (heaps) across all online user databases.
            Heaps cause full table scans on every non-covering lookup, accumulate
            forwarded records after row updates (degrading IO), and do not reclaim
            deleted row space without a REBUILD. Common source of hidden IO pressure
            that grows silently as data volumes increase.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-heaps/)
Requires    : VIEW DATABASE STATE (iterates each user database)
Notes       : Small read-only lookup tables as heaps are usually acceptable.
            Prioritise by reserved_mb and forwarded_fetch_count.
            forwarded_fetch_count = how often SQL Server chased a forwarded-record pointer
            since the last restart (IO cost). Counters reset on restart, so a low value on a
            recently restarted instance means "not measured yet", not "no forwarded records".
            has_primary_key = 0 means no PK exists at all — highest priority to fix.
            Fix: add a clustered index on the natural key, or add an identity
            column and cluster on that if no natural candidate exists.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #heaps (
    database_name           sysname       NOT NULL,
    schema_name             sysname       NOT NULL,
    table_name              sysname       NOT NULL,
    row_count               BIGINT        NOT NULL,
    reserved_mb             DECIMAL(10,2) NOT NULL,
    forwarded_fetch_count  BIGINT        NOT NULL,
    has_primary_key         BIT           NOT NULL
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #heaps (database_name, schema_name, table_name, row_count, reserved_mb, forwarded_fetch_count, has_primary_key)
SELECT
    DB_NAME(),
    s.name,
    t.name,
    SUM(p.rows),
    CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(10,2)),
    ISNULL(SUM(ios.forwarded_fetch_count), 0),
    CASE WHEN EXISTS (
        SELECT 1 FROM sys.indexes pk
        WHERE pk.object_id = t.object_id AND pk.is_primary_key = 1
    ) THEN 1 ELSE 0 END
FROM sys.tables        t
JOIN sys.schemas       s   ON  t.schema_id   = s.schema_id
JOIN sys.indexes       i   ON  t.object_id   = i.object_id AND i.type = 0
JOIN sys.partitions    p   ON  i.object_id   = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT JOIN sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ios
    ON  ios.object_id = i.object_id AND ios.index_id = i.index_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name, t.object_id
HAVING SUM(p.rows) > 0;
'
FROM sys.databases
WHERE state_desc  = 'ONLINE'
AND database_id > 4;

IF LEN(@sql) > 0
    EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    schema_name,
    table_name,
    row_count,
    reserved_mb,
    forwarded_fetch_count,
    has_primary_key
FROM   #heaps
ORDER BY has_primary_key ASC, reserved_mb DESC;

DROP TABLE #heaps;
