/*
Script Name : Get-UndistributedCommands
Category    : high-availability
Purpose     : Shows the count of commands that have been read from the publisher transaction log
              but not yet delivered to subscribers. A high and growing count indicates Distribution
              Agent lag or failure. Run against the distribution database (-Database distribution).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-replication-agent-status/)
Requires    : db_owner or replmonitor role on the distribution database
*/
-- Blog: https://sqldba.blog/dba-scripts-get-replication-agent-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    publication                     AS publication_name,
    subscriber_db                   AS subscriber_database,
    COUNT(*)                        AS undistributed_commands
FROM dbo.MSdistribution_status
GROUP BY publication, subscriber_db
ORDER BY undistributed_commands DESC;
