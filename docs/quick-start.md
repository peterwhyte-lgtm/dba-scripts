# Quick Start for Production DBA Work

Use this repo as a practical desktop toolkit for day-to-day SQL Server operations.

## Recommended workflow

1. Start with the category that matches the issue you are investigating.
2. Use SSMS-first SQL scripts for analysis and reporting.
3. Use PowerShell helpers for local automation or cleanup tasks.
4. Save output or notes to your incident runbook for repeatability.

## Good first scripts to try

- categories/performance-troubleshooting/sql/Get-LongRunningQueries.sql
- categories/storage-capacity-management/sql/Get-DatabaseSizesAndFreeSpace.sql
- categories/backups-and-recovery/sql/Get-BackupCoverage.sql
- categories/configuration-and-environment/sql/Get-InstanceConfigurationSnapshot.sql
- categories/security-and-permissions/sql/Get-SysadminMembers.sql

## Best way to start a DBA review

1. Run helpers/Show-RepoOverview.ps1 to see the repo inventory and the fastest entry points.
2. Use categories/<area>/sql for SSMS-ready analysis and category-specific checks.
3. Use categories/<area>/powershell for automation and local validation.
4. Use helpers/Clear-OutputFiles.ps1 when you want to reset output-files before a fresh review run.
5. Save outputs in your runbook so repeatable checks stay repeatable.
