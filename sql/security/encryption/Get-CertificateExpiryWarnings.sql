/*
Script Name : Get-CertificateExpiryWarnings
Category    : security
Purpose     : All user-managed certificates across server and user databases with days until expiry.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/)
Requires    : VIEW ANY DATABASE, VIEW DATABASE STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#CertInfo') IS NOT NULL DROP TABLE #CertInfo;
CREATE TABLE #CertInfo (
    cert_scope NVARCHAR(128) NOT NULL,
    cert_name NVARCHAR(128) NOT NULL,
    subject NVARCHAR(500),
    issuer_name NVARCHAR(500),
    start_date DATETIME,
    expiry_date DATETIME,
    days_until_expiry INT,
    expiry_status VARCHAR(10) NOT NULL,
    pvt_key_type NVARCHAR(60),
    is_service_broker BIT,
    pvt_key_last_backup DATETIME
);

/* ── Server-level certs in master (TDE, backup encryption, SB endpoint) ─── */
INSERT INTO #CertInfo
SELECT
    N'master' AS cert_scope,
    name AS cert_name,
    subject,
    issuer_name,
    start_date,
    expiry_date,
    DATEDIFF(DAY, GETDATE(), expiry_date),
    CASE
        WHEN expiry_date < GETDATE() THEN 'EXPIRED'
        WHEN DATEDIFF(DAY, GETDATE(), expiry_date) <= 30 THEN 'CRITICAL'
        WHEN DATEDIFF(DAY, GETDATE(), expiry_date) <= 90 THEN 'WARNING'
        ELSE 'OK'
    END,
    pvt_key_encryption_type_desc,
    is_active_for_begin_dialog,
    pvt_key_last_backup_date
FROM sys.certificates
WHERE name NOT LIKE '##%';

/* ── Per-database certs (Service Broker, column encryption) ─────────────── */
DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE cert_cur CURSOR FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
      AND HAS_DBACCESS(name) = 1
    ORDER BY name;

OPEN cert_cur; FETCH NEXT FROM cert_cur INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
    INSERT INTO #CertInfo
    SELECT
        DB_NAME(), name, subject, issuer_name, start_date, expiry_date,
        DATEDIFF(DAY, GETDATE(), expiry_date),
        CASE
            WHEN expiry_date < GETDATE() THEN ''EXPIRED''
            WHEN DATEDIFF(DAY, GETDATE(), expiry_date) <= 30 THEN ''CRITICAL''
            WHEN DATEDIFF(DAY, GETDATE(), expiry_date) <= 90 THEN ''WARNING''
            ELSE ''OK''
        END,
        pvt_key_encryption_type_desc, is_active_for_begin_dialog, pvt_key_last_backup_date
    FROM sys.certificates
    WHERE name NOT LIKE ''##%'';';
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;
    FETCH NEXT FROM cert_cur INTO @db;
END;
CLOSE cert_cur; DEALLOCATE cert_cur;

SELECT
    cert_scope,
    cert_name,
    subject,
    issuer_name,
    expiry_date,
    days_until_expiry,
    expiry_status,
    pvt_key_type,
    is_service_broker,
    pvt_key_last_backup
FROM #CertInfo
ORDER BY days_until_expiry ASC, cert_scope, cert_name;

DROP TABLE #CertInfo;
