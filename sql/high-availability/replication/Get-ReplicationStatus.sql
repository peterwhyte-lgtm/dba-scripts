/*
Script Name : Get-ReplicationStatus
Category    : high-availability
Purpose     : Lists all publications and subscriptions from the distribution database, including
              publication type, subscriber server and database, subscription type, and status.
              Run against the distribution database (-Database distribution).
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-replication-status/)
Requires    : db_owner or replmonitor role on the distribution database
*/
-- Blog: https://sqldba.blog/dba-scripts-get-replication-status/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

SELECT
    pub.publisher_db                                    AS publication_database,
    pub.publication                                     AS publication_name,
    CASE pub.publication_type
        WHEN 0 THEN 'Transactional'
        WHEN 1 THEN 'Snapshot'
        WHEN 2 THEN 'Merge'
        ELSE 'Unknown'
    END                                                 AS publication_type,
    si.name                                             AS subscriber_server,
    sub.subscriber_db                                   AS subscriber_database,
    CASE sub.subscription_type
        WHEN 0 THEN 'Push'
        WHEN 1 THEN 'Pull'
        WHEN 2 THEN 'Anonymous'
        ELSE 'Unknown'
    END                                                 AS subscription_type,
    CASE sub.status
        WHEN 0 THEN 'Inactive'
        WHEN 1 THEN 'Subscribed'
        WHEN 2 THEN 'Active'
        ELSE 'Unknown'
    END                                                 AS subscription_status
FROM dbo.MSpublications          pub
JOIN dbo.MSsubscriptions         sub ON sub.publication_id = pub.publication_id
JOIN dbo.MSsubscriber_info       si  ON si.id              = sub.subscriber_id
WHERE sub.subscriber_id > 0
ORDER BY pub.publisher_db, pub.publication, si.name;
