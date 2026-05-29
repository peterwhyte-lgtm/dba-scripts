# DBA Script Catalog

This catalog reflects the current repo layout and the scripts most useful for real DBA operations.

## Performance troubleshooting
- sql/performance-troubleshooting/Get-BlockingSessions.sql
- sql/performance-troubleshooting/Get-DeadlockSummary.sql
- sql/performance-troubleshooting/Get-LongRunningQueries.sql
- sql/performance-troubleshooting/Get-TopCpuQueries.sql
- sql/performance-troubleshooting/Get-WaitStatistics.sql
- powershell/performance-troubleshooting/Get-BlockingSessions.ps1
- powershell/performance-troubleshooting/Get-IndexFragmentation.ps1

## Backups and recovery
- sql/backups-and-recovery/Get-BackupCoverage.sql
- sql/backups-and-recovery/Get-BackupRestoreDurationEstimate.sql
- sql/backups-and-recovery/Get-DatabaseBackupHistory.sql
- sql/backups-and-recovery/Get-LastDatabaseBackupTimes.sql
- powershell/backups-and-recovery/Backup-SqlDatabases.ps1
- powershell/backups-and-recovery/Generate-RestoreScript.ps1

## Storage and capacity
- sql/storage-capacity-management/Get-DatabaseSizesAndFreeSpace.sql
- sql/storage-capacity-management/Get-DiskSpace.sql
- sql/storage-capacity-management/Get-TransactionLogSizeAndUsage.sql
- powershell/storage-capacity-management/Get-DiskSpaceSummary.ps1
- powershell/storage-capacity-management/Get-OldestBackupFolderFiles.ps1

## Maintenance and reliability
- sql/maintenance-and-reliability/Get-DatabaseHealth.sql
- sql/maintenance-and-reliability/Get-DatabaseIntegrityChecks.sql
- sql/maintenance-and-reliability/Get-IndexFragmentation.sql
- sql/maintenance-and-reliability/Get-TempdbUsage.sql

## Configuration and environment
- sql/configuration-and-environment/Get-InstanceConfigurationSnapshot.sql
- sql/configuration-and-environment/Get-MemoryConfiguration.sql
- sql/configuration-and-environment/Get-SqlAgentJobOverview.sql
- sql/configuration-and-environment/Get-SqlAgentJobFailureSummary.sql
- powershell/configuration-and-environment/Get-InstanceSnapshot.ps1
- powershell/configuration-and-environment/Get-MemoryAndMaxdop.ps1

## Security and permissions
- sql/security-and-permissions/Get-SysadminMembers.sql
- sql/security-and-permissions/Get-UserPermissionsAudit.sql
- sql/security-and-permissions/Get-DatabaseMailAndXpCmdShell.sql

## HA / DR
- sql/high-availability-and-disaster-recovery/Get-AvailabilityGroupLatency.sql
- sql/high-availability-and-disaster-recovery/Get-AvailabilityGroupReplicaState.sql

## DBA lab helpers
- powershell/dba-lab-scripts/Run-CreateTestDatabases.ps1
- powershell/dba-lab-scripts/Cleanup-TestDatabases.ps1
- powershell/dba-lab-scripts/Generate-TestDatabases.ps1

## Best starting points for a DBA triage session
1. powershell/helpers/Show-RepoOverview.ps1
2. sql/storage-capacity-management/Get-DatabaseSizesAndFreeSpace.sql
3. sql/performance-troubleshooting/Get-BlockingSessions.sql
4. sql/backups-and-recovery/Get-BackupCoverage.sql
