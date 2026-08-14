/*
Script Name : Get-ReplicationStatus
Category    : high-availability
Purpose     : Lists all publications and subscriptions from the distribution database, including
              publication type, subscriber server and database, subscription type, and status.
              Finds the distribution database automatically and returns a status row when
              replication is not configured, so it is safe to run from master on any instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-replication-status/)
Requires    : db_owner or replmonitor role on the distribution database
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE is_distributor = 1)
BEGIN
    SELECT 'Replication is not configured on this instance (no distribution database).' AS status;
END
ELSE
BEGIN
    -- The distribution database is usually named "distribution" but can be renamed;
    -- resolve it by flag. Multiple distribution databases are possible but rare —
    -- this reports the first by name.
    DECLARE @distdb sysname =
        (SELECT TOP (1) name FROM sys.databases WHERE is_distributor = 1 ORDER BY name);

    DECLARE @sql nvarchar(max) = N'
    SELECT
        pub.publisher_db AS publication_database,
        pub.publication AS publication_name,
        CASE pub.publication_type
            WHEN 0 THEN ''Transactional''
            WHEN 1 THEN ''Snapshot''
            WHEN 2 THEN ''Merge''
            ELSE ''Unknown''
        END AS publication_type,
        si.name AS subscriber_server,
        sub.subscriber_db AS subscriber_database,
        CASE sub.subscription_type
            WHEN 0 THEN ''Push''
            WHEN 1 THEN ''Pull''
            WHEN 2 THEN ''Anonymous''
            ELSE ''Unknown''
        END AS subscription_type,
        CASE sub.status
            WHEN 0 THEN ''Inactive''
            WHEN 1 THEN ''Subscribed''
            WHEN 2 THEN ''Active''
            ELSE ''Unknown''
        END AS subscription_status
    FROM ' + QUOTENAME(@distdb) + N'.dbo.MSpublications pub
    JOIN ' + QUOTENAME(@distdb) + N'.dbo.MSsubscriptions sub ON sub.publication_id = pub.publication_id
    JOIN ' + QUOTENAME(@distdb) + N'.dbo.MSsubscriber_info si ON si.id = sub.subscriber_id
    WHERE sub.subscriber_id > 0
    ORDER BY pub.publisher_db, pub.publication, si.name;';

    EXEC sys.sp_executesql @sql;
END
