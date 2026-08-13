# Quick start

Get from a fresh clone to running diagnostics against a SQL Server instance in five minutes.

---

## 1. Clone and initialise

```powershell
git clone https://github.com/peterwhyte-lgtm/dba-tools
cd dba-tools

# Checks PowerShell version, SQL execution tools, and creates output directories
.\Initialize-Environment.ps1

# Full setup — also tests connectivity and sets the session default server
.\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019
```

<p align="center">
  <img src="../assets/screenshots/01-init-terminal.png" alt="Initialize-Environment output" width="720">
  <br><em>Initialize-Environment.ps1 — all checks pass, next steps shown</em>
</p>

The setup script checks everything and tells you exactly what needs fixing. See [SETUP.md](../SETUP.md) for the full prerequisites guide including permissions, modules, and troubleshooting.

---

## 2. Connect to your SQL Server

Set the server once for the session — every script picks it up automatically:

```powershell
# Windows auth (recommended)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# SQL auth
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

# Check what is currently set
.\tools\local-sql\Set-SqlConnection.ps1 -Show

# Verify connectivity
.\tools\local-sql\Test-SqlConnectivity.ps1
```

To persist the connection across sessions:

```powershell
.\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019 -PersistProfile
```

---

## 3. Run your first script

Use `run.ps1` to run any script by name — no paths needed:

```powershell
# Top wait types since last restart
.\run.ps1 Get-WaitStatistics

# Active blocking chains
.\run.ps1 Get-BlockingChains

# Backup coverage across all databases
.\run.ps1 Get-BackupCoverage

# Against a specific server
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019

# Save output to CSV
.\run.ps1 Get-WaitStatistics -OutputFormat Csv
# Output saved to: output-files\reviews\performance\Get-WaitStatistics-<timestamp>.csv
```

<p align="center">
  <img src="../assets/screenshots/03-run-ps1-output.png" alt="run.ps1 in action" width="720">
  <br><em>.\run.ps1 — resolves any script by name, outputs to terminal or CSV</em>
</p>

Browse all available scripts:

```powershell
.\run.ps1 -List

# Find scripts by keyword
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking
.\tools\triage\Find-UsefulScript.ps1 -Keyword backup
```

---

## 4. Run a health check

The flagship workflow: collect everything in one pass, review with rules, then have an AI assess the whole collection:

```powershell
# 1. Collect 45 scripts, save named CSVs to output-files\healthcheck\<server>-<timestamp>\
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01\SQL2019

# 2. Rules review — surfaces CRITICAL / WARNING / INFO
.\powershell\reporting\Review-HealthCheckOutput.ps1

# 3. AI assessment — correlates findings into a prioritized written report
.\powershell\reporting\Invoke-AiAssessment.ps1
```

<p align="center">
  <img src="../assets/screenshots/04-healthcheck-findings.png" alt="Review-HealthCheckOutput findings" width="720">
  <br><em>Review-HealthCheckOutput — CRITICAL / WARNING / INFO findings across the instance</em>
</p>

What the rules flag: missing backups, stale DBCC CHECKDB, suspect pages, sa enabled, percent-based autogrowth, unconfigured max server memory, high I/O latency, transaction log pressure, and more.

The AI step reads every CSV in the collection and writes a prioritized report — root causes, evidence, and a fix for each issue — to `output-files\assessments\`. It runs via Claude Code in your editor or via the API script; setup for both (including the corporate sign-off path with `-DryRun`) is in [docs/ai-assessment.md](ai-assessment.md).

For a scored client report:

```powershell
.\powershell\reporting\Invoke-AssessmentReport.ps1 -ServerInstance PROD01\SQL2019 -AssessedBy "Peter Whyte"
# Output: output-files\assessment\<server>-<timestamp>.md
```

---

## 5. Browse scripts in the web UI

An optional local web interface for browsing, running, and visualising script output:

```powershell
.\web-ui\Start-WebUi.ps1
# Opens http://localhost:8787
```

<p align="center">
  <img src="../assets/screenshots/05-web-ui-scripts.png" alt="Web UI running in VS Code terminal alongside the browser" width="720">
  <br><em>VS Code terminal (bottom) running Start-WebUi.ps1, browser UI (top) — browse scripts by category, search, and run against any instance</em>
</p>

---

## 6. Run SQL directly in SSMS

Every script in `sql/` is paste-and-run in SSMS. No PowerShell needed:

```sql
-- Open any .sql file from sql/ and paste directly into SSMS
-- Example: sql\performance\Get-WaitStatistics.sql
-- All scripts: read-only, SET NOCOUNT ON, no USE database statement
```

---

## Where to go from here

| Need | Resource |
|------|----------|
| AI assessment setup (home and corporate) | [docs/ai-assessment.md](ai-assessment.md) |
| Full script list with descriptions | [docs/script-catalog.md](script-catalog.md) |
| Repo folder layout | [docs/repo-structure.md](repo-structure.md) |
| Prerequisites, permissions, troubleshooting | [SETUP.md](../SETUP.md) |
| Migration workflow | `powershell/migration/Invoke-PreMigrationAssessment.ps1` |
| Change orders and runbooks | `docs/ops/` |
| Scheduled trend collection | `sql/collectors/` (Agent job DDL generators) |
| Multi-server operations | `powershell/reporting/multi-server/` |
