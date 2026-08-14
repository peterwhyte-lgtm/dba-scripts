# CLAUDE.md

This file is the working operating guide for this repository.

## Purpose

This repo is a production SQL Server DBA toolkit for Peter Whyte (sqldba.blog). Its identity: **AI reviewing SQL Server (one or many)** — health check data collection, a web UI dashboard to view and verify it, and copy/paste production DBA scripts underneath. Everything a DBA needs, with an AI helper to surface the blindspots.

The repo is built around four core ideas:

1. **The AI assessment is the flagship** — the healthcheck workflow (collect → rules review → AI assessment) is the repo's headline capability; the AI step is the point of the collection.
2. **Scripts first underneath** — the flagship rests on usable, copy/paste DBA tooling that works with no AI and no web UI.
3. **Run it directly when possible** — scripts should be understandable and runnable in isolation.
4. **Docs and outputs matter** — the repo should explain what a script does, what it returns, and what to do next.

The web UI is where collection output is viewed, verified, and diagnosed — part of the flagship workflow, though every workflow also works from the terminal alone. Multi-server ("the many part") is the planned build-out of the main gig, not yet current scope.

## Product positioning (Peter's directive, 2026-07-06)

Treat dba-tools like a **product**: the AI integration is the selling point and the thing to promote; everything underneath must hold production value against the field's gold standards. Benchmarks to measure against (and beat where claimed):

- **Activity/session visibility** as good as `sp_WhoIsActive`
- **Maintenance plan generation** as good as Ola Hallengren's solution
- **Diagnostic scripts** as good as Glenn Berry's, but more pertinent
- **Wait statistics** material better than Paul Randal's reference pages

When improving or reviewing scripts in these areas, these benchmarks are the bar — production value is the floor the AI story stands on.

## Operating rules

These rules apply across the repo:

- Prefer scripts that can be run from the repo **and** copied/pasted into a normal DBA workflow.
- **Copy/paste-first, zero dependencies:** a DBA who grabs one script (a patch runner, an SSMS
  installer, a trace, a monitoring query) must be able to run it right away. Where a script has
  an unavoidable precondition (e.g. traces need an existing output directory), say so in a script
  comment and/or terminal output — tell the user to create it or amend the parameter.
- Default to `.` / localhost unless a server is explicitly supplied.
- Preserve the intent of the script; do not change logic unless needed for safety, correctness, or readability.
- Prefer deterministic, readable, production-safe logic over clever shortcuts.
- Document purpose, permissions, expected output, and when **not** to use a script.
- Keep script docs and script behavior aligned so the output is trustworthy.
- Treat `output-files/` as generated runtime output, not permanent source content.
- Keep scripts easy to understand in isolation, even if the repo provides wrappers or launchers.
- Treat multi-server tooling as optional convenience, not as the main model for every script.
- Avoid overengineering and avoid adding complexity that hides operational intent.

## Naming and classification

- Prefer script names that describe the operational outcome first.
- Use one primary category per script or post.
- If a script is strong enough for a blog post, document it in a way that explains the problem, the output, and the DBA takeaway.
- Prefer one clear post per concept; avoid duplicating similar material.

## How to run scripts

Use the simplest path that preserves clarity:

- a script should be runnable directly from the repo
- a script should also be easy to copy/paste into a DBA workflow
- if a script targets a specific server, the script or wrapper should make that explicit
- the output should be understandable even without the web UI
- another DBA should be able to explain the script confidently during troubleshooting

The preferred entry points are:

```powershell
# 1. Root launcher — fuzzy name match, searches sql/ and powershell/
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-WaitStatistics -ServerInstance MYSERVER\INST01 -OutputFormat Csv

# 2. Direct wrapper — explicit path, passes all params through
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\wrappers\performance\Get-WaitStatistics.ps1 -ServerInstance . -OutputFormat Csv

# 3. SQL directly via the repo runner (for SSMS-style results in terminal)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\local-sql\Invoke-RepoSql.ps1 -ScriptPath .\sql\performance\Get-WaitStatistics.sql -ServerInstance .
```

Full healthcheck workflow (collect → rules review → AI assessment — the AI step is the
point of the collection; see `docs/ai-assessment.md`):
```powershell
# 1. Collect 45 scripts, save CSVs to output-files\healthcheck\<server>-<timestamp>\
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance .

# 2. Review the latest collection folder and surface CRITICAL / WARNING / INFO findings
.\powershell\reporting\Review-HealthCheckOutput.ps1

# Or target a specific folder
.\powershell\reporting\Review-HealthCheckOutput.ps1 -FolderPath ".\output-files\healthcheck\.-20260529-185000" -OutputFormat Csv

# 3. AI assessment — Claude API path (needs ANTHROPIC_API_KEY; -DryRun previews the prompt)
.\powershell\reporting\Invoke-AiAssessment.ps1
```

**When a Claude Code session is asked for a health assessment, IT performs step 3 itself**
(instead of calling the API script): read the CSVs in the latest healthcheck folder, follow
`powershell\reporting\ai-assessment-rubric.md`, write the report to
`output-files\assessments\<server>-<timestamp>-claude-code.md`.

Preflight and discovery:
```powershell
.\tools\triage\Show-RepoOverview.ps1                          # inventory: script counts by category
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking        # find scripts by keyword
.\tools\local-sql\Test-SqlConnectivity.ps1 -ServerInstance .  # verify SQL connectivity
.\tools\maintenance\Clear-OutputFiles.ps1                     # wipe output-files\ before a fresh run
```

Migration DDL generators:
```powershell
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LoginScript.ps1
.\powershell\migration\Generate-AgentJobScript.ps1
.\powershell\migration\Generate-UserMappingScript.ps1
# Output: output-files\migration\*.sql
```

## Blog / content guidance

> **MOVED 2026-07-16 — the blog drafting workspace no longer lives in this repo.** It migrated to
> the **Publisher** app at **`personal/tools/site-publisher/`** (private repo, backed up). The
> `dba-scripts-*` gold is in `site-publisher/workspace/sqldba/{published,drafts}/`, all legacy drafts +
> the 74 published archives are in `site-publisher/archive/sqldba/`, the master template is
> `site-publisher/templates/dba-script/index.md`, the how-to is `site-publisher/reference/DRAFTING.md`, and
> the publishing checklist (103 posts + the 6-post traces cluster #104–#109, 6 live) is `site-publisher/PUBLISHING.md`. Scaffold a post
> with `python publisher.py draft Get-ScriptName` (the Python port of the old `New-ScriptPost.ps1`).
> **dba-tools stays the operational home of the SQL scripts** the posts link to; only the blog
> drafting/content moved out. The taxonomy below remains the shared reference model.

The blog workspace assists Peter in writing posts for sqldba.blog — it has no public-facing output and is not a documentation layer for the repo. The live sqldba.blog post is the public documentation artifact for each script. Links to live posts are added by Peter after publishing, not generated automatically.

The repo should reflect the intended blog taxonomy so that scripts and posts can be organized consistently over time, while keeping the main repo focused on usable DBA tooling.

### Blog category framework

**Live WordPress categories (authoritative — sqldba.blog, consolidated 2026-07-13):** Performance,
Monitoring, Troubleshooting, Maintenance, Backups & Recovery, Security, High Availability & DR,
Migration & Upgrades, Installation & Configuration, T-SQL Fundamentals, T-SQL & Internals, AI, Labs
— plus **DBA Scripts** (added 2026-07-16, <https://sqldba.blog/category/dba-scripts/>): the home
for all master-template script posts (see Script post standard below).
The old `dba-operations` / `dba-scripts` / `dba-engineering` containers are retired. When choosing
where a post goes, use this set. Full plan, per-post mapping, and edge-case rules (patching vs
upgrade, trace flags, restore vs stuck-restore): `personal/tools/site-publisher/reference/CATEGORY-PLAN.md`.
Machine map for the `recategorize.py` sweep tool: `site-publisher/reference/recategorize-map.json`.

The richer list below is the **internal planning model** for repo organization (it has finer
buckets like inventory, incident-response, capacity-planning that fold into the live set above —
e.g. inventory + instance-config → Monitoring; environment-setup → Installation & Configuration).
Use the following primary categories when deciding where a script or post belongs:

1. **Core DBA operations**
   - performance
   - monitoring
   - inventory
   - maintenance
   - backup-recovery
   - security
   - high-availability
   - migration-upgrades
   - troubleshooting
2. **Production operations**
   - incident-response
   - capacity-planning
   - change-management
   - data-integrity
   - auditing-compliance
3. **Engineering & architecture**
   - data-architecture
   - diagnostics
   - environment-setup
   - automation
4. **Script ecosystem**
   - scripts
5. **Experimental & learning**
   - labs
6. **Meta / system thinking**
   - engineering-notes
   - ai-systems
   - ai (tips and workflow learnings from building with AI tools — distinct from ai-systems which is technical AI integration)
7. **Personal / optional**
   - life-work
8. **Future extensions**
   - cloud (inactive unless needed)

This framework is mainly an internal reference model for repo organization and content planning. It does not need to be exposed in a rigid way to every user, but it should guide how scripts and docs are classified and how future content is prioritized.

### Repo structure as blog taxonomy signal

The `sql/<category>/` directory maps to a blog primary category. The `sql/<category>/<subfolder>/` maps loosely to blog tags — not a rigid 1:1, but a directional guide:

| sql/ path | Blog category | Tag signal |
|---|---|---|
| `sql/inventory/` | inventory | instance, databases, services |
| `sql/monitoring/instance/` | monitoring | instance-config, memory |
| `sql/monitoring/databases/` | monitoring | database-health, integrity |
| `sql/monitoring/disk-space/` | monitoring | disk-space, growth, transaction-log, vlf |
| `sql/monitoring/tempdb/` | monitoring | tempdb |
| `sql/monitoring/jobs/` | monitoring | sql-agent |
| `sql/monitoring/error-log/` | monitoring | error-log |
| `sql/monitoring/features/` | monitoring | cdc, query-store, extended-events, service-broker |
| `sql/performance/blocking-locking/` | performance | blocking, locking, deadlocks |
| `sql/performance/indexes/` | performance | indexes, fragmentation |
| `sql/performance/queries/` | performance | query-tuning, plan-cache, statistics |
| `sql/performance/query-store/` | performance | query-store |
| `sql/performance/active-sessions/` | performance | active-sessions |
| `sql/security/access/` | security | logins, users, permissions, roles |
| `sql/security/encryption/` | security | tde, encryption, certificates |
| `sql/high-availability/always-on/` | high-availability | availability-groups |
| `sql/high-availability/replication/` | high-availability | replication |
| `sql/backups/` | backup-recovery | — |
| `sql/migration/` | migration-upgrades | — |
| `sql/traces/` | troubleshooting | extended-events, tracing, auditing |

A post series (e.g., wait statistics, index series) can introduce more granular tags than the subfolder suggests — the subfolder is a starting point, not a ceiling.

### Script post standard (master template, 2026-07-16)

Every DBA script in the repo gets a blog post following the master template at
`personal/tools/site-publisher/templates/dba-script/index.md`, established by the live post
<https://sqldba.blog/dba-scripts-get-vlf-counts/>. Full conventions + section decision matrix:
`site-publisher/reference/README.md` ("Master post template"). The non-negotiables:

- Title starts `DBA Scripts: ` and slug starts `dba-scripts-` (hard rule, no exceptions;
  usually `DBA Scripts: Get [Thing]` / `dba-scripts-get-thing`), category **DBA Scripts**, first line links the
  project page: `Part of the [DBA-Tools](https://sqldba.blog/scripts/) Project.`
- Core sections always: intro (problem-first), Why It Matters, When to Run, The Script
  (full SQL including repo header), How To Run From The Repo (+ GitHub links to the
  script's `sql/` path and wrapper), Example Output, Understanding the Results,
  Related Scripts, Summary.
- Optional sections (Common Symptoms, Common Causes, How to Fix, Best Practices, FAQ)
  per the decision matrix — full for flagship diagnostics, compact for inventory scripts.
- **Related Scripts is forever-updating**: populate from the script's `sql/` directory,
  hyperlink items as their posts go live, and when a new post publishes, sweep the live
  posts of same-directory scripts to add a link back.

### How to choose a primary category

When a script is added or updated, choose the single best primary category based on its main operational intent:

- Use the category that best matches the main question the script answers
- If the script is primarily about investigation, use the category that matches the investigation area
- If the script is primarily about execution or automation, use the category that matches the operational workflow it supports
- If the script is mainly a reusable utility, classify it based on the practical DBA task it helps with, not the implementation detail

A script should not be spread across multiple categories just because it touches several topics.

### Title rules

**Script posts (the master template): HARD RULE (Peter, 2026-07-18) — every script post
title starts `DBA Scripts: ` and every slug starts `dba-scripts-`, no exceptions.** The
usual form is `DBA Scripts: Get [Thing]` — slug
`dba-scripts-get-thing`. This supersedes the older patterns for script-backed posts
(2026-07-16; the retired `Script:` prefix cleanup in
`site-publisher/archive/sqldba/_planning-docs/SCRIPT-PREFIX-RETITLE.md` predates this — the 24
legacy posts are being refit via `site-publisher/PUBLISHING.md` Phase 1).

Non-script posts use one of:
- Get [Thing] for SQL Server
- Check [Thing] in SQL Server
- Analyze [Thing] in SQL Server
- Find [Thing] in SQL Server
- SQL Server [Thing] Overview (rare cases only)

### Content rules

- Do not duplicate a blog post if a similar script already covers the same operational idea
- Prefer one authoritative post per concept; if two scripts overlap, consolidate or clarify the distinction
- Use the repo path to point to the real script location
- Keep the post practical, not promotional, and focused on DBA outcomes
- For similar concepts, prefer a clear distinction such as summary vs detailed drill-down (for example, a high-level summary script and a deeper script should be explained separately)
- When a script is created or refined, classify it under the most appropriate primary category and keep that classification consistent across repo docs and any related post material
- Treat the repo script as the operational artifact and the blog post as the explanatory artifact; they are related, but they are not the same thing

### Additional recommendations

- Add a short note to new scripts explaining what problem they solve, what permissions they need, and when not to use them
- Prefer clear names that describe the DBA outcome, not just the internal implementation path
- Keep the script and its surrounding documentation aligned so a reader can understand both the purpose and the expected output
- If a script is likely to be used often, favour a stable, readable interface over clever shortcuts
- Use the repo taxonomy to guide future planning, but do not let taxonomy become a barrier to practical action
- Aim for scripts that are safe to review quickly by another DBA during an incident
- Prefer defaults that reduce surprise and avoid hidden environment assumptions
- Where a script is likely to be reused, make the expected inputs and outputs obvious from the script name and surrounding comments
- When in doubt, choose the version that is easier to understand, debug, and explain under pressure

## Layout

**Use `sql/` or `powershell/` for all new work.**

```text
sql/
  inventory/      — server/instance cataloguing: version, OS, databases, services, linked servers,
                    patch level, database/login/job/linked-server inventory lists
  monitoring/     — ongoing health monitoring; subfolders by area:
    instance/     — OS config, trace flags, CPU topology, instance config score/snapshot, MAXDOP,
                    resource governor, memory config
    databases/    — database health, integrity checks, DBCC CHECKDB history, suspect pages
    disk-space/   — database sizes, free space, file detail, filegroup space, disk space, tlog size/usage,
                    VLF count, growth risk, growth events, autogrowth history
    tempdb/       — TempDB configuration, file balance, hotspots, usage
    jobs/         — SQL Agent job failures, overview, duration trends, schedule summary, alerts/operators
    error-log/    — recent error log entries, error log patterns, schema change history
    features/     — CDC/change tracking, Query Store status, Extended Events, Service Broker,
                    compression candidates, cross-database dependencies, collation conflicts, DB Mail queue
    (root)        — active connections by database, linked server connectivity
  performance/    — query and workload performance; subfolders by area:
    blocking-locking/ — blocking chains (+plan), blocking sessions/summary, open transactions,
                        lock escalation stats, deadlock summary, contention analysis
    indexes/      — missing indexes, unused indexes, index usage stats, duplicate indexes, heaps,
                    index design issues, fragmentation (single-db and cross-db)
    queries/      — top CPU/IO queries, slow queries from cache, plan cache health, SP performance,
                    implicit conversions, memory grant spills, query variance, statistics health
    query-store/  — Query Store top queries, forced plans, regressions
    active-sessions/ — active requests (+plan), active sessions, long-running queries, worker threads
    (root)        — wait statistics, database I/O usage, table sizes, backup/restore progress
  high-availability/ — already subfoldered:
    always-on/    — AG failover readiness, replica state, latency, readable secondary usage
    fci/          — last node blip
    mirroring/    — endpoint health, mirroring status
    replication/  — distribution agent, log reader agent, replication status, undistributed commands
    logshipping/  — (placeholder)
    azure/        — (placeholder)
  backups/        — coverage, history, encryption status, completion time, duration estimates,
                    size trend, restore history, last backup times, restore script generation
  security/       — subfolders by area:
    access/       — database/server role members, login/user/database permissions, orphaned users,
                    sysadmin members, user permissions audit, weak login settings, failed login summary,
                    login last activity
    encryption/   — certificates and keys, certificate expiry warnings, TDE status
    (root)        — audit specifications, DB Mail/xp_cmdshell surface area, DDL triggers,
                    linked server security, proxy and credentials
  maintenance/    — maintenance job scripts (Generate-* and Get-MaintenanceJobStatus)
  migration/      — pre-migration assessment: compatibility audit, deprecated features, edition feature
                    usage, migration login audit, migration risk assessment, post-migration validation,
                    version upgrade readiness; DDL generators: Generate-Login/AgentJob/UserMapping/
                    LinkedServer/RestoreWithMove scripts; Fix-OrphanedUsers
  collectors/     — Generate-CollectorJob-*.sql (12 collectors: ag-health, blocking, database-growth,
                    deadlocks, errorlog, index-fragmentation, perfmon, query-store, storage-io, tempdb,
                    vlf-count, wait-stats): each creates a SQL Agent job + DBAMonitor table;
                    Generate-CollectorAlertJob.sql; Get-*Delta.sql for snapshot-over-time analysis
  traces/         — Extended Events tooling: Create-* session scripts (decommission audit, login activity,
                    SP execution), Get-ActiveXeSessions, Get-XeSessionActivity, Remove-XeSession
  lab/            — test scripts — dev/test only

powershell/
  reporting/          — on-demand report/analysis orchestrators (real PS logic, human-triggered —
                        contrast: wrappers/ are thin 1:1 shims; collectors are scheduled Agent jobs):
                        Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport,
                        Invoke-AiAssessment (+ ai-assessment-rubric.md — the shared AI prompt),
                        Invoke-MultiServerHealthCheck, Get-CapacityProjection (collector trend
                        analysis), Compare-ConfigurationBaseline (config drift vs saved baseline)
  diagnostics/        — live incident triage (rich runners with plan export, run DURING an incident):
                        Get-ActiveRequests (-IncludePlan), Get-BlockingChains (-IncludePlan);
                        output goes to output-files\diagnostics\
  reporting/multi-server/ — MultiServer-Get*.ps1 scripts (disk, wait stats, patch level, blocking, etc.)
  disk-space/         — Get-DiskSpaceSummary, Get-LargestFolders, Get-OldestBackupFolderFiles, Get-BackupAge
  wrappers/           — thin wrappers; mirror the sql/ category+subfolder structure exactly
    inventory/        — wrappers for sql/inventory/ scripts
    backups/          — wrappers for sql/backups/ scripts
    maintenance/      — wrappers for sql/maintenance/ scripts
    high-availability/ — wrappers for sql/high-availability/ scripts
    migration/        — wrappers for sql/migration/ scripts (excluding inventory scripts)
    monitoring/       — wrappers for sql/monitoring/ scripts; same subfolders:
      instance/       — wrappers for sql/monitoring/instance/
      databases/      — wrappers for sql/monitoring/databases/
      disk-space/     — wrappers for sql/monitoring/disk-space/
      tempdb/         — wrappers for sql/monitoring/tempdb/
      jobs/           — wrappers for sql/monitoring/jobs/
      error-log/      — wrappers for sql/monitoring/error-log/
      features/       — wrappers for sql/monitoring/features/
      (root)          — wrappers for sql/monitoring/ root scripts
    performance/      — wrappers for sql/performance/ scripts; same subfolders:
      blocking-locking/ — wrappers for sql/performance/blocking-locking/
      indexes/          — wrappers for sql/performance/indexes/
      queries/          — wrappers for sql/performance/queries/
      query-store/      — wrappers for sql/performance/query-store/
      active-sessions/  — wrappers for sql/performance/active-sessions/
      (root)            — wrappers for sql/performance/ root scripts
    security/         — wrappers for sql/security/ scripts; same subfolders:
      access/           — wrappers for sql/security/access/
      encryption/       — wrappers for sql/security/encryption/
      (root)            — wrappers for sql/security/ root scripts
    traces/           — wrappers for sql/traces/ scripts
  installation/       — install-sql.ps1, configure-sql.ps1, pre-install-check.ps1, post-install-validation.ps1,
                        uninstall-sql.ps1, generate-install-report.ps1, templates/
  migration/          — Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript,
                        Generate-LinkedServerScript, Generate-RestoreWithMoveScript,
                        Invoke-MigrationExport, Invoke-PreMigrationAssessment, Export-MigrationBaseline,
                        Invoke-MigrationPreFlightCheck
  patching/           — patch-summary.ps1 (SQL + SSMS status overview, stays at this level)
    sql/              — Invoke-SqlPatch.ps1 (multi-server auto-patch), patch-config.psd1
    ssms/             — install-ssms.ps1 (handles SSMS ≤20 and 21+), uninstall-ssms.ps1
  lab/                — lab and test database scripts (dev/test only)
  (powershell/collectors/ no longer exists — the Collect-*.ps1 → SQL Agent job migration is
   complete; all collector tooling lives in sql/collectors/. Analysis over collector history
   is Get-CapacityProjection in reporting/.)

web-ui/               — browser UI: Start-WebUi.ps1, Generate-ScriptIndex.ps1

tools/
  local-sql/    — Invoke-RepoSql.ps1 (the core runner), Set-SqlConnection.ps1, Test-SqlConnectivity.ps1,
                  Test-ServerNetwork.ps1 (DNS/port pre-flight; auto-runs on connection failure)
  triage/       — Show-RepoOverview.ps1, Find-UsefulScript.ps1, Get-StandardsAudit.ps1
  scaffolding/  — New-Wrapper.ps1, New-MultiServerScript.ps1
  maintenance/  — Clear-OutputFiles.ps1

docs/ops/       — change orders, checklists, runbooks, rollback playbooks, SQL change templates
docs/           — quick-start.md, roadmap.md, runbook.md, standards.md, repo-structure.md

output-files/   — generated CSVs, healthcheck folders, reviews
```

## Running against a remote server

All scripts that call `Invoke-RepoSql.ps1` honour three session-level environment variables. Set them once with `Set-SqlConnection.ps1` and every script picks them up automatically for the rest of the session — no need to repeat `-ServerInstance` on every call.

```powershell
# Set remote server for this session (Windows auth)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# SQL auth (prompts for password)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

# Named instance with non-default port
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance "PROD01\INST01,14330"

# See what is currently active
.\tools\local-sql\Set-SqlConnection.ps1 -Show

# Reset to local (.) Windows auth
.\tools\local-sql\Set-SqlConnection.ps1 -Clear
```

Or pass `-ServerInstance` directly on any individual call:

```powershell
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019
.\powershell\wrappers\performance\Get-WaitStatistics.ps1 -ServerInstance PROD01\SQL2019 -OutputFormat Csv
```

Env vars used internally: `$env:DBASCRIPTS_SERVER`, `$env:DBASCRIPTS_USER`, `$env:DBASCRIPTS_PASS`. Explicit params always win over env vars.

### DDL generator scripts

`powershell/migration/Generate-*.ps1` scripts work differently from normal wrappers — they do **not** go through the CSV pipeline. They call `Invoke-Sqlcmd` with `MaxCharLength 2000000` (or `sqlcmd.exe -y 0`) to capture the full `NVARCHAR(MAX)` DDL string and write it to a `.sql` file in `output-files\migration\`. Never call these through `Invoke-RepoSql.ps1`.

```powershell
# Migration: generate all three scripts from source server
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LoginScript.ps1
.\powershell\migration\Generate-AgentJobScript.ps1
.\powershell\migration\Generate-UserMappingScript.ps1
# Output: output-files\migration\*.sql  — review, edit owners, run on target
```

## How PowerShell wrappers work

Every thin wrapper in `powershell/wrappers/<category>/*.ps1` follows this pattern:

1. Resolves `$repoRoot` as **three** levels up from `$PSScriptRoot` (wrappers sit at `powershell/wrappers/<category>/`)
2. Builds `$sqlScript = Join-Path $repoRoot 'sql\<category>\<Name>.sql'` (or `sql\migration\` for migration scripts)
3. Delegates to `tools\local-sql\Invoke-RepoSql.ps1` with `-ScriptPath`, `-ServerInstance`, `-Database`, `-OutputFormat`, `-OutputPath`

**Web UI contract:** A SQL script in `sql/` only appears in the web UI if it has a matching wrapper in `powershell/wrappers/<same-category>/<same-subfolder>/` (mirroring the sql/ path exactly). The wrapper IS the web UI entry point — the web UI launches wrappers, not SQL files directly. Every new SQL script must have a paired wrapper at the same relative path under `powershell/wrappers/`.

`Invoke-RepoSql.ps1` tries `Invoke-Sqlcmd` first (SqlServer module), falls back to `sqlcmd.exe`. Always writes a CSV to `output-files\reviews\<category>\<scriptname>-<timestamp>.csv` and prints a table preview. If neither tool is available it throws.

`run.ps1` resolves script by name fuzzy match → `& $target @Arguments`. It searches `powershell/`, `tools/`, `sql/` recursively. Throws if more than one match — callers must be specific.

**PowerShell script rules:**
- Classify script type in `.NOTES`: `runner` / `automation` / `hybrid`
- State target scope: `single server` or `multi-server`
- Classify risk in `.NOTES`: `RiskLevel : SAFE` / `MEDIUM` / `HIGH IMPACT`
- Separate SQL logic from orchestration — SQL lives in external `.sql` files
- Add error handling; ensure idempotent behaviour where possible

## SQL script standards

Every SQL script must have this header block then the two safety annotations:

```sql
/*
Script Name : Get-ExampleScript
Category    : performance-troubleshooting
Purpose     : One-line description of what this returns.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
```

`-- SAFE:` values: `ReadOnly` / `WritesData` / `CreatesObjects` — `-- IMPACT:` values: `Low` / `Medium` / `High`

Add `HealthCheck : Yes` (after `Requires`) to any script that runs as part of `Invoke-HealthCheckCollection.ps1`. This tag drives the "Health Check Suite" section in the web UI and makes membership machine-readable without needing a separate folder.

**Author URL rule:** The `Author` line uses `https://sqldba.blog` as a placeholder until the script has a published post. Once a post is live, update the URL to the specific post URL. Permalinks are **postname-only** (`/%postname%/`, since 2026-07-13) — the category is **not** in the URL, so the format is `Author : Peter Whyte (https://sqldba.blog/get-database-file-names-and-paths-in-sql-server/)` (not `/category/postname/`). Do this at the same time as marking the blog post `status: updated` or `status: published`. **The Author line is the ONLY blog link in a script header** — the old `-- Blog:` duplicate line was removed repo-wide 2026-08-14; do not reintroduce it.

**SQL script rules:**
- Remove or flag unsafe patterns: `WITH (NOLOCK)` (explain risk if present), deprecated catalog views (`sys.sysprocesses`, `sys.sysobjects` etc.)
- Prefer modern DMVs — `sys.objects` not `sys.sysobjects`, `sys.server_principals` not `sys.syslogins`
- No `USE database; GO` — `Invoke-Sqlcmd` does not support `GO` batch separators; pass `-Database` at execution time
- `OUTER APPLY` not `CROSS APPLY` when the applied function may return no rows
- No trailing blank lines; 0–1 blank lines at end of file
- Keep output readable and deterministic


## Adding new scripts

New SQL script: `sql/<category>/<subfolder>/Get-Something.sql` (or `sql/<category>/Get-Something.sql` if it belongs at the category root).

New PS wrapper: copy any existing wrapper from the same level under `powershell/wrappers/`. Path depth rules:
- `powershell/wrappers/<category>/` (root-level scripts) → `$PSScriptRoot '..\..\..'` (3 levels)
- `powershell/wrappers/<category>/<subfolder>/` (subfoldered) → `$PSScriptRoot '..\..\..\..'` (4 levels)
- Update `$sqlScript` to match the sql/ path exactly. The wrapper must be present for the script to appear in the web UI.

Use `New-Wrapper.ps1` to scaffold: it will need the category and subfolder to set the correct depth.

New orchestrator PS script (has real logic, not a thin wrapper): add to `powershell/<subfolder>/` (e.g. `reporting/`, `maintenance/`, `migration/`). Use `$PSScriptRoot '..\..'` to resolve repo root.

**When refactoring an existing script, summarise:** improved script, risk classification (`SAFE` / `MEDIUM` / `HIGH IMPACT`), key changes (bullets), suggested folder placement.

**For each major script, document:** purpose in operational terms, example output interpretation, when **not** to use it, required permissions.

## SQL session mode (memory-constrained workstations)

On a workstation where SQL Server shares RAM with Docker containers and other services
(e.g. the local site-lab staging rig), the OS will page SQL Server out under pressure —
collections crawl, collector steps fail with error 802, and the plan cache gets flushed,
which poisons every performance CSV. Before heavy SQL verification work (full healthcheck
runs, integration testing batches): **stop the site-lab containers, run the SQL work,
restart the containers after.** Keep max server memory modest on such a box (2048 MB
ceiling here) rather than chasing the paging with a bigger cap.

## Healthcheck collection — what it covers

`Invoke-HealthCheckCollection.ps1` runs 45 scripts and saves named CSVs. It also writes a
per-script `manifest.csv` (label, status, started, finished, duration) into the collection
folder, rewritten atomically after every status change — the web UI's `/api/status` polls it
for live progress, and it records per-script timings and failures for any later reader
(including the AI assessment). `-OutputFolder` targets an exact folder (used by the web UI);
otherwise the folder is `<server>-<timestamp>` under `-OutputRoot`.

| CSV label | SQL script |
|-----------|-----------|
| server-info | Get-VersionAndEdition.sql |
| os-hardware | Get-OsAndHardwareInfo.sql |
| database-health | Get-DatabaseHealth.sql |
| database-sizes | Get-DatabaseSizesAndFreeSpace.sql |
| database-files | Get-DatabaseFilesDetail.sql |
| backup-times | Get-LastDatabaseBackupTimes.sql |
| backup-coverage | Get-BackupCoverage.sql |
| tlog-usage | Get-TransactionLogSizeAndUsage.sql |
| memory-config | Get-MemoryConfigurationAndUsage.sql |
| wait-stats | Get-WaitStatistics.sql |
| active-sessions | Get-ActiveSessions.sql |
| tempdb-usage | Get-TempdbUsage.sql |
| job-failures | Get-SqlAgentJobFailureSummary.sql |
| recent-errors | Get-RecentErrorLogEntries.sql |
| dbcc-checkdb | Get-LastDbccCheckdb.sql |
| suspect-pages | Get-SuspectPages.sql |
| io-usage | Get-DatabaseIoUsage.sql |
| disk-space | Get-DiskSpace.sql |
| growth-risk | Get-DatabaseGrowthRisk.sql |
| security-surface-area | Get-DatabaseMailAndXpCmdShell.sql |
| weak-logins | Get-WeakLoginSettings.sql |
| missing-indexes | Get-MissingIndexes.sql |
| tempdb-config | Get-TempDbConfiguration.sql |
| plan-cache | Get-PlanCacheHealth.sql |
| linked-server-security | Get-LinkedServerSecurity.sql |
| vlf-count | Get-VlfCount.sql |
| maintenance-jobs | Get-MaintenanceJobStatus.sql (msdb) |
| failed-logins | Get-FailedLoginSummary.sql |
| query-store-status | Get-QueryStoreStatus.sql |
| extended-events | Get-ExtendedEventsSessions.sql |
| cdc-and-ct | Get-CdcAndChangeTracking.sql |
| service-broker | Get-ServiceBrokerHealth.sql |
| sysadmin-members | Get-SysadminMembers.sql |
| instance-config | Get-InstanceConfigurationSnapshot.sql |
| top-cpu-queries | Get-TopCpuQueries.sql |
| agent-jobs-overview | Get-SqlAgentJobOverview.sql |
| orphaned-users | Get-OrphanedUsers.sql |
| certificate-expiry | Get-CertificateExpiryWarnings.sql |
| autogrowth-history | Get-AutogrowthHistory.sql |
| ag-replica-state | Get-AvailabilityGroupReplicaState.sql |
| ag-failover-readiness | Get-AgFailoverReadiness.sql |
| ag-latency | Get-AvailabilityGroupLatency.sql |
| mirroring-endpoint-health | Get-MirroringEndpointHealth.sql |
| replication-status | Get-ReplicationStatus.sql |
| last-node-blip | Get-LastNodeBlip.sql |

`Review-HealthCheckOutput.ps1` reads those CSVs and fires on: databases not ONLINE, missing backups, full backup older than 24h (CRITICAL), stale log backups, tlog >80% used, auto-shrink, auto-close, percent-based autogrowth, DBCC CHECKDB stale >7 days (WARNING) or overdue >14 days / never (CRITICAL), any suspect pages (CRITICAL), SA enabled (CRITICAL), weak SQL login settings, I/O latency >50ms, specific wait type patterns (PAGEIOLATCH, WRITELOG, RESOURCE_SEMAPHORE, CXPACKET), max server memory unconfigured, data files <10% free, VLF count >200 (WARNING) or >1000 (CRITICAL), DBA maintenance job missing/failed/disabled, failed logins (locked accounts and repeated failures), Query Store switched to READ_ONLY, active user Extended Events sessions (INFO), CDC/Change Tracking warnings, Service Broker CRITICAL/WARNING status, databases at/near their configured growth limit, volumes <10% (WARNING) or <5% (CRITICAL) free, certificates expired/expiring, orphaned database users, xp_cmdshell enabled, error-log corruption/crash patterns (823/824/825/832, stack dumps) and memory-pressure patterns (paged out, error 802/701), AG replicas NOT_HEALTHY/DISCONNECTED or failing readiness, mirroring/AG endpoints not STARTED, inactive replication subscriptions, and recent failover-related error log entries.

## Important caveats

- AG scripts (`sql/high-availability/Get-AvailabilityGroupReplicaState.sql`, `Get-AvailabilityGroupLatency.sql`) guard against non-AG instances and return a status row instead of throwing.
- Multi-result-set SQL scripts cannot be cleanly exported as a single CSV via `Invoke-RepoSql.ps1`. All scripts in `sql/` are single-result-set by design.
- `output-files/` CSV files accumulate and should not be committed. Clear with `.\tools\maintenance\Clear-OutputFiles.ps1` before a fresh assessment run.
- `docs/standards.md` is the detailed standards reference — the header in this file is the condensed authoritative version. Keep both in sync when standards change.
