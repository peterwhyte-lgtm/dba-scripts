/*
Script Name : Get-CertificatesAndKeys
Category    : security
Purpose     : Server-level certificates and asymmetric keys with expiry, usage detection,
              and lifecycle risk flags. Certificates created for TDE, AG encrypted endpoints,
              or linked server auth are commonly created and never monitored. An expired cert
              doesn't break TDE in memory but prevents restoring the database on another server.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/)
Requires    : VIEW ANY DATABASE, VIEW ANY DEFINITION
*/
-- Blog: https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT *
FROM (
    -- Server-level certificates
    SELECT
        CAST('CERTIFICATE' AS NVARCHAR(30)) AS object_type,
        c.name COLLATE DATABASE_DEFAULT AS cert_or_key_name,
        DB_NAME() AS database_context,
        c.pvt_key_encryption_type_desc COLLATE DATABASE_DEFAULT AS key_protection,
        CONVERT(NVARCHAR(128), c.thumbprint, 1) AS thumbprint,
        c.start_date,
        c.expiry_date,
        DATEDIFF(DAY, GETDATE(), c.expiry_date) AS days_until_expiry,
        c.subject COLLATE DATABASE_DEFAULT AS subject_or_algorithm,
        CASE
            WHEN EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys ek
                         WHERE ek.encryptor_thumbprint = c.thumbprint)
            THEN 'TDE — protects database encryption key'
            WHEN c.pvt_key_encryption_type_desc = 'NO_PRIVATE_KEY'
            THEN 'Public cert only (no private key — cannot sign or decrypt)'
            ELSE 'Unidentified — review usage manually'
        END AS used_for,
        ISNULL(
            STUFF((
                SELECT ', ' + DB_NAME(ek2.database_id)
                FROM sys.dm_database_encryption_keys AS ek2
                WHERE ek2.encryptor_thumbprint = c.thumbprint
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(500)'), 1, 2, ''),
            NULL) AS tde_databases,
        CASE
            WHEN c.expiry_date < GETDATE()
            THEN 'CRITICAL — EXPIRED; TDE databases cannot be restored elsewhere with this cert'
            WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 30
            THEN 'CRITICAL — expires in ' + CAST(DATEDIFF(DAY, GETDATE(), c.expiry_date) AS VARCHAR) + ' days'
            WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90
            THEN 'WARN — expires in ' + CAST(DATEDIFF(DAY, GETDATE(), c.expiry_date) AS VARCHAR) + ' days'
            WHEN c.pvt_key_encryption_type_desc = 'NO_PRIVATE_KEY'
            THEN 'INFO — no private key; verify this is intentional'
            ELSE 'OK'
        END AS status
    FROM sys.certificates AS c
    WHERE c.name NOT LIKE '##%'

    UNION ALL

    -- Asymmetric keys
    SELECT
        CAST('ASYMMETRIC_KEY' AS NVARCHAR(30)),
        ak.name COLLATE DATABASE_DEFAULT,
        DB_NAME(),
        ak.pvt_key_encryption_type_desc COLLATE DATABASE_DEFAULT,
        CONVERT(NVARCHAR(128), ak.thumbprint, 1),
        NULL,
        NULL,
        NULL,
        (ak.algorithm_desc COLLATE DATABASE_DEFAULT)
            + ' / ' + CAST(ak.key_length AS VARCHAR) + '-bit',
        'Asymmetric key — check if used for column encryption or EKM',
        NULL,
        'INFO — verify usage and that the key is backed up'
    FROM sys.asymmetric_keys AS ak
    WHERE ak.name NOT LIKE '##%'

    UNION ALL

    -- Open symmetric keys in current session
    SELECT
        CAST('OPEN_SYMMETRIC_KEY' AS NVARCHAR(30)),
        ok.key_name COLLATE DATABASE_DEFAULT,
        ok.database_name COLLATE DATABASE_DEFAULT,
        'OPEN_IN_SESSION',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        'Symmetric key currently open in session',
        NULL,
        CASE WHEN ok.key_name LIKE '##%'
             THEN 'INFO — internal system key'
             ELSE 'WARN — symmetric key is open; verify it is required for current operation'
        END
    FROM sys.openkeys AS ok
) AS all_keys
ORDER BY
    CASE WHEN status LIKE 'CRITICAL%' THEN 1
         WHEN status LIKE 'WARN%' THEN 2
         WHEN status LIKE 'INFO%' THEN 3
         ELSE 4 END,
    days_until_expiry,
    cert_or_key_name;
