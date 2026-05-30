/*
Script Name : Get-DatabaseRoleMembers
Category    : security-and-permissions
Purpose     : List database role memberships across all online user databases.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE, VIEW DEFINITION on each target database
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

IF OBJECT_ID('tempdb..#role_members') IS NOT NULL DROP TABLE #role_members;

CREATE TABLE #role_members (
    database_name NVARCHAR(128),
    role_name     NVARCHAR(128),
    is_fixed_role BIT,
    member_name   NVARCHAR(128),
    member_type   NVARCHAR(60),
    create_date   DATETIME
);

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
INSERT INTO #role_members
SELECT
    DB_NAME()          AS database_name,
    dr.name            AS role_name,
    dr.is_fixed_role,
    dp.name            AS member_name,
    dp.type_desc       AS member_type,
    dp.create_date
FROM sys.database_role_members AS drm
JOIN sys.database_principals   AS dr ON drm.role_principal_id   = dr.principal_id
JOIN sys.database_principals   AS dp ON drm.member_principal_id = dp.principal_id
WHERE dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'');
'
FROM sys.databases
WHERE database_id > 4
  AND state_desc  = 'ONLINE';

EXEC sys.sp_executesql @sql;

SELECT
    database_name,
    role_name,
    is_fixed_role,
    member_name,
    member_type,
    create_date
FROM #role_members
ORDER BY database_name, role_name, member_name;

DROP TABLE #role_members;
