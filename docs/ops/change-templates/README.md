# Change templates

Reusable SQL for common planned DBA operations. Copy the template, fill in the variables, review it,
then run it. Nothing here is safe to run unread — these are the scripts that change the server.

This folder also serves as the index for the whole [`docs/ops/`](../) area, which covers the work you
schedule rather than the work that ambushes you.

## SQL templates in this folder

| Template | Purpose |
|----------|---------|
| [`Configure-AlwaysOn-AvailabilityGroup-Template.sql`](Configure-AlwaysOn-AvailabilityGroup-Template.sql) | AG creation and replica configuration |
| [`Configure-Cdc-Template.sql`](Configure-Cdc-Template.sql) | Enable CDC on a database |
| [`Configure-Mirroring-Template.sql`](Configure-Mirroring-Template.sql) | Database mirroring setup |
| [`Configure-Tde-Template.sql`](Configure-Tde-Template.sql) | Transparent Data Encryption |
| [`Database-Consistency-Check-Template.sql`](Database-Consistency-Check-Template.sql) | DBCC CHECKDB workflow |
| [`Pre-OSUpgrade-Readiness.sql`](Pre-OSUpgrade-Readiness.sql) | Pre-flight checks before an OS upgrade |
| [`Recompile-Procedure-Template.sql`](Recompile-Procedure-Template.sql) | Force recompile of stored procedures |
| [`Restore-Database-NoRecovery-Template.sql`](Restore-Database-NoRecovery-Template.sql) | Restore `WITH NORECOVERY` for log shipping or AG seeding |
| [`Update-Statistics-Template.sql`](Update-Statistics-Template.sql) | Statistics update workflow |
| [`change-template-installation.sql`](change-template-installation.sql) | SQL Server installation checklist queries |
| [`change-template-patching.sql`](change-template-patching.sql) | Pre and post-patch validation queries |

## The change lifecycle

1. **[`../change-orders/`](../change-orders/)** — get approval before you start. Documents the pre and
   post checks and the rollback criteria.
2. **[`../checklists/`](../checklists/)** — execute step by step during the window.
3. **[`../runbooks/`](../runbooks/)** — the full playbook when a checklist is not enough detail.
4. **[`../rollback/`](../rollback/)** — trigger criteria and the steps back, if it goes wrong.

### Change orders

| Document | Use for |
|----------|---------|
| [`sql-server-upgrade-change-order.md`](../change-orders/sql-server-upgrade-change-order.md) | SQL Server version upgrade, in-place or side-by-side |
| [`server-migration-change-order.md`](../change-orders/server-migration-change-order.md) | Hardware or VM server replacement |
| [`alwayson-planned-failover-change-order.md`](../change-orders/alwayson-planned-failover-change-order.md) | AG planned failover or replica maintenance |

### Checklists

| Checklist | Use for |
|-----------|---------|
| [`sql-version-upgrade.md`](../checklists/sql-version-upgrade.md) | SQL Server version upgrade |
| [`alwayson-migration.md`](../checklists/alwayson-migration.md) | AG failover, replica addition or removal, listener changes |
| [`server-replacement.md`](../checklists/server-replacement.md) | Physical or VM server replacement |
| [`dr-failover.md`](../checklists/dr-failover.md) | DR failover and failback |

### Runbooks

| Runbook | Covers |
|---------|--------|
| [`RUNBOOK-Standalone.md`](../runbooks/RUNBOOK-Standalone.md) | Standalone server migration by backup and restore |
| [`RUNBOOK-AG-Cluster.md`](../runbooks/RUNBOOK-AG-Cluster.md) | AG cluster migration and failover |
| [`RUNBOOK-OsUpgrade.md`](../runbooks/RUNBOOK-OsUpgrade.md) | OS upgrade, in-place or side-by-side |
| [`RUNBOOK-SqlEditionChange.md`](../runbooks/RUNBOOK-SqlEditionChange.md) | Edition upgrade or downgrade |
| [`RUNBOOK-SqlVersionUpgrade.md`](../runbooks/RUNBOOK-SqlVersionUpgrade.md) | SQL Server version upgrade end to end |

### Rollback

[`../rollback/migration-rollback-playbook.md`](../rollback/migration-rollback-playbook.md) — binary
trigger criteria, who owns the decision, and the steps back for each migration type.

### Mid-incident lookup

[`../dba-quickref.md`](../dba-quickref.md) — the one to have open when something is already on fire.
