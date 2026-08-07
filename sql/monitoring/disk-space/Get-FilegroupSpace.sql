/*
Script Name : Get-FilegroupSpace
Category    : monitoring
Purpose     : Allocated, used, and free space per filegroup across all online databases — ordered by lowest free percentage first.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-filegroup-space/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-sql-server-database-file-details/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#FgSpace') IS NOT NULL DROP TABLE #FgSpace;
CREATE TABLE #FgSpace (
    database_name NVARCHAR(128) NOT NULL,
    filegroup_name NVARCHAR(128) NOT NULL,
    filegroup_type VARCHAR(20) NOT NULL,
    is_default BIT NOT NULL,
    is_read_only BIT NOT NULL,
    file_count INT NOT NULL,
    size_mb DECIMAL(20,2) NOT NULL,
    used_mb DECIMAL(20,2) NOT NULL
);

DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE fg_cur CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id <> 2 /* exclude tempdb — no meaningful filegroup data */
      AND HAS_DBACCESS(name) = 1
    ORDER BY name;

OPEN fg_cur; FETCH NEXT FROM fg_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
    INSERT INTO #FgSpace (database_name, filegroup_name, filegroup_type,
                          is_default, is_read_only, file_count, size_mb, used_mb)
    SELECT
        DB_NAME(),
        fg.name,
        CASE fg.type
            WHEN ''FG'' THEN ''ROWS''
            WHEN ''FD'' THEN ''FILESTREAM''
            WHEN ''FX'' THEN ''MEMORY''
            ELSE fg.type
        END,
        fg.is_default,
        fg.is_read_only,
        COUNT(f.file_id),
        CAST(SUM(CAST(f.size AS BIGINT) * 8.0 / 1024) AS DECIMAL(20,2)),
        CAST(SUM(CAST(COALESCE(FILEPROPERTY(f.name, ''SpaceUsed''), 0) AS BIGINT) * 8.0 / 1024) AS DECIMAL(20,2))
    FROM sys.filegroups fg
    JOIN sys.database_files f ON f.data_space_id = fg.data_space_id
    GROUP BY fg.name, fg.type, fg.is_default, fg.is_read_only;';
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;
    FETCH NEXT FROM fg_cur INTO @db;
END;
CLOSE fg_cur; DEALLOCATE fg_cur;

SELECT
    database_name,
    filegroup_name,
    filegroup_type,
    is_default,
    is_read_only,
    file_count,
    size_mb,
    used_mb,
    CAST(size_mb - used_mb AS DECIMAL(20,2)) AS free_mb,
    CAST(CASE WHEN size_mb > 0 THEN (size_mb - used_mb) * 100.0 / size_mb ELSE 0 END AS DECIMAL(5,1)) AS free_pct
FROM #FgSpace
ORDER BY free_pct ASC, database_name, filegroup_name;

DROP TABLE #FgSpace;
