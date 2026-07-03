# DBA Scripts Roadmap

## Current state (updated 2026-06-21)

Fully functional production DBA toolkit. The repo has a category-first layout: `sql/` for SQL scripts, `powershell/` for wrappers, orchestrators, and automation (categories mirror `sql/`), and `docs/ops/` for operational runbooks and change templates.

**What is complete:**
- SQL diagnostic layer — 80+ scripts across monitoring, performance, high-availability, backups, security, maintenance, migration
- Wrapper layer — 81 thin PS wrappers, one per SQL script, colocated with the web UI
- PowerShell orchestration — healthcheck collection (39 scripts), review, assessment report, multi-server health check
- Migration toolkit — full pre/post assessment, DDL generators (logins, jobs, linked servers, user mappings), baseline export
- Collectors — 12 scheduled collectors as SQL Agent job generators in `sql/collectors/` (PS-based Collect-* retired); `Generate-CollectorAlertJob.sql` + `Get-*Delta.sql` for alerting and snapshot analysis
- Collector analysis — `Get-CapacityProjection.ps1` (days-to-full from collector history), `Compare-ConfigurationBaseline.ps1` (config drift)
- Multi-server scripts — 12 self-contained scripts for fleet-wide operations
- Browser UI — script browser, CSV viewer, triage page, health check runner, security page (surface area vitals + access risk + findings panel)
- Environment setup — `Initialize-Environment.ps1` + `SETUP.md`
- Pester tests — SQL header standards, path resolution, wrapper parity (635 tests, all passing)
- CI — GitHub Actions: Pester, PSScriptAnalyzer, markdownlint, SQL standards audit, secrets scan

---

## Active backlog

### Phase 3 — Script blog coverage (in progress, Peter-driven)

39 post drafts in `blog/` covering performance, monitoring, security, HA/DR, and the wait statistics series. Publishing queue and index in `blog/README.md`. Two consolidations completed 2026-06-21: `sysadmin-members` (stub duplicate) deleted into `sysadmin-audit`; `writelog-tempdb` merged as a section of the `writelog` post.

For each script that merits a post:

1. Draft in `blog/<slug>/index.md` using `blog/_template/index.md`
2. Take screenshots; add to `images/`, replace `<!-- SCREENSHOT: ... -->` markers
3. Publish to sqldba.blog
4. Add `-- Blog: https://sqldba.blog/<slug>/` to the SQL script header in the repo

The repo's internal documentation layer is the script header only (Purpose, Requires, SAFE/IMPACT annotations). Internal docs otherwise stay light and general — no per-script READMEs or sidecars.

### Phase 4 — CI and quality gates (complete 2026-06-17)

| Item | Status | Notes |
|------|--------|-------|
| GitHub Actions: Pester | ✅ | `Invoke-Pester tests/` on push — SqlPathResolution, WrapperParity, New-MultiServerScript |
| GitHub Actions: PSScriptAnalyzer | ✅ | Covers all `.ps1` under sql/, powershell/, web-ui/, tools/ |
| GitHub Actions: markdownlint | ✅ | `.markdownlint.jsonc` wired via ci.yaml (excludes blog/ and CLAUDE.md) |
| GitHub Actions: SQL standards audit | ✅ | `Get-StandardsAudit.ps1 -FailsOnly` — fails CI on any FAIL status |
| GitHub Actions: secrets scan | ✅ | gitleaks on full history |
| SQLFluff | — | Not added — Get-StandardsAudit covers NOLOCK, deprecated views, USE, GO |

---

## Phase 6 — Web UI overhaul (started 2026-07-03)

Objective: the web UI is where script output is viewed, verified, and signed off — and the end
state is diagnosing SQL Server issues from a production DBA's perspective. Staged deliberately
(AI credit/limit pacing); each stage ships and is verified independently. Multi-server dashboard
is acknowledged **future** work beyond these stages.

| Stage | Item | Status | Notes |
|-------|------|--------|-------|
| 1 | **Data strip** — one collect action, many lenses: shared status strip on Health/Security/Disk/AI pages (server · collected age · 39/39 OK), collection-history dropdown, single Collect button; per-page Run buttons removed | ✅ 2026-07-03 | All lens pages re-render from any selected folder without re-collecting |
| 2 | **AI Assessment page** (`/ai`) — list reports from output-files\assessments (API + claude-code badged), verdict preview, markdown → HTML rendering, Run panel (DryRun always; live run when ANTHROPIC_API_KEY set; guidance link otherwise) | ✅ 2026-07-03 | New `/api/run-ai` endpoint wraps Invoke-AiAssessment.ps1 |
| 3 | **Security drill-down** — 3 levels: clickable vital counts (failed logins, sysadmins, weak logins, orphaned users, certs, surface area) → expandable CSV table → row detail with remediation T-SQL; sysadmin↔weak-login cross-reference flagged inline | ✅ 2026-07-03 | `Build-DrillTable` shared helper; vanilla JS, server-rendered tables |
| 4 | **Health Check scorecard + delta** — severity + per-category chips that filter findings; "N new / M resolved" vs previous collection with expandable lists; findings.csv auto-generated when missing | ✅ 2026-07-03 | Delta = keyed diff of two findings.csv files |
| 5 | **Triage → live incident cockpit** — Get-* entries gain Run ▶ (via /api/run + /api/csv) with results tabled inline; Create-*/Generate-* stay view-first for safety; Scripts stays the browse/reference library | ✅ 2026-07-03 | Mirrors the powershell/diagnostics split in the UI |

## Phase 6.1 — Web UI fixes (started 2026-07-03)

Post-overhaul fixes with a DBA-lens focus: skew-proof visuals and everything ordered by
production DBA usage. Staged; each stage verified against local SQL before pushing.

| Stage | Item | Status | Notes |
|-------|------|--------|-------|
| 1 | **DBA visual pass** — disk page charts redesigned as two lenses (% used worst-first for all DBs = urgency, skew-proof; top-15 absolute GB = capacity), per-bar severity colours, dynamic chart height; table name-bars sqrt-scaled so small DBs stay visible next to a multi-TB outlier; canonical DBA category order (performance, monitoring, backups, security, HA, …, lab) applied to home page SQL + workflow groups with only top-2 expanded; CSV list groups sorted freshest-first; Health Check + Security pages open with a one-line verdict summary (findings counts / SA · xp_cmdshell · sysadmins · weak logins) | ✅ 2026-07-03 | `Get-CategoryRank` + `$script:SqlCategoryOrder` / `$script:PsCategoryOrder` in Start-WebUi.ps1 |
| 2 | **Quick correctness fixes** — shared `ConvertTo-JsonError` helper for all API handlers (hand-rolled -replace chains missed control chars in SQL error text); direct-PS1 Run ▶ now passes only params the script declares (binding errors / silent-$args, same bug class as run.ps1 alias fix); healthcheck script count derived from Invoke-HealthCheckCollection.ps1 instead of hardcoded 39 | ✅ 2026-07-03 | Suspected unencoded `p=` fetch params turned out fine — values are pre-encoded server-side with `EscapeDataString` |
| 3 | **Clear Output safety** — `output-files\assessments\` exempt from /api/clear-output so AI sign-off reports survive the wipe; confirm dialog says so | ✅ 2026-07-03 | Verified with a non-destructive dry-run of the filter (641 of 647 files deletable, 6 assessment files kept) |
| 4 | **Non-blocking collect + progress** — background job + `/api/status` polling; UI stays responsive during collection, shows per-script progress | Planned | Largest item; ships last |

---

## Tools enhancements (backlog, no fixed phase)

| Item | Description | Notes |
|------|-------------|-------|
| Test-ServerNetwork tool | Port checker that always tests 1433 when a SQL Server is the target; clear messaging for port closed vs DNS not found vs connection refused; useful as a pre-flight before any remote script run | Peter has a port list for AG clusters — update when available |
| AG cluster port checker | Comprehensive port check for AG environments: 1433, RPC (135), mirroring endpoint, AG endpoint, optional named instance browser (1434) | Builds on existing `testing-remote-server-port-connectivity-with-powershell` post |
| Server connection diagnostics | Good terminal output when connecting to a specific or multiple servers — indicate what's being tested, surface failures with actionable messages | Pair with Test-ServerNetwork; consider how this scales to multi-server |
| Multi-server design | Decide consistent pattern for passing server lists to scripts — fleet-wide vs targeted; credential handling; output format with `Server` column prepended | Already partially in `powershell/reporting/multi-server/`; needs a design decision before expanding |
| Error messages as blog content | Any notable error encountered during builds/runs is a candidate for an evergreen post; minimal format — what the error means, the fix, when it happens | Process, not code — add to blog backlog as errors come up |

## Phase 5 — Automation and intelligence (no timeline, unstarted)

These extend the existing collector and reporting infrastructure into scheduled, multi-server, and predictive capability.

### Phase 5 items

| Item | Description | Entry point | Dependencies |
|------|-------------|-------------|--------------|
| Multi-server collector | Run any named collector against a list of servers in one command | `Invoke-MultiCollector.ps1 -Collector wait-stats -Servers "SVR01,SVR02"` | Existing 12 collectors; multi-server script pattern from `powershell/reporting/multi-server/` |
| Baseline comparison | Load pre/post CSV export sets, diff every metric, flag regressions | `Compare-MigrationBaseline.ps1 -Before .\before\ -After .\after\` | `Export-MigrationBaseline.ps1` already produces source CSVs |
| Trend forecasting | Project when a database or disk will run out of space based on MB/day growth rate | `Get-DatabaseGrowthForecast.sql` (already exists, requires DatabaseGrowth collector) | `Generate-CollectorJob-DatabaseGrowth.sql` must be installed and collecting |
| Assessment scheduling | Run `Invoke-AssessmentReport.ps1` on a schedule, email the output | SQL Agent job or Task Scheduler; add `-Email` param to existing script | `Invoke-AssessmentReport.ps1` already exists; needs SMTP param and agent DDL |

### Design notes

- **Multi-server collector:** follow the same pattern as `MultiServer-Get*.ps1` scripts — parallel `Invoke-Command`, aggregate results with a `Server` column prepended. Credential handling via the existing `$env:DBASCRIPTS_*` env vars.
- **Baseline comparison:** CSVs already have consistent column names per script — diff logic is straightforward. Flag columns where delta exceeds a threshold (e.g. query duration +20%, missing index impact doubled).
- **Trend forecasting:** slope of the last N days of `collector.DatabaseGrowthCurrent` rows gives MB/day; divide remaining free space by MB/day for days-until-full. Already partially in `Get-DatabaseGrowthForecast.sql`.
- **Assessment scheduling:** lowest effort of the four — add `-EmailTo`, `-SmtpServer` params to `Invoke-AssessmentReport.ps1`, wrap in a SQL Agent job DDL generator (`Generate-AssessmentScheduleJob.sql`).

---

## Completion log

| Date | Item |
|------|------|
| 2026-07-03 | Web UI Phase 6 complete (all 5 stages + polish: data strip, /ai page, security drill-down, scorecard+delta, triage cockpit, disk donuts + summary + name-bars, favicon); powershell/diagnostics/ created (Get-ActiveRequests, Get-BlockingChains moved from reporting/); powershell/collectors ghost references purged from docs + Initialize-Environment + Quick-RepoCheck; 55 stale SQL paths fixed in web UI top/triage lists; Restart-WebUi self-kill filter fixed (launch-signature match); Start-WebUi friendly port-conflict message; Get-MaintenanceJobStatus name filter widened (DBA - % → DBA %); 5 blog seeds captured from build sessions |
| 2026-07-02 | AI assessment layer — healthcheck is now collect → rules review → AI assessment; `Invoke-AiAssessment.ps1` (Claude API, `ANTHROPIC_API_KEY`/`ANTHROPIC_BASE_URL` env vars, `-DryRun` prompt preview) + shared `ai-assessment-rubric.md`; Claude Code sessions perform the assessment directly per ai-playbook; collection expanded 32→39 scripts (sysadmin-members, instance-config, top-cpu-queries, agent-jobs-overview, orphaned-users, certificate-expiry, autogrowth-history); `docs/ai-assessment.md` setup guide incl. corporate repointing; Test-ServerNetwork.ps1 shipped (local service check, SQL Browser SSRP port resolution, -AgCluster/-FciCluster); traces added to blog taxonomy (troubleshooting) |
| 2026-06-21 | Phase 3 planning — 39-post publishing queue added to blog/README.md across 7 waves; 6 missing blog posts added to index (sysadmin-members, login-activity-trace, fci-node-blip, replication-monitoring, mirroring-health, mirroring-troubleshooting); sysadmin-members stub deleted (duplicate of sysadmin-audit); writelog-tempdb merged as "When tempdb is the source" section of writelog post; roadmap current state updated |
| 2026-06-21 | Security page — Build-SecurityPage + Build-SecurityScripts added to web UI; /security route wired; nav link added; Get-DatabaseMailAndXpCmdShell.sql updated with force encryption (sys.dm_server_registry) and NTLM connection count (sys.dm_exec_connections); Surface Area vitals (xp_cmdshell CRITICAL, CLR WARN, Force Encryption WARN, NTLM WARN) + Access Risk vitals (SA, weak logins, locked accounts, brute-force); findings panel with filter JS; security scripts grid |
| 2026-06-20 | CONTRIBUTING.md rewrite — Peter Whyte as lead and author established; mission statement; SQL header Author field fixed to Peter Whyte (<https://sqldba.blog>); Pester test instructions added |
| 2026-06-20 | README.md — author identity added to What This Is; health check count corrected 27→32; AssessedBy placeholder fixed; Contributing blurb updated |
| 2026-06-20 | docs/standards.md — wrapper depth updated to cover both 3-level and 4-level cases with subfoldered path example |
| 2026-06-20 | CLAUDE.md — outdated standards.md caveat corrected; both files now described as in sync |
| 2026-06-20 | CI fix — Get-ActiveRequests.ps1 and Get-BlockingChains.ps1 path references corrected to active-sessions/ and blocking-locking/ subdirs; 4 Pester failures resolved; 635/635 passing |
| 2026-06-17 | Phase 4 CI — SQL standards audit job added to ci.yaml; Get-StandardsAudit.ps1 updated to exit 1 on failures and validate annotation position; WrapperParity.Tests.ps1 added; blog/ role and Phase 3 definition clarified in CLAUDE.md, roadmap, and standards.md; sub-READMEs (tools/, powershell/, tools/local-sql/) updated to remove stale script references |
| 2026-06-17 | CLAUDE.md update — SQL header standard revised: Safe/Impact removed from block comment, inline annotations moved above SET NOCOUNT ON; 146 SQL scripts, 3 doc files, CONTRIBUTING.md, and Get-StandardsAudit.ps1 updated to match; blog posts corruption fixed (40 files); repo-structure.md, standards.md, quick-start.md aligned to CLAUDE.md layout; Get-Databases.ps1 wrapper added |
| 2026-06-15 | Moved thin wrappers to `powershell/wrappers/<cat>/` — clean separation from orchestrators; PSScriptRoot depth 3 levels; all tooling and docs updated |
| 2026-06-14 | Repo restructure — category-first layout: `sql/`, `powershell/`, `powershell/runners/`, `docs/ops/`; all path references updated across 132+ files |
| 2026-06-05 | `wrappers/` top-level folder — 81 thin PS wrappers separated from `powershell/`, mirrors `sql/` category structure |
| 2026-06-05 | Phase 2 PS standards — `.NOTES` block (ScriptType, TargetScope, RiskLevel, Purpose) added to all remaining non-compliant PS scripts |
| 2026-06-05 | 7 new PS wrappers — Get-Heaps, Get-UnusedIndexes, Get-CompatibilityLevelAudit, Get-MigrationLoginAudit, Get-PostMigrationValidation, Generate-LinkedServerScript, Generate-RestoreWithMoveScript |
| 2026-06-05 | `docs/repo-structure.md` and `docs/script-catalog.md` — accurate structure and full script list |
| 2026-06-04 | Generate-BackupJobs/IndexMaintenanceJobs/MaintenanceJobs — fixed OutputFormat=Csv path so web UI renders DDL as code block |
| 2026-06-04 | Web UI — collapsible SQL categories, Workflows section, IsWrapper detection, chart improvements, threshold markers |
| 2026-06-03 | P6 SQL scripts — Get-TempDbConfiguration, Get-PlanCacheHealth, Get-ReadableSecondaryUsage, Get-BackupEncryptionStatus, Get-LinkedServerSecurity, Get-DatabasePermissions, Get-ProxyAndCredentials, Get-LockEscalationStats |
| 2026-06-03 | `Invoke-MultiServerHealthCheck.ps1` — server list → per-server collection → aggregated CRITICAL/WARNING report |
| 2026-06-03 | `Compare-CollectorSnapshots.ps1`, `Invoke-CollectorAlert.ps1` — post-incident collector analysis and threshold alerting |
| 2026-06-03 | Collectors: query-store, index-fragmentation, vlf-count, errorlog — all 12 collectors now complete with READMEs |
| 2026-06-03 | `Initialize-Environment.ps1` + `SETUP.md` — new machine onboarding |
| 2026-06-03 | `tests/New-MultiServerScript.Tests.ps1`, `tests/SqlPathResolution.Tests.ps1` — Pester smoke tests |
| 2026-06-03 | Multi-server scripts — 12 self-contained scripts, parallel execution, credential template, result collection with Server column |
| 2026-05-29 | Full canonical layout, all scripts single-result-set, standard headers, no NOLOCK, no deprecated catalog views |
| 2026-05-29 | 8 initial collectors — wait-stats, blocking, deadlocks, tempdb, perfmon, ag-health, storage-io, database-growth |
| 2026-05-29 | `Invoke-HealthCheckCollection.ps1` (32 scripts) + `Review-HealthCheckOutput.ps1` |
