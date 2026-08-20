/*
Script Name : Get-UndistributedCommands
Category    : high-availability
Purpose     : Shows how many commands have been written to the distribution database but not yet
              delivered to each subscriber. A high and growing backlog means the Distribution
              Agent is lagging or has failed. Finds the distribution database automatically and
              returns a status row when replication is not configured, so it is safe to run from
              master on any instance.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-replication-agent-status/)
Requires    : db_owner or replmonitor role on the distribution database
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
    -- resolve it by flag. Multiple distribution databases are possible but rare --
    -- this reads the first by name.
    DECLARE @distdb sysname =
        (SELECT TOP (1) name FROM sys.databases WHERE is_distributor = 1 ORDER BY name);

    -- MSdistribution_status is a VIEW that is already aggregated: one row per article per
    -- agent, carrying UndelivCmdsInDistDB (pending) and DelivCmdsInDistDB (delivered).
    -- SUM those columns -- COUNT(*) would return the number of articles, not the number of
    -- commands, which is a far smaller number that looks like a healthy backlog.
    -- The view carries no publication or subscriber name of its own; those live on
    -- MSdistribution_agents and are joined in on agent_id.
    DECLARE @sql nvarchar(max) = N'
    SELECT
        a.publisher_db  AS publisher_database,
        a.publication   AS publication_name,
        a.subscriber_db AS subscriber_database,
        SUM(s.UndelivCmdsInDistDB) AS undistributed_commands,
        SUM(s.DelivCmdsInDistDB)   AS delivered_commands
    FROM ' + QUOTENAME(@distdb) + N'.dbo.MSdistribution_status s
    JOIN ' + QUOTENAME(@distdb) + N'.dbo.MSdistribution_agents a ON a.id = s.agent_id
    GROUP BY a.publisher_db, a.publication, a.subscriber_db
    ORDER BY undistributed_commands DESC;';

    EXEC sys.sp_executesql @sql;
END
