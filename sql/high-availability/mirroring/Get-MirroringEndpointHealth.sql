/*
Script Name : Get-MirroringEndpointHealth
Category    : high-availability
Purpose     : Returns the state, port, role, and authentication configuration of the database
              mirroring endpoint. If the endpoint is not STARTED, mirroring cannot communicate.
              Run on both the principal and mirror server during troubleshooting.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/)
Requires    : VIEW SERVER STATE
*/
-- Blog: https://sqldba.blog/dba-scripts-get-mirroring-endpoint-health-and-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    e.name AS endpoint_name,
    e.state_desc AS endpoint_state,
    d.role_desc AS endpoint_role,
    tcp.port AS port_number,
    d.connection_auth_desc AS connection_auth,
    d.encryption_algorithm_desc AS encryption_algorithm
FROM sys.endpoints e
JOIN sys.database_mirroring_endpoints d ON d.endpoint_id = e.endpoint_id
JOIN sys.tcp_endpoints tcp ON tcp.endpoint_id = e.endpoint_id;
