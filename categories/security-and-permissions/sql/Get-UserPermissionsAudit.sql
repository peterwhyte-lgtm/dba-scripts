/*
Script Name : Audit SQL Server Users and Permissions
Description : Returns User Permissions Audit for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

USE master;
GO

SELECT
    sp.name AS login_name,
    sp.type_desc AS login_type,
    sp.is_disabled
FROM sys.server_principals AS sp
WHERE sp.type IN ('S', 'U', 'G')
  AND sp.name NOT LIKE '##%'
ORDER BY sp.name;



