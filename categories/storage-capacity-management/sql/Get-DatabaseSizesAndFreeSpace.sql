/*
Script Name : Get-DatabaseSizesAndFreeSpace
Description : Returns Database Sizes And Free Space for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
/*
Script Name : Database Sizes and Free Space
Description : Returns data/log sizes plus free-space estimates for all online databases.
Use        : Capacity planning, growth reviews, and storage reporting.
*/

SET NOCOUNT ON;

DECLARE @db sysname;
DECLARE @sql nvarchar(max);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
ORDER BY database_id;

CREATE TABLE #DatabaseSizeReview (
    database_name sysname,
    data_size_gb DECIMAL(18,2),
    log_size_gb DECIMAL(18,2),
    data_free_space_gb DECIMAL(18,2),
    log_free_space_gb DECIMAL(18,2),
    data_free_percent DECIMAL(5,2),
    log_free_percent DECIMAL(5,2)
);

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
        USE ' + QUOTENAME(@db) + N';

        INSERT INTO #DatabaseSizeReview (
            database_name,
            data_size_gb,
            log_size_gb,
            data_free_space_gb,
            log_free_space_gb,
            data_free_percent,
            log_free_percent
        )
        SELECT
            DB_NAME() AS database_name,
            CAST(SUM(CASE WHEN type_desc = ''ROWS'' THEN size END) * 8. / 1024 AS DECIMAL(12,2)) AS data_size_gb,
            CAST(SUM(CASE WHEN type_desc = ''LOG'' THEN size END) * 8. / 1024 AS DECIMAL(12,2)) AS log_size_gb,
            CAST(SUM(CASE WHEN type_desc = ''ROWS'' THEN size - FILEPROPERTY(name, ''SpaceUsed'') END) * 8. / 1024 AS DECIMAL(12,2)) AS data_free_space_gb,
            CAST(SUM(CASE WHEN type_desc = ''LOG'' THEN size - FILEPROPERTY(name, ''SpaceUsed'') END) * 8. / 1024 AS DECIMAL(12,2)) AS log_free_space_gb,
            CAST(100.0 * SUM(CASE WHEN type_desc = ''ROWS'' THEN size - FILEPROPERTY(name, ''SpaceUsed'') END)
                / NULLIF(SUM(CASE WHEN type_desc = ''ROWS'' THEN size END), 0) AS DECIMAL(5,2)) AS data_free_percent,
            CAST(100.0 * SUM(CASE WHEN type_desc = ''LOG'' THEN size - FILEPROPERTY(name, ''SpaceUsed'') END)
                / NULLIF(SUM(CASE WHEN type_desc = ''LOG'' THEN size END), 0) AS DECIMAL(5,2)) AS log_free_percent
        FROM sys.database_files;';

    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT *
FROM #DatabaseSizeReview
ORDER BY data_size_gb DESC, log_size_gb DESC;

DROP TABLE #DatabaseSizeReview;




