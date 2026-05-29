# Script Templates

Use these as the standard format for new DBA scripts.

## SQL Script Template

-- Purpose: Describe what the script checks or fixes.
-- Use: Copy into SSMS and run against the target instance or database.
-- Prerequisites: Mention required permissions, database context, or connected instance.
-- Notes: Mention expected output, caveats, and what action the DBA should take next.

SELECT
    1 AS example_result;

## Script Standards We Want to Keep

- Keep scripts simple and production-friendly.
- Prefer SSMS-first SQL scripts for investigation and reporting.
- Add brief metadata headers and safety annotations directly in the script itself.
- Make PowerShell helpers easy to run locally without extra setup.
- Use sql-templates/operations for production-ready operational templates that are intentionally copy/paste friendly.
- Keep long narrative notes in the repo docs only when they describe workflows, standards, or repo structure.

## PowerShell Script Template

<#
.SYNOPSIS
Short description of the helper.

.DESCRIPTION
What the script does and when to use it.
#>

param(
    [string]$SqlInstance = '.\\SQLSERVER'
)

Write-Host 'Script ready to extend.' -ForegroundColor Cyan
