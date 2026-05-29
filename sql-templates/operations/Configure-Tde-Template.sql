/*
Change Order / DBA Runbook: Configure TDE

Purpose:
  Enable Transparent Data Encryption for a target database using a documented, repeatable process.
Business impact:
  Protects database files at rest and supports compliance and security requirements.
Pre-checks:
  1. Confirm the SQL Server service account and backup plan for the certificate/private key.
  2. Confirm the DBA has CONTROL SERVER and CREATE ANY DATABASE permissions.
  3. Verify storage paths for the certificate and private key backups.
Execution notes:
  - Replace placeholder values before execution.
  - Run the master database section first, then the target database section.
Validation:
  - Confirm the database encryption state and encryption progress after the change.
Rollback:
  - Revert encryption only after confirming a valid backup and approved security procedure.
*/

SET NOCOUNT ON;
GO

DECLARE @TargetDatabase sysname = N'YourDatabase';
DECLARE @MasterKeyPassword nvarchar(128) = N'StrongMasterKeyPassword!';
DECLARE @CertificateName sysname = N'TDE_Certificate_YourDatabase';
DECLARE @BackupPath nvarchar(4000) = N'C:\SQLBackups\TDE\YourDatabase_Cert.cer';
DECLARE @PrivateKeyPath nvarchar(4000) = N'C:\SQLBackups\TDE\YourDatabase_Cert_PrivateKey.pvk';

-- Run the following section in master.
USE [master];
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = @MasterKeyPassword;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = @CertificateName)
BEGIN
    CREATE CERTIFICATE [TDE_Certificate_YourDatabase]
        WITH SUBJECT = N'TDE Certificate for YourDatabase';
END;
GO

BACKUP CERTIFICATE [TDE_Certificate_YourDatabase]
TO FILE = @BackupPath
WITH PRIVATE KEY (
    FILE = @PrivateKeyPath,
    ENCRYPTION BY PASSWORD = @MasterKeyPassword
);
GO

-- Run the following section in the target database.
USE [YourDatabase];
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_cryptographic_providers)
BEGIN
    CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE [TDE_Certificate_YourDatabase];
END;
GO

ALTER DATABASE [YourDatabase] SET ENCRYPTION ON;
GO

SELECT
    DB_NAME() AS database_name,
    is_encrypted,
    encryption_state,
    percent_complete,
    encryptor_type
FROM sys.dm_database_encryption_keys;
