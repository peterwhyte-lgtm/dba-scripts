/*
Script Name : New-TestDatabases
Description : Returns New Test Databases for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
/*
Creates many SQL Server databases with randomized names and configurable sizes.

Run this script directly in SSMS (T-SQL). Edit the parameter block below
to set the desired values before executing; this file is a general-purpose
database creation helper for test/migration scenarios.

Parameters (edit in SSMS):
- @Count       : number of databases to create (default: 10)
- @Prefix      : name prefix (default: 'migdb')
- @StartIndex  : starting numeric index (default: 1)
- @SuffixLen   : length of random suffix appended to names (default: 8)
- @DataSizeMB  : initial data file size in MB (default: 25)
- @LogSizeMB   : initial log file size in MB (default: 10)
- @IndexWidth  : zero-pad width for the numeric index (e.g. 3 => 001)

Behavior:
- Each database is created and then the primary data and log files are
	resized to the requested sizes. Database names use the form:
	<Prefix>_<Index>_<RandomSuffix> (index is zero-padded to @IndexWidth).
- The script skips creation for databases that already exist.

Warnings:
- Creating many databases requires significant disk space and time.
- Run as a login with appropriate privileges (sysadmin recommended).

CSV output:
- This script does not export a CSV list of created names. For CSV output,
	use the PowerShell helper: MSSQL/create-multiple-databases.ps1
*/

-- Parameters (edit these values before running in SSMS)
DECLARE @Count INT = 10;            -- number of databases to create (default smaller for safety)
DECLARE @Prefix SYSNAME = N'migdb'; -- name prefix
DECLARE @StartIndex INT = 1;        -- starting index
DECLARE @SuffixLen INT = 8;         -- length of random suffix
DECLARE @IndexWidth INT = 3;        -- numeric width for the middle index (e.g. 3 => 001, 002)
DECLARE @DataSizeMB INT = 25;       -- initial data file size in MB
DECLARE @LogSizeMB INT = 10;        -- initial log file size in MB

DECLARE @i INT = @StartIndex;
DECLARE @End INT = @i + @Count - 1;
DECLARE @Name SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

WHILE @i <= @End
BEGIN
		SET @Name = @Prefix + '_' + RIGHT(REPLICATE('0', @IndexWidth) + CAST(@i AS VARCHAR(20)), @IndexWidth)
			+ '_' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()),'-',''), @SuffixLen);

		PRINT 'Creating: ' + @Name;

		IF DB_ID(@Name) IS NULL
		BEGIN
			BEGIN TRY
				-- Create database using defaults (no FILENAME) so SQL Server places files in its default locations
				SET @SQL = N'CREATE DATABASE [' + @Name + N'];';
				EXEC sp_executesql @SQL;

				-- Resize the created files to the requested sizes by logical name
				DECLARE @DataLogical SYSNAME = NULL;
				DECLARE @LogLogical SYSNAME = NULL;

				SELECT @DataLogical = mf.name
				FROM sys.master_files mf
				WHERE mf.database_id = DB_ID(@Name) AND mf.type_desc = 'ROWS';

				SELECT @LogLogical = mf.name
				FROM sys.master_files mf
				WHERE mf.database_id = DB_ID(@Name) AND mf.type_desc = 'LOG';

				IF @DataLogical IS NOT NULL
				BEGIN
					SET @SQL = N'ALTER DATABASE [' + @Name + N'] MODIFY FILE (NAME = N''' + @DataLogical + ''', SIZE = ' + CAST(@DataSizeMB AS NVARCHAR(10)) + N'MB);';
					EXEC sp_executesql @SQL;
				END

				IF @LogLogical IS NOT NULL
				BEGIN
					SET @SQL = N'ALTER DATABASE [' + @Name + N'] MODIFY FILE (NAME = N''' + @LogLogical + ''', SIZE = ' + CAST(@LogSizeMB AS NVARCHAR(10)) + N'MB);';
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





