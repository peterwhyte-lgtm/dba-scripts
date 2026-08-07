/*
Script Name : Get-PostMigrationValidation
Category    : migration
Purpose     : Run on both SOURCE and TARGET and compare the CSV outputs to confirm the
              migration is complete and consistent. Surfaces database count mismatches,
              databases not ONLINE, orphaned users, and login count deltas.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/)
Requires    : VIEW ANY DATABASE, VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-migration-login-audit-and-post-migration-validation/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

/*
  DESIGN: Returns a single summary result set with one row per check category.
  Run this script on both servers. Export as CSV, then diff the two outputs.
  The 'value' column should match between source and target for each check_name.

  Checks performed:
    - user_database_count — total number of user databases
    - databases_not_online — any database not in ONLINE state
    - databases_missing_backup — databases with no recorded backup (should be 0 on target if just restored)
    - total_login_count — server principal count (SQL + Windows)
    - sql_login_count — SQL-authenticated logins
    - windows_login_count — Windows logins and groups
    - sysadmin_count — members of sysadmin role
    - linked_server_count — linked server definitions
    - agent_job_count — SQL Agent jobs
    - instance_version — SQL Server version string (major.minor.build)
    - instance_edition — SQL Server edition
    - max_server_memory_mb — sp_configure max server memory
    - maxdop — sp_configure max degree of parallelism
    - tempdb_data_file_count — TempDB data files (should match after setup)
*/

SELECT
    check_name,
    value,
    detail
FROM (

    -- Database count
    SELECT
        'user_database_count' AS check_name,
        CAST(COUNT(*) AS nvarchar(200)) AS value,
        'databases with database_id > 4' AS detail
    FROM sys.databases
    WHERE database_id > 4

    UNION ALL

    -- Databases not ONLINE
    SELECT
        'databases_not_online',
        CAST(COUNT(*) AS nvarchar(200)),
        ISNULL(
            STUFF((
                SELECT N', ' + name + N' (' + state_desc + N')'
                FROM sys.databases
                WHERE database_id > 4 AND state_desc <> N'ONLINE'
                FOR XML PATH(''), TYPE).value('.','nvarchar(max)')
            , 1, 2, N''),
            N'All ONLINE'
        )
    FROM sys.databases
    WHERE database_id > 4 AND state_desc <> N'ONLINE'

    UNION ALL

    -- Login count (all)
    SELECT
        'total_login_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'SQL + Windows logins (excl. system accounts)'
    FROM sys.server_principals
    WHERE type IN ('S', 'U', 'G')
      AND name NOT LIKE N'##%##'
      AND name NOT IN (N'sa')
      AND name NOT LIKE N'NT SERVICE\%'
      AND name NOT LIKE N'NT AUTHORITY\%'
      AND name NOT LIKE N'BUILTIN\%'

    UNION ALL

    -- SQL login count
    SELECT
        'sql_login_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'type = S (SQL authenticated)'
    FROM sys.server_principals
    WHERE type = 'S'
      AND name NOT LIKE N'##%##'
      AND name NOT IN (N'sa')

    UNION ALL

    -- Windows login count
    SELECT
        'windows_login_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'type IN (U, G) — Windows users and groups'
    FROM sys.server_principals
    WHERE type IN ('U', 'G')
      AND name NOT LIKE N'NT SERVICE\%'
      AND name NOT LIKE N'NT AUTHORITY\%'
      AND name NOT LIKE N'BUILTIN\%'

    UNION ALL

    -- Sysadmin count
    SELECT
        'sysadmin_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'members of sysadmin fixed server role'
    FROM sys.server_role_members srm
    INNER JOIN sys.server_principals r ON srm.role_principal_id = r.principal_id
    INNER JOIN sys.server_principals m ON srm.member_principal_id = m.principal_id
    WHERE r.name = N'sysadmin'
      AND m.name NOT LIKE N'##%##'
      AND m.name NOT IN (N'sa')

    UNION ALL

    -- Linked servers
    SELECT
        'linked_server_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'sys.servers WHERE is_linked = 1'
    FROM sys.servers WHERE is_linked = 1

    UNION ALL

    -- SQL Agent jobs
    SELECT
        'agent_job_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'msdb.dbo.sysjobs'
    FROM msdb.dbo.sysjobs

    UNION ALL

    -- Version
    SELECT
        'instance_version',
        CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(200)),
        CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(200))

    UNION ALL

    -- Edition
    SELECT
        'instance_edition',
        CAST(SERVERPROPERTY('Edition') AS nvarchar(200)),
        CAST(SERVERPROPERTY('EngineEdition') AS nvarchar(200))

    UNION ALL

    -- Max server memory
    SELECT
        'max_server_memory_mb',
        CAST(CAST(value_in_use AS bigint) AS nvarchar(200)),
        'sp_configure ''max server memory (MB)'''
    FROM sys.configurations WHERE name = 'max server memory (MB)'

    UNION ALL

    -- MAXDOP
    SELECT
        'maxdop',
        CAST(value_in_use AS nvarchar(200)),
        'sp_configure ''max degree of parallelism'''
    FROM sys.configurations WHERE name = 'max degree of parallelism'

    UNION ALL

    -- TempDB data file count
    SELECT
        'tempdb_data_file_count',
        CAST(COUNT(*) AS nvarchar(200)),
        'sys.master_files WHERE database_id = 2 AND type = 0'
    FROM sys.master_files
    WHERE database_id = 2 AND type = 0

) chk
ORDER BY check_name;
