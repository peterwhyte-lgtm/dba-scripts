/*
Script Name : Get-DatabaseIntegrityChecks
Category    : maintenance-and-reliability
Purpose     : Pre-check database readiness and configuration for integrity validation runs.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, db_datareader on msdb
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low
-- Use as a pre-check before running DBCC CHECKDB.


SELECT
    d.name AS database_name,
    d.state_desc,
    d.recovery_model_desc,
    d.user_access_desc,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.page_verify_option_desc,
    MAX(CASE WHEN bs.type = 'D' THEN bs.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN bs.type = 'I' THEN bs.backup_finish_date END) AS last_differential_backup,
    MAX(CASE WHEN bs.type = 'L' THEN bs.backup_finish_date END) AS last_log_backup
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS bs
    ON d.name = bs.database_name
GROUP BY
    d.name,
    d.state_desc,
    d.recovery_model_desc,
    d.user_access_desc,
    d.is_read_only,
    d.is_auto_close_on,
    d.is_auto_shrink_on,
    d.page_verify_option_desc
ORDER BY d.name;

/*
Example manual integrity run in SSMS:

DBCC CHECKDB ('YourDatabaseName') WITH NO_INFOMSGS, ALL_ERRORMSGS;

For a faster targeted check on one database:

DBCC CHECKDB ('YourDatabaseName') WITH TABLOCK, PHYSICAL_ONLY, NO_INFOMSGS;
*/




