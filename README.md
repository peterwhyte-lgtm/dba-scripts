# DBA Scripts

A curated collection of practical SQL Server scripts used in real production environments.
Focused on performance, backups, configuration, security, and operational visibility.
Built for DBAs who need answers quickly.

This repository is designed to support the DBA Scripts section of the site and to give production SQL Server DBAs a fast, copy/paste-friendly toolkit for daily troubleshooting and operational checks.

## What is included

- Production-safe diagnostics and monitoring scripts for day-to-day DBA work
- Simple SSMS-first queries with inline comments and practical output
- PowerShell helpers for local ops, cleanup, and quick triage
- Lab/test scripts for environment setup and database generation
- A new category-first layout under categories/ for the DBA workflow
- Top-level helpers/ and tools/ folders for reusable utilities and repo maintenance

## What we are optimizing for

- Fast copy/paste into SSMS or Azure Data Studio
- Clear category grouping by real DBA task
- Easy handoff to other production DBAs
- A solid foundation for future blog posts and runbooks

## Production DBA categories

Use the category-first layout under categories/:

- categories/performance-troubleshooting/sql/ — SSMS-ready tuning and wait analysis queries
- categories/performance-troubleshooting/powershell/ — blocking, wait, and fragmentation helpers
- categories/storage-capacity-management/sql/ — database and storage usage queries
- categories/storage-capacity-management/powershell/ — disk and folder usage diagnostics
- categories/backups-and-recovery/sql/ — backup coverage and recovery checks
- categories/backups-and-recovery/powershell/ — backup and restore helpers
- categories/maintenance-and-reliability/sql/ — index and health maintenance queries
- categories/maintenance-and-reliability/powershell/ — health checks and reliability scripts
- categories/configuration-and-environment/sql/ — instance config and environment review queries
- categories/configuration-and-environment/powershell/ — instance and environment snapshots
- categories/security-and-permissions/sql/ — permission and role audit queries
- categories/security-and-permissions/powershell/ — security and access checks
- categories/high-availability-and-disaster-recovery/sql/ — AG and DR health checks
- categories/high-availability-and-disaster-recovery/powershell/ — AG and DR operational helpers
- categories/dba-lab-scripts/sql/ — test database creation and lab utility scripts
- categories/dba-lab-scripts/powershell/ — local/test database generation and cleanup helpers

## How to use this repo

1. Start in categories/<area>/sql for the SSMS-ready analysis scripts.
2. Use categories/<area>/powershell for automation and local troubleshooting helpers.
3. Use helpers/ for repo-wide utilities such as Show-RepoOverview.ps1 and Clear-OutputFiles.ps1.
4. Use tools/ for repo maintenance and catalog tasks.
5. Treat the scripts as production-safe starting points and extend them for your environment.

## Notes

- Folder names are lowercase for consistency.
- Scripts are grouped by real production DBA use case.
- The DBA Lab Scripts area is intentionally separate for test and simulation work.
- Use docs/ for runbooks, templates, and operational notes.
