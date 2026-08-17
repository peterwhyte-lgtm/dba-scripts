# Migration SQL

Thirteen scripts for moving a database or an instance: work out what will break before the window,
generate the DDL you need to recreate the server-level objects, and prove afterwards that nothing was
lost.

All thirteen are read-only. The `Generate-*` scripts build a T-SQL script as their output and hand it
to you as text — nothing is created until you review that output and run it yourself.

## Before the window — assessment

| Script | What it returns |
|--------|-----------------|
| `Get-MigrationRiskAssessment` | The one to run first. Categorised HIGH / MEDIUM / INFO findings across compatibility, database settings, linked servers, AG membership, and sizing |
| `Get-VersionUpgradeReadiness` | Pre-upgrade readiness summary for a version upgrade |
| `Get-CompatibilityLevelAudit` | Every user database with its current compatibility level, the SQL version that maps to, and the instance native level |
| `Get-DeprecatedFeaturesInUse` | Deprecated features actually used since the last restart, ranked by usage count — not the full list of what is deprecated |
| `Get-EditionFeatureUsage` | Enterprise-only features in active use, so a downgrade to Standard does not surprise you |
| `Get-MigrationLoginAudit` | Every server principal that has to move, classified by type with the action each one needs |

## Recreating server-level objects — DDL generators

Databases move with backup and restore. Everything that lives *outside* the database does not, and
these are what rebuild it on the target.

| Script | Generates |
|--------|-----------|
| `Generate-LoginScript` | `CREATE LOGIN` for all non-system logins, with SIDs and hashed passwords preserved |
| `Generate-UserMappingScript` | `CREATE USER` and role membership DDL for all user databases |
| `Generate-AgentJobScript` | `sp_add_job` DDL to recreate every SQL Agent job |
| `Generate-LinkedServerScript` | `sp_addlinkedserver` + `sp_addlinkedsrvlogin` DDL for all linked servers |
| `Generate-RestoreWithMoveScript` | `RESTORE DATABASE ... WITH MOVE` for all online user databases, for a target with different drive paths |

Preserving login SIDs is what stops every database user from being orphaned on the target. Do the
logins before the restores where you can.

## After the window — validation

| Script | What it returns |
|--------|-----------------|
| `Get-PostMigrationValidation` | A summary of key server state. Run it on both source and target and compare the two CSVs |
| `Fix-OrphanedUsers` | `ALTER USER` statements to re-map database users whose login SID no longer matches |

## Running these

The `Get-*` scripts have the usual wrapper, so `.\run.ps1 Get-MigrationRiskAssessment` works.

**The `Generate-*` scripts do not, and must not go through `Invoke-RepoSql.ps1`.** They return a single
`NVARCHAR(MAX)` value that the normal CSV pipeline truncates. Use the matching PowerShell script in
`powershell/migration/`, which captures the full string and writes it to a `.sql` file:

```powershell
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LoginScript.ps1
.\powershell\migration\Generate-AgentJobScript.ps1
.\powershell\migration\Generate-UserMappingScript.ps1
# Output lands in output-files\migration\*.sql — review it, fix owners, then run on the target
```

## Related

- **Orchestrators** in `powershell/migration/` run the assessment scripts as a set:
  `Invoke-PreMigrationAssessment.ps1`, `Invoke-MigrationPreFlightCheck.ps1`,
  `Invoke-MigrationExport.ps1`, and `Export-MigrationBaseline.ps1` for before/after comparison.
- **Inventory scripts live in [`sql/inventory/`](../inventory/), not here** —
  `Get-DatabaseInventory`, `Get-LoginInventory`, `Get-JobInventory`, and
  `Get-LinkedServerInventory` are general-purpose and useful outside a migration.
- **Runbooks and change orders** for the whole exercise: [`docs/ops/`](../../docs/ops/).
