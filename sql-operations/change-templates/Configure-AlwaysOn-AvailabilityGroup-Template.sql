/*
Change Order / DBA Runbook: Configure an Availability Group

Purpose:
  Use this file as a production-friendly AG setup and validation runbook.
Business impact:
  Supports resilient failover and high-availability operations for SQL Server workloads.
Pre-checks:
  1. Confirm AG prerequisites are complete on every replica.
  2. Confirm WSFC, endpoint, and listener planning are approved.
  3. Verify database backups and recovery model requirements.
Execution notes:
  - Replace placeholders before execution.
  - Treat this as a checklist and validation document for the change record.
Validation:
  - Confirm AG metadata, replica settings, and availability mode.
Rollback:
  - Revert only after confirming a documented failback and operational approval path.
*/

SET NOCOUNT ON;

DECLARE @AGName sysname = N'YourAGName';
DECLARE @PrimaryReplica sysname = N'PrimaryServer\Instance';
DECLARE @SecondaryReplica sysname = N'SecondaryServer\Instance';

SELECT
    @AGName AS availability_group_name,
    @PrimaryReplica AS primary_replica,
    @SecondaryReplica AS secondary_replica;

-- Validation queries for AG prerequisites.
SELECT
    ag.name AS ag_name,
    ag.failure_condition_level,
    ag.health_check_timeout,
    ag.dbs_to_include,
    ag.dbs_to_exclude
FROM sys.availability_groups AS ag
WHERE ag.name = @AGName;

SELECT
    ar.replica_id,
    ar.name,
    ar.endpoint_url,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.primary_role_allow_connections_desc,
    ar.secondary_role_allow_connections_desc
FROM sys.availability_replicas AS ar
INNER JOIN sys.availability_groups AS ag ON ar.group_id = ag.group_id
WHERE ag.name = @AGName;
