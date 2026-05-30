/*
Script Name : Get-ServicesInformation
Category    : configuration-and-environment
Purpose     : Show SQL Server service state, startup type, and service account details.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    servicename,
    process_id,
    startup_type_desc,
    status_desc,
    last_startup_time,
    service_account,
    is_clustered,
    cluster_nodename,
    startup_type_desc + ' / ' + status_desc AS startup_status_summary
FROM sys.dm_server_services
ORDER BY servicename;



