/*
Change Order / DBA Runbook: Configure Mirroring

Purpose:
  Provide a copy/paste-ready runbook entry for database mirroring setup and validation.
Business impact:
  Supports high availability and failover readiness for mission-critical databases.
Pre-checks:
  1. Confirm endpoints, certificates, and service accounts are already configured on both partners.
  2. Verify the witness and failover strategy for the database.
  3. Review maintenance windows and partner readiness before starting.
Execution notes:
  - Replace placeholders before execution.
  - Use this template as a runbook reference and validation checklist.
Validation:
  - Confirm mirroring state, partner name, safety level, and witness configuration.
Rollback:
  - Remove the mirroring session only after confirming the business and operational approval path.
*/

SET NOCOUNT ON;

DECLARE @DatabaseName sysname = N'YourDatabase';
DECLARE @WitnessServer sysname = N'WitnessServer\Instance';
DECLARE @PrincipalServer sysname = N'PrincipalServer\Instance';
DECLARE @MirrorServer sysname = N'MirrorServer\Instance';

SELECT
    @DatabaseName AS database_name,
    @PrincipalServer AS principal_server,
    @MirrorServer AS mirror_server,
    @WitnessServer AS witness_server;

-- Validation query for current mirroring state.
SELECT
    d.name AS database_name,
    dm.mirroring_state_desc,
    dm.mirroring_role_desc,
    dm.mirroring_safety_level_desc,
    dm.mirroring_partner_name,
    dm.mirroring_witness_name,
    dm.mirroring_failover_lsn
FROM sys.database_mirroring AS dm
INNER JOIN sys.databases AS d ON dm.database_id = d.database_id
WHERE d.name = @DatabaseName;
