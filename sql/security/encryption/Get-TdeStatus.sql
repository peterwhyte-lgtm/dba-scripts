/*
Script Name : Get-TdeStatus
Category    : security
Purpose     : Transparent Data Encryption (TDE) status across all databases. Includes
              encryption state, key algorithm, encryptor type, and tempdb encryption
              side-effect awareness.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-certificates-keys-and-tde-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    d.name AS database_name,
    d.is_encrypted AS tde_enabled,
    ISNULL(ek.encryption_state_desc, 'UNENCRYPTED') AS encryption_state,
    ek.key_algorithm,
    ek.key_length,
    ek.encryptor_type,
    ek.encryptor_thumbprint,
    ek.percent_complete,
    ek.create_date AS key_create_date,
    ek.set_date AS key_set_date,
    ek.regenerate_date AS key_regenerate_date,
    c.name AS certificate_name,
    c.expiry_date AS certificate_expiry,
    CASE
        WHEN d.database_id = 2 AND d.is_encrypted = 1
            THEN 'INFO — TempDB is encrypted because at least one user database uses TDE'
        WHEN ek.encryption_state = 3 AND d.is_encrypted = 1
            THEN 'OK — encrypted'
        WHEN ek.encryption_state IN (2, 4)
            THEN 'INFO — encryption/key-change in progress (' + CAST(ek.percent_complete AS VARCHAR) + '% complete)'
        WHEN ek.encryption_state = 5
            THEN 'INFO — decryption in progress'
        WHEN d.is_encrypted = 0 AND d.database_id NOT IN (1,2,3,4)
            THEN 'INFO — not encrypted'
        ELSE 'OK'
    END AS status
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS ek
    ON ek.database_id = d.database_id
LEFT JOIN master.sys.certificates AS c
    ON c.thumbprint = ek.encryptor_thumbprint
WHERE d.database_id NOT IN (3) -- exclude model; include tempdb to show side-effect
ORDER BY
    d.is_encrypted DESC,
    d.name;
