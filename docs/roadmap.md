# DBA Scripts Roadmap

This repo is being shaped as a practical production DBA toolkit for the blog and for day-to-day SQL Server operations.

## What the repo already covers

The current layout now includes practical coverage for:
- performance troubleshooting and wait/blocking analysis
- storage and capacity review
- backup and restore basics and readiness checks
- configuration, memory, MAXDOP, and SQL Agent reviews
- security and permission auditing
- HA/DR and lab-style database generation
- integrity/readiness checks before DBCC validation work
- category-first navigation under categories/
- top-level helpers/ and tools/ for quick repo operations and AI-assisted work

## What we completed in this pass

1. Reworked the repo into a DBA-first category structure with SQL and PowerShell under each category.
2. Added top-level helpers for repo overview, output cleanup, quick task routing, script discovery, and script generation.
3. Added an output-files skeleton for demo reports, backup-review output, and sample backup fixtures.
4. Updated the main docs so the repo is easier to navigate from both the high-level and script-specific views.

## Priority areas for the next deep dive

The three highest-value areas to improve next are:

1. Operational template quality
   - Make sql-templates/operations more production-ready and ServiceNow-style for change orders and runbooks.
2. Category discoverability
   - Improve the front-of-repo navigation so DBAs can locate the right category and script faster.
3. Helper automation quality
   - Replace starter helpers with real operational scripts for backup age, DR, and maintenance checks.

The next wave should focus on:

1. SQL Agent health and job failure analysis
   - completed: job history and failure visibility via Get-SqlAgentJobOverview.sql and Get-SqlAgentJobFailureSummary.sql
2. TempDB and I/O diagnostics
   - completed: usage and I/O views via Get-TempdbUsage.sql and Get-DatabaseIoUsage.sql
3. Deadlock and blocking deep dives
   - completed: blocking and wait summaries via Get-BlockingSessions.sql and Get-DeadlockSummary.sql
4. Backup/restore validation and DR rehearsal
   - completed: backup coverage and restore estimates via Get-BackupCoverage.sql, Get-BackupRestoreDurationEstimate.sql, Generate-BackupScript.sql, and Generate-RestoreScript.sql
5. Migration inventory and change prep
   - completed: inventory and checklist helpers via Get-LinkedServerAndJobInventory.sql and Get-MigrationChecklist.sql
6. Corruption and integrity checks
   - added: Get-DatabaseIntegrityChecks.sql as a pre-check and DBCC guidance script

## Work completed in this update

- Added a category-first layout under categories/ for real DBA browsing.
- Added helper utilities under helpers/ for repo overview, cleanup, routing, and proactive script generation.
- Added output-files structure for demo reports and backup-review output.
- Fixed obvious repo path and navigation inconsistencies across README, quick-start, and catalog docs.
- Added starter script generation helpers so new DBA scripts can be scaffolded quickly.

## Current focus

- Keep scripts easy to copy into SSMS and Azure Data Studio
- Preserve simple, production-friendly comments and notes
- Expand the most useful DBA workflows first, not just the most theoretical ones
- Keep category names aligned with real troubleshooting tasks and blog topics
