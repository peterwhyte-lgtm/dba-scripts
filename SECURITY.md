# Security Policy

- This repository contains read-only diagnostics and operational templates by default.
- Never include secrets, connection strings, or private hostnames in issues or PRs.

## Supported versions

We aim for compatibility with:

- SQL Server 2016+ (compat notes in CLAUDE.md)
- PowerShell 7+ (Windows PowerShell 5.1 usually works but is not primary)

## Reporting a vulnerability

Please email security disclosures to: <peterwhyte.mail@gmail.com>
Subject: `[mssql-tools] Security`

Include: what you found, which file(s) are affected, and steps to reproduce. Response within 48 hours.

**Do not open a public GitHub issue for security vulnerabilities.**

## Credential handling

**Windows (integrated) auth is always preferred** — no credentials are stored anywhere by this repo.

**SQL auth** is supported as a fallback. When used via `Set-SqlConnection.ps1`:

- The password is stored in `$env:DBASCRIPTS_PASS` as plain text for the session only
- The env var is cleared when the PowerShell session ends
- Passwords are never written to log files, CSV output, or committed files
- A warning is printed when SQL auth is activated

**Answer file templates** (`powershell/installation/templates/*.ini`) contain no real credentials. `SAPWD` is always supplied at runtime via the `-SAPassword` parameter — never stored in INI files.

## What is in scope

- Credential leaks or plaintext secrets committed to the repo
- Scripts that execute undocumented write operations
- Parameter injection via script inputs
- CI/CD pipeline supply chain issues

## What is out of scope

The web UI (`web-ui/Start-WebUi.ps1`) runs on localhost only and is not intended to be network-exposed. Security issues specific to internet-facing deployments are out of scope.

## CI security controls

Every push and pull request runs:

- **PSScriptAnalyzer** — static analysis of all PowerShell
- **gitleaks** — scans full git history for accidentally committed secrets
- **markdownlint** — docs integrity checks

The CI workflow uses `permissions: {}` by default with least-privilege per-job grants.
