/*
Script Name : Get-ServicesInformation
Category    : monitoring
Purpose     : SQL Server services — startup type, running status, and service account with
              risk flags. Surfaces manual/disabled startup on critical services and
              high-privilege service accounts (LocalSystem, SYSTEM, NetworkService).
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    servicename,
    startup_type_desc,
    status_desc,
    process_id,
    last_startup_time,
    service_account,
    is_clustered,
    cluster_nodename,
    -- Service account risk: built-in high-privilege accounts are a security concern
    CASE
        WHEN service_account IN ('LocalSystem', 'NT AUTHORITY\SYSTEM')
            THEN 'CRITICAL — LocalSystem has unrestricted local access; use a dedicated service account'
        WHEN service_account = 'NT AUTHORITY\NETWORK SERVICE'
            THEN 'WARN — NetworkService shares identity with other services; prefer a dedicated account'
        WHEN service_account LIKE 'NT Service\%'
            THEN 'OK — Managed Service Account (virtual account)'
        WHEN service_account LIKE '%$'
            THEN 'OK — Group Managed Service Account (gMSA)'
        WHEN service_account IS NULL OR service_account = ''
            THEN 'INFO — service account not visible (insufficient permissions or service not running)'
        ELSE 'OK — dedicated service account'
    END AS account_risk,
    -- Startup type: SQL Engine and Agent should be Automatic
    CASE
        WHEN startup_type_desc = 'Disabled'
            THEN 'CRITICAL — service is disabled; will not start after reboot'
        WHEN startup_type_desc = 'Manual'
             AND servicename NOT LIKE '%Browser%'
             AND servicename NOT LIKE '%Full-text%'
            THEN 'WARN — Manual startup; service will not auto-recover after reboot'
        WHEN startup_type_desc = 'Manual'
            THEN 'INFO — Manual startup (acceptable for Browser/Full-text if not required)'
        ELSE 'OK'
    END AS startup_risk,
    -- Running status
    CASE
        WHEN status_desc = 'Running'  THEN 'OK'
        WHEN status_desc = 'Stopped' AND servicename NOT LIKE '%Browser%'
            THEN 'WARN — service is stopped'
        ELSE 'INFO — ' + status_desc
    END AS running_status
FROM sys.dm_server_services
ORDER BY
    CASE
        WHEN servicename LIKE '%SQL Server (%' AND servicename NOT LIKE '%Agent%' THEN 1
        WHEN servicename LIKE '%SQL Server Agent%'                                 THEN 2
        ELSE 3
    END,
    servicename;
