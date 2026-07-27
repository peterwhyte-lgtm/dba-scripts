# DBA Scripts hub — page organization (planning doc)

Renamed from `most-used-scripts.md`. Scope: **DBA Scripts category posts only** — the IA for
the `/scripts/` project page redesign. The live category archive
(sqldba.blog/category/dba-scripts/) is just a flat reverse-chron list; this doc plans a
proper hub page that branches into obvious subcategories, the way the Wait Types library
uses a pillar page + standard pages. **Draft — Peter to edit/reorder/cut.**

Status grounded in `personal/tools/site-publisher/PUBLISHING.md` +
`personal/tools/site-lab/STAGING-VS-LIVE.md` (generated 2026-07-25) and this repo's
`docs/script-catalog.md`. Legend: 🟢 live · 🟡 staged (written, awaiting Peter's push-live) ·
⚪ planned (not yet drafted).

---

## Page concept

```
/scripts/  (the project page — currently a plain description page, WP #dba-scripts-project)

  [Hero] "DBA Scripts" — what the project is, link to dba-tools repo, count of live/planned posts

  [Featured row] the LIVE posts only — no "coming soon" teasers, grows as more go live

  [Branch: Performance]                →  card grid or whatever reads well —
  [Branch: Monitoring]                    categorization is the part that matters here,
  [Branch: Instance & Configuration]      visual treatment is a later design pass
  [Branch: Backups & Recovery]
  [Branch: Security]
  [Branch: High Availability & DR]
  [Branch: Migration & Upgrades]
  [Branch: Maintenance]
  [Branch: Troubleshooting / Traces]

  [Footer strip] "New to a server? Start with a full health check" → the flagship
                 Invoke-HealthCheckCollection → AI assessment workflow post (#34)
```

Each branch = a subcategory section on the page: short one-line description of the
question it answers, then a list of scripts with live links where they exist. Branches
mostly mirror the repo's own `sql/<category>/` taxonomy (`dba-tools/CLAUDE.md`), with one
deliberate addition — **Instance & Configuration** — split out as its own branch below.

## Decisions (resolved from the last review)

- **Featured row is live-only.** No staged/planned "coming soon" entries — it's literally
  the current live set, and it grows as posts go live. Nothing to build until then.
- **Design is secondary to categorization.** Card grid, accordion, whatever looks good —
  pick that in the actual design pass. Getting the subcategory split right matters more
  right now.
- **Traces stay under DBA Scripts, tagged Troubleshooting.** The 6 trace posts will also
  carry a Troubleshooting category/tag on the live site, but they're still DBA Scripts
  posts first and belong in this hub.
- **Instance & Configuration is now its own branch**, not a callout box. It covers both
  "onboarding a new/inherited server" *and* the ongoing fleet angle — versions, patch
  levels, and config drift don't stay static across a fleet, so this is a recurring
  reference branch, not a one-time checklist.

---

## Featured row — the live set (9)

| Script | Branch |
|--------|--------|
| [Get VLF Counts](https://sqldba.blog/dba-scripts-get-vlf-counts/) | Performance |
| [Get Heaps](https://sqldba.blog/dba-scripts-get-heaps/) | Performance |
| [Get Index Fragmentation](https://sqldba.blog/dba-scripts-get-index-fragmentation/) | Performance |
| [Get Transaction Log Size and Usage](https://sqldba.blog/dba-scripts-get-transaction-log-size-and-usage/) | Monitoring |
| [Get Autogrowth History](https://sqldba.blog/dba-scripts-get-autogrowth-history/) | Monitoring |
| [Get Database Sizes and Free Space](https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/) | Monitoring |
| [Get Database Files Detail](https://sqldba.blog/dba-scripts-get-sql-server-database-file-details/) | Monitoring |
| [Get Last DBCC CHECKDB](https://sqldba.blog/dba-scripts-get-last-dbcc-checkdb/) | Maintenance |
| [Get Sysadmin Members](https://sqldba.blog/dba-scripts-get-sysadmin-members/) | Security |

---

## Branch: Performance

*"Why is this slow, right now or on a pattern."*

| Script | Status |
|--------|--------|
| Get Blocking Chains (+plan) | 🟡 staged (#27) |
| Get Active Requests / Active Sessions (+plan) | ⚪ planned (#47) |
| Get Long-Running Queries | 🟡 staged (#03) |
| Get Wait Statistics | 🟡 staged (#04) |
| Get Deadlock Summary | 🟡 staged (#29) |
| Get Missing Indexes | 🟡 staged (#02) |
| Get Unused Indexes | 🟡 staged (#31) |
| Get Duplicate Indexes | 🟡 staged (#50) |
| Get Index Fragmentation | 🟢 [live](https://sqldba.blog/dba-scripts-get-index-fragmentation/) |
| Get Index Fragmentation Across Databases | 🟡 staged (#07, refit) |
| Get Index Design Issues | 🟡 staged (#53) |
| Get Heaps | 🟢 [live](https://sqldba.blog/dba-scripts-get-heaps/) |
| Get Statistics Health | 🟡 staged (#32) |
| Get Top CPU/IO Queries | ⚪ planned (#28, trash stale WP draft first) |
| Get Implicit Conversions | 🟡 staged (#52) |
| Get Memory Grant Spills | ⚪ planned (#55) |
| Get Query Store Top Queries / Status / Regressions / Forced Plans | 🟡 staged (#33, #63) / ⚪ planned (#56) |
| Get Contention Analysis | ⚪ planned (#48) |
| Get Lock Escalation Stats | ⚪ planned (#90) |

## Branch: Monitoring

*"Is this instance healthy right now, and will it stay that way."*

| Script | Status |
|--------|--------|
| Get VLF Counts | 🟢 [live](https://sqldba.blog/dba-scripts-get-vlf-counts/) |
| Get Transaction Log Size and Usage | 🟢 [live](https://sqldba.blog/dba-scripts-get-transaction-log-size-and-usage/) |
| Get Autogrowth History | 🟢 [live](https://sqldba.blog/dba-scripts-get-autogrowth-history/) |
| Get Disk Space | 🟡 staged (#08) |
| Get Database Health | 🟡 staged (#61) |
| Get Database Sizes and Free Space | 🟢 [live](https://sqldba.blog/dba-scripts-get-database-sizes-and-free-space/) |
| Get Database Files Detail | 🟢 [live](https://sqldba.blog/dba-scripts-get-sql-server-database-file-details/) |
| Get Database Growth Risk / Growth Events / Growth Forecast | ⚪ planned (#60) |
| Get TempDB Hotspots | 🟡 staged (#37) |
| Get TempDB Configuration | 🟡 staged (#58) |
| Get SQL Agent Job Overview | 🟡 staged (#12, refit) |
| Get SQL Agent Job Failure Summary | 🟡 staged (#36) |
| Get Maintenance Job Status | 🟡 staged (#66) |
| Get Recent Error Log Entries | 🟡 staged (#62) |
| Get Query Store Status | 🟡 staged (#63) |
| Get CDC and Change Tracking | ⚪ planned (#64) |
| Get Extended Events Sessions | ⚪ planned (#65) |
| Get Service Broker Health | ⚪ planned (#87) |
| Get Agent Alerts and Operators | 🟡 staged (#59) |

## Branch: Instance & Configuration

*"What do we actually have — one server today, and the whole fleet over time. Versions,
patch levels, and config drift don't stay put, so this branch is a recurring reference,
not a one-time onboarding checklist."*

| Script | Status |
|--------|--------|
| Get Instance Configuration Score | 🟡 staged (#39) |
| Get Instance Configuration Snapshot | 🟡 staged (#17, refit) |
| Get Version and Edition | 🟡 staged (#16, refit) |
| Get Patch Level | ⚪ planned (#77 — site-crawler draft exists, quick win) |
| Get OS and Hardware Info / OS Configuration Checks | ⚪ planned (#57) |
| Get Trace Flags | ⚪ planned (#81) |
| Get Table Sizes | 🟡 staged (#49) |
| Get Database Summary | ⚪ planned (not yet queued individually in PUBLISHING.md) |
| Get Server Inventory (logins, jobs, linked servers) | ⚪ planned (#78) |
| Get Database Inventory | ⚪ planned — see also Migration branch |
| Compare Configuration Baseline (drift vs. saved baseline) | ⚪ planned — fleet config-drift angle, not yet queued as a post |
| Get Capacity Projection (collector trend analysis) | ⚪ planned — fleet capacity-planning angle, not yet queued as a post |
| Multi-server fleet-view scripts (`MultiServer-Get*`: patch level, database sizes, disk space, backup status, blocking, wait stats, service status, firewall rules, event logs; `Invoke-MultiServerHealthCheck`) | ⚪ planned — matches the repo-wide note that multi-server ("the many part") is a planned build-out, not yet current scope |

## Branch: Backups & Recovery

*"Are we actually protected, and how fast could we get back up."*

| Script | Status |
|--------|--------|
| Get Backup Coverage | 🟡 staged (#18, refit in place on WP #972) |
| Get Last Database Backup Times | 🟡 staged (#76, refit in place on WP #518) |
| Get Backup and Restore Duration Estimate | 🟡 staged (#19, rescoped 2026-07-26 — no longer covers completion time, that's #93) |
| Get Backup Chain Integrity | 🟡 staged (#74) |
| Get Backup Encryption Status | 🟡 staged (#75) |
| Get Database Backup History | 🟡 staged (#94) |
| Get Backup and Restore Progress | 🟡 staged (#93) |
| Generate Full/Diff/T-Log Backup + Restore Scripts | ⚪ planned (#100) — Phase 3, different shape (DDL generator, 4 scripts bundled) |

All 8 Backups & Recovery posts now staged. Two live legacy posts (`estimate-backup-and-restore-completion-time-in-sql-server`
and WP #1034) still duplicate #93's territory now that #19 moved off it — needs Peter's pick-one-and-redirect call, not yet done.

## Branch: Security

*"Who can do what, and is anything obviously exposed."*

| Script | Status |
|--------|--------|
| Get Sysadmin Members | 🟢 [live](https://sqldba.blog/dba-scripts-get-sysadmin-members/) |
| Get Weak Login Settings | (folded into #21, live) |
| Get User Permissions Audit | ⚪ planned (#20) |
| Get Orphaned Users | 🟡 staged (#40) |
| Get Failed Login Summary | ⚪ planned (#67) |
| Get Database Mail and xp_cmdshell Configuration | 🟡 staged (#22, refit) |
| Get Audit Specifications | ⚪ planned (#68) |
| Get TDE Status / Certificates and Keys | ⚪ planned (#69, #95) |
| Get Linked Server Security | ⚪ planned (#70) |
| Get DDL Triggers | ⚪ planned (#96) |
| Get Proxies and Credentials | ⚪ planned (#97) |

## Branch: High Availability & DR

*"If we failed over right now, would it work — and what's replicating."*

| Script | Status |
|--------|--------|
| Get Availability Group Replica State | ⚪ planned (#23, split-merge draft) |
| Get Availability Group Latency | ⚪ planned (#24, split-merge draft) |
| Get AG Failover Readiness / Readable Secondary Usage | ⚪ planned (#71) |
| Get Replication Status | 🟡 staged (#43) |
| Get Mirroring Status / Endpoint Health | ⚪ planned (#44, deprecated-feature label) |
| Get Last Node Blip (FCI) | ⚪ planned (#42) |

## Branch: Migration & Upgrades

*"Getting on/off this server safely, or getting it to a newer version."*

| Script | Status |
|--------|--------|
| Get Migration Risk Assessment | 🟡 staged (#46) |
| Get Version Upgrade Readiness / Compatibility Audit / Deprecated Features / Edition Features | ⚪ planned (#72) |
| Get Migration Login Audit / Post-Migration Validation | ⚪ planned (#73) |
| Get Database Inventory | ⚪ planned (part of #78 server inventory) |
| Generate Login / Agent Job / User Mapping / Linked Server / Restore-With-Move Scripts | ⚪ planned (#101) |
| Fix Orphaned Users | ⚪ planned (pairs with #40) |

## Branch: Maintenance

*"Keeping the lights on — the Ola Hallengren benchmark."*

| Script | Status |
|--------|--------|
| Get Last DBCC CHECKDB | 🟢 [live](https://sqldba.blog/dba-scripts-get-last-dbcc-checkdb/) |
| Get Maintenance Job Status | 🟡 staged (#66) |
| Generate Maintenance Jobs (CHECKDB, history cleanup, error log cycle) | ⚪ planned (#99 — "the Ola-benchmark story") |
| Generate Index Maintenance Jobs / Script | ⚪ planned (folds into #99/#30) |
| Generate Backup Jobs | ⚪ planned (folds into #100) |
| Collector Jobs Suite (12 collectors + delta queries) | ⚪ planned (#103 — pillar-sized, could be its own mini-series) |

## Branch: Troubleshooting / Traces

*"Something specific broke — go get evidence."* The 6 trace posts double-tag Troubleshooting
on the live site but are DBA Scripts posts first, so they live in this hub.

| Script | Status |
|--------|--------|
| Create Login Activity Session | 🟡 staged (#104) |
| Create Decommission Audit Session | 🟡 staged (#105) |
| Create SP Execution Session | 🟡 staged (#106) |
| Get Active XE Sessions | 🟡 staged (#107) |
| Get XE Session Activity | 🟡 staged (#108) |
| Remove XE Session | 🟡 staged (#109) |
| Get Suspect Pages | ⚪ planned |
| Get Schema Change History | ⚪ planned (#83) |

---

## Still open

- Actual visual layout (card grid vs. accordion vs. anchored sections) — a design pass once
  the branch list above is signed off.
