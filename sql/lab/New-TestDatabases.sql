/*
Script Name : New-TestDatabases
Category    : dba-lab
Purpose     : Create multiple test databases with randomised names for lab and migration scenarios.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Creates objects
Impact      : High
Requires    : sysadmin or dbcreator
Notes       : Edit the DECLARE parameter block before running in SSMS.
              For PowerShell-driven creation use powershell\lab\New-MultipleDatabases.ps1.
              For parameterised execution from a script use powershell\lab\Run-CreateTestDatabases.ps1.
*/
-- WARNING: Creates databases — review @Count and @Prefix before running
SET NOCOUNT ON;
-- SAFE:Creates objects
-- IMPACT:High

-- Parameters (edit these values before running)
DECLARE @Count      INT     = 10;
DECLARE @Prefix     SYSNAME = N'migdb';
DECLARE @StartIndex INT     = 1;
DECLARE @SuffixLen  INT     = 8;
DECLARE @IndexWidth INT     = 3;
DECLARE @DataSizeMB INT     = 25;
DECLARE @LogSizeMB  INT     = 10;

DECLARE @i   INT = @StartIndex;
DECLARE @End INT = @i + @Count - 1;
DECLARE @Name SYSNAME;
DECLARE @SQL  NVARCHAR(MAX);

WHILE @i <= @End
BEGIN
    SET @Name = @Prefix + '_'
        + RIGHT(REPLICATE('0', @IndexWidth) + CAST(@i AS VARCHAR(20)), @IndexWidth)
        + '_' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), @SuffixLen);

    PRINT 'Creating: ' + @Name;

    IF DB_ID(@Name) IS NULL
    BEGIN
        BEGIN TRY
            SET @SQL = N'CREATE DATABASE [' + @Name + N'];';
            EXEC sp_executesql @SQL;

            DECLARE @DataLogical SYSNAME = NULL;
            DECLARE @LogLogical  SYSNAME = NULL;

            SELECT @DataLogical = mf.name FROM sys.master_files mf
            WHERE mf.database_id = DB_ID(@Name) AND mf.type_desc = 'ROWS';

            SELECT @LogLogical = mf.name FROM sys.master_files mf
            WHERE mf.database_id = DB_ID(@Name) AND mf.type_desc = 'LOG';

            IF @DataLogical IS NOT NULL
            BEGIN
                SET @SQL = N'ALTER DATABASE [' + @Name + N'] MODIFY FILE (NAME = N''' + @DataLogical
                    + ''', SIZE = ' + CAST(@DataSizeMB AS NVARCHAR(10)) + N'MB);';
                EXEC sp_executesql @SQL;
            END

            IF @LogLogical IS NOT NULL
            BEGIN
                SET @SQL = N'ALTER DATABASE [' + @Name + N'] MODIFY FILE (NAME = N''' + @LogLogical
                    + ''', SIZE = ' + CAST(@LogSizeMB AS NVARCHAR(10)) + N'MB);';
                EXEC sp_executesql @SQL;
            END
        END TRY
        BEGIN CATCH
            PRINT 'Failed creating ' + @Name + ': ' + ERROR_MESSAGE();
            THROW;
        END CATCH
    END

    SET @i += 1;
END

PRINT 'Done.';
