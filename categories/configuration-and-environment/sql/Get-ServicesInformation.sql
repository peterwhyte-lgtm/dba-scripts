/*
Script Name : Get SQL Server Services Information
Description : Returns SQL Server service state and startup details for support and patch planning.
Use        : Service review, cluster checks, and maintenance preparation.
*/

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



