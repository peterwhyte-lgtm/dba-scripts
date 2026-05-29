# Category-first DBA layout

This folder is the new DBA-first navigation layer for the repo.

Each category contains:
- sql/ for SSMS-ready queries and reports
- powershell/ for automation helpers and local tooling

The old top-level sql/ and powershell/ folders are still kept for compatibility while the category-first path becomes the main working view.

Suggested workflow:
1. Start in categories/<area>/sql for analysis.
2. Use categories/<area>/powershell for local automation.
3. Use helpers/ for common repo utilities and tools/ for repo maintenance helpers.
