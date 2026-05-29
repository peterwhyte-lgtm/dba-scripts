# DBA Script Catalog

This catalog reflects the current repo layout and the scripts most useful for real DBA operations.

## Performance troubleshooting
- categories/performance-troubleshooting/sql/Get-BlockingSessions.sql
- categories/performance-troubleshooting/sql/Get-DeadlockSummary.sql
- categories/performance-troubleshooting/sql/Get-LongRunningQueries.sql
- categories/performance-troubleshooting/sql/Get-TopCpuQueries.sql
- categories/performance-troubleshooting/sql/Get-WaitStatistics.sql
- categories/performance-troubleshooting/powershell/Get-BlockingSessions.ps1
- categories/performance-troubleshooting/powershell/Get-IndexFragmentation.ps1

## Backups and recovery
- categories/backups-and-recovery/sql/Get-BackupCoverage.sql
- categories/backups-and-recovery/sql/Get-BackupRestoreDurationEstimate.sql
- categories/backups-and-recovery/sql/Get-DatabaseBackupHistory.sql
- categories/backups-and-recovery/sql/Get-LastDatabaseBackupTimes.sql
- categories/backups-and-recovery/powershell/Backup-SqlDatabases.ps1
- categories/backups-and-recovery/powershell/Generate-RestoreScript.ps1

## Storage and capacity
- categories/storage-capacity-management/sql/Get-DatabaseSizesAndFreeSpace.sql
- categories/storage-capacity-management/sql/Get-DiskSpace.sql
- categories/storage-capacity-management/sql/Get-TransactionLogSizeAndUsage.sql
- categories/storage-capacity-management/powershell/Get-DiskSpaceSummary.ps1
- categories/storage-capacity-management/powershell/Get-OldestBackupFolderFiles.ps1

## Maintenance and reliability
- categories/maintenance-and-reliability/sql/Get-DatabaseHealth.sql
- categories/maintenance-and-reliability/sql/Get-DatabaseIntegrityChecks.sql
- categories/maintenance-and-reliability/sql/Get-IndexFragmentation.sql
- categories/maintenance-and-reliability/sql/Get-TempdbUsage.sql

## Configuration and environment
- categories/configuration-and-environment/sql/Get-InstanceConfigurationSnapshot.sql
- categories/configuration-and-environment/sql/Get-MemoryConfiguration.sql
- categories/configuration-and-environment/sql/Get-SqlAgentJobOverview.sql
- categories/configuration-and-environment/sql/Get-SqlAgentJobFailureSummary.sql
- categories/configuration-and-environment/powershell/Get-InstanceSnapshot.ps1
- categories/configuration-and-environment/powershell/Get-MemoryAndMaxdop.ps1

## Security and permissions
- categories/security-and-permissions/sql/Get-SysadminMembers.sql
- categories/security-and-permissions/sql/Get-UserPermissionsAudit.sql
- categories/security-and-permissions/sql/Get-DatabaseMailAndXpCmdShell.sql

## HA / DR
- categories/high-availability-and-disaster-recovery/sql/Get-AvailabilityGroupLatency.sql
- categories/high-availability-and-disaster-recovery/sql/Get-AvailabilityGroupReplicaState.sql

## DBA lab helpers
- categories/dba-lab-scripts/powershell/Run-CreateTestDatabases.ps1
- categories/dba-lab-scripts/powershell/Cleanup-TestDatabases.ps1
- categories/dba-lab-scripts/powershell/Generate-TestDatabases.ps1

## Operational templates
- sql-templates/operations/Update-Statistics-Template.sql
- sql-templates/operations/Configure-Cdc-Template.sql
- sql-templates/operations/Configure-Tde-Template.sql
- sql-templates/operations/Configure-Mirroring-Template.sql
- sql-templates/operations/Configure-AlwaysOn-AvailabilityGroup-Template.sql
- sql-templates/operations/Restore-Database-NoRecovery-Template.sql
- sql-templates/operations/Database-Consistency-Check-Template.sql

## Best starting points for a DBA triage session

1. `helpers/triage/Show-RepoOverview.ps1` — inventory the repo and identify the fastest path.
2. `categories/storage-capacity-management/sql/Get-DatabaseSizesAndFreeSpace.sql` — quick storage and growth review.
3. `categories/performance-troubleshooting/sql/Get-BlockingSessions.sql` — blocking and wait-first triage.
4. `categories/backups-and-recovery/sql/Get-BackupCoverage.sql` — backup coverage and recovery readiness.
5. `sql-templates/operations/Pre-OSUpgrade-Readiness.sql` — runbook-ready readiness checks.

### Example triage commands

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\triage\Show-RepoOverview.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\helpers\local-sql\Invoke-SqlFile.ps1 -ScriptPath .\categories\storage-capacity-management\sql\Get-DatabaseSizesAndFreeSpace.sql
```
