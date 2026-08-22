/*
Script Name : Get-LoginMigrationParity
Category    : migration
Purpose     : Compare logins between two servers to verify a migration. Returns one comparable
              fingerprint row per login (SID, disabled state, deny connect, default database
              and language, password policy, password hash, server roles). Run on SOURCE and
              TARGET, export both as CSV, then diff. Catches what a login migration silently
              drops and a login count check cannot see.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-login-migration-parity/)
Requires    : VIEW ANY DEFINITION (VIEW SERVER STATE for full detail); CONTROL SERVER to
              compare password hashes, which are otherwise reported as 'no-permission'
Notes       : Get-PostMigrationValidation.sql compares COUNTS. A count matches while every
              login on the target is enabled, mapped to the wrong default database and
              carrying a fresh SID, so a count check passes a migration that is wrong.
              This script compares the attributes themselves.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: deliberately one flat, ordered, deterministic row per login so a plain text diff
  of two CSVs is the whole comparison. No cursors, no temp tables, no server-to-server
  connection: run it twice and diff, which works across an air gap and needs no linked server.

  Columns chosen because each one is something a real migration loses quietly:
    sid_hex           - a login recreated BY NAME gets a fresh SID, orphaning every database
                        user mapped to it. The single most common migration defect.
    is_disabled       - CREATE LOGIN always produces an ENABLED login. A disabled account
                        comes back live on the target with its original password valid.
    connect_denied    - an explicit DENY CONNECT SQL is a separate object from is_disabled
                        and is not carried by CREATE LOGIN either.
    default_database  - if it does not exist on the target the login cannot connect at all.
    default_language  - changes date parsing and error message language for that session.
    check_policy /
    check_expiration  - password policy silently relaxing on the target is a security finding.
    password_hash_id  - short fingerprint of the stored hash, so you can compare without
                        putting a full hash in a CSV that gets emailed around. Read it
                        carefully: the hash is SALTED, so the same password typed twice
                        produces two different hashes. A matching fingerprint therefore
                        proves the login was scripted WITH PASSWORD = <hash> HASHED and the
                        hash carried across. A differing one means somebody re-typed the
                        password, even if they typed the same password.
    server_roles      - fixed and user-defined server role membership, comma separated.

  HOW TO USE
    1. Run on SOURCE, save CSV.
    2. Run on TARGET, save CSV.
    3. Diff. Every row should match except password_hash_id for Windows logins (always 'n/a').
    4. Rows present on source and missing on target are logins that did not migrate.

  This script never writes. Nothing here changes a login.
*/

SELECT
    p.name                                             AS login_name,
    p.type_desc                                        AS login_type,

    -- A login recreated by name gets a new SID. This column is the one that matters most.
    CONVERT(nvarchar(200), p.sid, 1)                   AS sid_hex,

    p.is_disabled,

    -- DENY CONNECT SQL is a permission, not a flag on the principal, so it is easy to miss.
    CASE WHEN EXISTS (
            SELECT 1
            FROM sys.server_permissions sp
            WHERE sp.grantee_principal_id = p.principal_id
              AND sp.permission_name      = N'CONNECT SQL'
              AND sp.state                = 'D')      -- D = DENY
         THEN 1 ELSE 0 END                             AS connect_denied,

    ISNULL(p.default_database_name, N'(none)')         AS default_database,

    -- Does that default database actually exist here? Blank on the target means the login
    -- is created but cannot connect, which reads as an authentication problem.
    CASE WHEN p.default_database_name IS NULL THEN 'n/a'
         WHEN DB_ID(p.default_database_name) IS NULL THEN 'MISSING'
         ELSE 'present' END                            AS default_db_state,

    ISNULL(p.default_language_name, N'(none)')         AS default_language,

    CASE WHEN p.type = 'S' THEN CAST(sl.is_policy_checked     AS nvarchar(5)) ELSE 'n/a' END AS check_policy,
    CASE WHEN p.type = 'S' THEN CAST(sl.is_expiration_checked AS nvarchar(5)) ELSE 'n/a' END AS check_expiration,

    -- Fingerprint, not the hash: enough to prove the password came across, safe to share.
    CASE WHEN p.type <> 'S' THEN 'n/a'
         WHEN sl.password_hash IS NULL THEN 'no-permission'
         ELSE RIGHT(CONVERT(nvarchar(300), sl.password_hash, 1), 12)
    END                                                AS password_hash_id,

    STUFF((
        SELECT N', ' + r.name
        FROM sys.server_role_members srm
        INNER JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
        WHERE srm.member_principal_id = p.principal_id
        ORDER BY r.name
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'')  AS server_roles,

    CONVERT(varchar(19), p.create_date, 120)           AS create_date,
    CONVERT(varchar(19), p.modify_date, 120)           AS modify_date
FROM sys.server_principals AS p
LEFT JOIN sys.sql_logins   AS sl ON sl.principal_id = p.principal_id
-- 'S' = SQL_LOGIN, 'U' = WINDOWS_LOGIN, 'G' = WINDOWS_GROUP.
-- There is no type 'W'; using one silently returns no Windows logins at all.
WHERE p.type IN ('S', 'U', 'G')
  AND p.name NOT LIKE N'##%##'          -- certificate-backed internal principals
  AND p.name NOT LIKE N'NT SERVICE\%'   -- belong to the target's own installation
  AND p.name NOT LIKE N'NT AUTHORITY\%'
  AND p.name NOT LIKE N'BUILTIN\%'
ORDER BY p.name;
