/*
Script Name : Generate-IndexMaintenanceScript
Category    : maintenance
Purpose     : Generates ALTER INDEX REBUILD / REORGANIZE statements for fragmented indexes
              across all online user databases. Review the output, then execute the
              maintenance_statement column in a maintenance window.
              Does not execute any maintenance — read-only.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW ANY DATABASE, plus access to each user database it inspects
              (db_datareader or VIEW DATABASE STATE); it opens every online user database
Notes       : REBUILD threshold >= 30 pct, REORGANIZE 10-29 pct.
              Indexes under 1000 pages excluded — fragmentation is not meaningful below this.
              ONLINE = ON requires Enterprise or Developer edition.
              Remove the WITH (ONLINE = ON) clause when running on Standard edition.
*/
-- SAFE:ReadOnly
-- IMPACT:Medium
SET NOCOUNT ON;

DECLARE @rebuild_pct  DECIMAL(5,1) = 30.0;  -- >= this %  → REBUILD
DECLARE @reorg_pct    DECIMAL(5,1) = 10.0;  -- >= this %  → REORGANIZE
DECLARE @min_pages    INT          = 1000;  -- skip indexes smaller than this page count

CREATE TABLE #frag (
    database_name  sysname      NOT NULL,
    schema_name    sysname      NOT NULL,
    table_name     sysname      NOT NULL,
    index_name     sysname      NOT NULL,
    frag_pct       DECIMAL(5,1) NOT NULL,
    page_count     BIGINT       NOT NULL,
    action         VARCHAR(10)  NOT NULL
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #frag (database_name, schema_name, table_name, index_name, frag_pct, page_count, action)
SELECT
    DB_NAME(), s.name, t.name, i.name,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)),
    ips.page_count,
    CASE WHEN ips.avg_fragmentation_in_percent >= ' + CAST(@rebuild_pct AS VARCHAR(10)) + N'
         THEN ''REBUILD'' ELSE ''REORGANIZE'' END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ips
JOIN sys.indexes i ON  ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.tables  t ON  i.object_id   = t.object_id
JOIN sys.schemas s ON  t.schema_id   = s.schema_id
WHERE i.name IS NOT NULL
  AND ips.page_count                   >= ' + CAST(@min_pages  AS VARCHAR(10)) + N'
  AND ips.avg_fragmentation_in_percent >= ' + CAST(@reorg_pct  AS VARCHAR(10)) + N';
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
    index_name,
    frag_pct,
    page_count,
    action,
    CASE action
        WHEN 'REBUILD'
            THEN 'USE ' + QUOTENAME(database_name)
                 + '; ALTER INDEX ' + QUOTENAME(index_name)
                 + ' ON '           + QUOTENAME(schema_name) + '.' + QUOTENAME(table_name)
                 + ' REBUILD WITH (ONLINE = ON);'  -- remove WITH clause on Standard edition
        ELSE
             'USE ' + QUOTENAME(database_name)
             + '; ALTER INDEX ' + QUOTENAME(index_name)
             + ' ON '           + QUOTENAME(schema_name) + '.' + QUOTENAME(table_name)
             + ' REORGANIZE;'
    END AS maintenance_statement
FROM   #frag
ORDER BY action DESC, frag_pct DESC;

DROP TABLE #frag;
