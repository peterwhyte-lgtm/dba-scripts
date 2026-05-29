# Category-first DBA layout

This folder is the main navigation layer for the repo.

## What lives here

Each category contains:
- sql/ for SSMS-ready queries, investigations, and operational checks
- powershell/ for automation, local validation, and operational helpers

## How to choose the right category

- performance-troubleshooting — slow queries, waits, blocking, and I/O pain
- storage-capacity-management — growth, disk space, log usage, and capacity reviews
- backups-and-recovery — backups, restores, backup age, and DR validation
- maintenance-and-reliability — integrity, fragmentation, TempDB, and maintenance routines
- configuration-and-environment — instance settings, jobs, memory, and environment checks
- security-and-permissions — permissions, roles, and access reviews
- high-availability-and-disaster-recovery — AG and failover checks
- dba-lab-scripts — lab test databases and local simulation helpers

## Suggested workflow

1. Start in categories/<area>/sql for analysis and reporting.
2. Use categories/<area>/powershell for local automation or validation.
3. Use sql-templates/operations for runbook-style templates and change-order style procedures.
4. Use helpers/ and tools/ for repo-wide utilities and maintenance tasks.
