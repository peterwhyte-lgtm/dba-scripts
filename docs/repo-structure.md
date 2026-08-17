# dba-tools repo structure

This document describes the current folder layout and the purpose of each area.

---

## Top-level layout

```text
sql/            SQL scripts (181; read-only, SSMS-ready, single-result-set)
powershell/     PowerShell orchestrators, automation, migration tools, and the thin wrappers
web-ui/         Browser UI (Start-WebUi.ps1, Restart-WebUi.ps1, Generate-ScriptIndex.ps1)
tools/          Repo utilities: SQL runner, triage, scaffolding, maintenance
docs/           quick-start, script catalog, repo structure, standards, templates, AI guides, roadmap
docs/ops/       Change orders, runbooks, checklists, rollback playbooks, SQL change templates
tests/          Pester test suite
output-files/   Generated output (gitignored — CSVs, healthcheck folders, reports)
```

---

## `sql/` — SQL scripts

All SQL scripts are single-result-set and SSMS paste-and-run compatible. Most are read-only; the exceptions (e.g. `traces/Create-*`, `collectors/`) are marked `SAFE:CreatesObjects` in the header. Every script has a standard header with `Script Name`, `Purpose`, `Author`, `Safe`, `Impact`, and `Requires`.

| Category | Contents |
|----------|----------|
| `inventory/` | Version, OS, databases, services, linked servers, patch level, inventory lists |
| `monitoring/` | Instance health, memory, MAXDOP, jobs, TempDB, DBCC, suspect pages, disk, config |
| `performance/` | Waits, blocking, long queries, missing indexes, I/O, plan cache, active requests |
| `backups/` | Coverage, history, DR estimates, restore generation, encryption status |
| `security/` | Roles, permissions, orphans, weak logins, surface area, linked server security |
| `high-availability/` | Subfoldered: `always-on/` (replica state, latency, failover readiness, readable secondary), `replication/`, `mirroring/`, `fci/` |
| `maintenance/` | Index maintenance jobs, backup jobs, housekeeping jobs, job status |
| `collectors/` | `Generate-CollectorJob-*.sql` — one script per collector, creates SQL Agent job and DBAMonitor table |
| `traces/` | Extended Events tooling — Create-* audit/activity sessions, session review, session cleanup |
| `lab/` | Dev/test-only scripts — blocking scenarios, test database creation |

Migration SQL scripts live separately at `sql/migration/`. See [script-catalog.md](script-catalog.md) for the full list.

---

## `powershell/` — Unique PowerShell scripts

Scripts with genuine logic beyond "run the matching SQL file." Orchestrators, automation, and OS-level tools. (Thin wrappers live under `wrappers/` — see the web UI section below.)

| Folder | Contents |
|--------|----------|
| `reporting/` | Invoke-HealthCheckCollection, Review-HealthCheckOutput, Invoke-AssessmentReport, Invoke-AiAssessment (+ ai-assessment-rubric.md), Invoke-MultiServerHealthCheck, Get-CapacityProjection, Compare-ConfigurationBaseline |
| `diagnostics/` | Live incident triage — Get-ActiveRequests, Get-BlockingChains (both support `-IncludePlan` execution plan export) |
| `reporting/multi-server/` | MultiServer-Get*.ps1 scripts for fleet-wide operations (disk, wait stats, patch level, blocking, etc.) |
| `disk-space/` | Get-DiskSpaceSummary, Get-LargestFolders, Get-OldestBackupFolderFiles, Get-BackupAge |
| `installation/` | install-sql.ps1, configure-sql.ps1, pre-install-check.ps1, post-install-validation.ps1, uninstall-sql.ps1, generate-install-report.ps1, templates/ |
| `migration/` | Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript, Generate-LinkedServerScript, Generate-RestoreWithMoveScript, Invoke-MigrationExport, Invoke-MigrationPreFlightCheck, Invoke-PreMigrationAssessment, Export-MigrationBaseline |
| `patching/` | patch-summary.ps1 (SQL + SSMS status overview) |
| `patching/sql/` | Invoke-SqlPatch.ps1 (multi-server auto-patch), patch-config.psd1 |
| `patching/ssms/` | install-ssms.ps1 (handles SSMS ≤20 and 21+), uninstall-ssms.ps1 |
| `lab/` | Lab and test database scripts (dev/test only) |

---

## Migration toolkit

| Location | Contents |
|----------|----------|
| `sql/migration/` | 13 scripts — assessment (risk, upgrade readiness, compat audit, deprecated features, edition features, login audit), DDL generators, and post-migration validation. See [`sql/migration/README.md`](../sql/migration/README.md) |
| `sql/inventory/` | The four `Get-*Inventory` scripts live here, **not** in `sql/migration/` — they are general-purpose, not migration-only |
| `powershell/migration/` | Generate-LoginScript, Generate-AgentJobScript, Generate-UserMappingScript, Generate-LinkedServerScript, Generate-RestoreWithMoveScript, Invoke-MigrationExport, Invoke-MigrationPreFlightCheck, Invoke-PreMigrationAssessment, Export-MigrationBaseline |

---

## `sql/collectors/` — Scheduled collectors

The `Collect-*.ps1` → SQL Agent migration is complete (`powershell/collectors/` no longer exists). Each `Generate-CollectorJob-*.sql` script creates a SQL Agent job and a DBAMonitor table when executed; `Generate-CollectorAlertJob.sql` adds threshold alerting, and the `Get-*Delta.sql` scripts analyse snapshot history. Trend analysis over collector output is `powershell/reporting/Get-CapacityProjection.ps1`.

| Collector | Data captured |
|-----------|---------------|
| `wait-stats` | Top wait types snapshot |
| `blocking` | Active blocking chains |
| `deadlocks` | Deadlock events from XEvent ring buffer |
| `tempdb` | TempDB file usage per session |
| `perfmon` | OS and SQL performance counters |
| `ag-health` | AG replica sync state and latency |
| `storage-io` | Database file I/O per volume |
| `database-growth` | Database size snapshots for growth trending |
| `vlf-count` | VLF count per database |
| `errorlog` | Error log entries by severity |
| `query-store` | Top queries from Query Store |
| `index-fragmentation` | Index fragmentation weekly snapshots |

---

## `web-ui/` — Browser UI and wrappers

| Item | Purpose |
|------|---------|
| `web-ui/Start-WebUi.ps1` | Local web interface for browsing scripts and visualising CSV output |
| `web-ui/Restart-WebUi.ps1` | Restarts the UI server |
| `web-ui/Generate-ScriptIndex.ps1` | Generates `docs/script-index.md` from script headers. The output is not committed — run it locally if you want it; [`docs/script-catalog.md`](script-catalog.md) is the maintained index |
| `powershell/wrappers/` | Thin PS wrappers — one per SQL script; **presence here is what makes a script appear in the web UI** |

### `powershell/wrappers/` — Thin PS wrappers

One wrapper per SQL script. Each wrapper resolves the repo root, locates its matching `.sql` file, and delegates to `tools/local-sql/Invoke-RepoSql.ps1`. Category names and subfolders mirror `sql/` exactly. Depth depends on where the wrapper sits: `wrappers/<category>/` is three levels up (`..\..\..`), `wrappers/<category>/<subfolder>/` is four (`..\..\..\..`).

| Folder | Wraps |
|--------|-------|
| `powershell/wrappers/monitoring/` | All `sql/monitoring/` scripts |
| `powershell/wrappers/performance/` | All `sql/performance/` scripts |
| `powershell/wrappers/backups/` | All `sql/backups/` scripts |
| `powershell/wrappers/security/` | All `sql/security/` scripts |
| `powershell/wrappers/migration/` | All `sql/migration/` Get-* scripts |
| `powershell/wrappers/high-availability/` | All `sql/high-availability/` scripts |
| `powershell/wrappers/maintenance/` | `sql/maintenance/` Get-* scripts |
| `powershell/wrappers/inventory/` | All `sql/inventory/` scripts |
| `powershell/wrappers/traces/` | All `sql/traces/` scripts |

---

## `tools/` — Repo utilities

| Folder | Contents |
|--------|----------|
| `tools/local-sql/` | `Invoke-RepoSql.ps1` (core runner), `Set-SqlConnection.ps1`, `Test-SqlConnectivity.ps1`, `Test-ServerNetwork.ps1` (DNS/port pre-flight) |
| `tools/triage/` | `Show-RepoOverview.ps1`, `Find-UsefulScript.ps1`, `Get-StandardsAudit.ps1` |
| `tools/scaffolding/` | `New-Wrapper.ps1`, `New-MultiServerScript.ps1` |
| `tools/maintenance/` | `Clear-OutputFiles.ps1` |

---

## `docs/ops/` — Change management

SQL templates, change orders, checklists, and runbooks for planned DBA work.

| Item | Contents |
|------|----------|
| `change-templates/` | SQL templates for CDC, TDE, AG, mirroring, DBCC, statistics, installation, patching — plus the index README for this whole area |
| `change-orders/` | CAB-ready change order documents for AlwaysOn failover, server migration, SQL upgrade |
| `dba-quickref.md` | Mid-incident lookup sheet |
| `checklists/` | Step-by-step checklists for AG migration, DR failover, server replacement, version upgrade |
| `runbooks/` | Full runbooks for standalone migration, AG cluster migration, OS upgrade, edition change, version upgrade |
| `rollback/` | Migration rollback playbook with binary trigger criteria and decision ownership |

---

## Adding new content

**New SQL script:** `sql/<category>/Get-Something.sql` — use the standard header from `CLAUDE.md`.

**New PS wrapper:** Use `.\tools\scaffolding\New-Wrapper.ps1 -SqlPath sql\<category>\<subfolder>\Get-Something.sql`, which works out the depth for you. If you copy one by hand, copy it from the same level: `wrappers/<category>/` uses `$PSScriptRoot '..\..\..'`, `wrappers/<category>/<subfolder>/` uses `$PSScriptRoot '..\..\..\..'`. The wrapper must exist for the script to appear in the web UI.

**New unique PS script:** Add to `powershell/<subfolder>/`. Use `$PSScriptRoot '..\..'` to resolve the repo root.

**New collector job:** Add a `sql/collectors/Generate-CollectorJob-<name>.sql` that creates a SQL Agent job and DBAMonitor table when executed.
