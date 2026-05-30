# Operations SQL templates

This folder contains reusable SQL templates for common DBA operations.

## Included templates

- Update-Statistics-Template.sql
  - Use for targeted statistics maintenance on one table or a full database.
- Recompile-Procedure-Template.sql
  - Use to refresh execution plans after schema or index changes.
- Configure-Cdc-Template.sql
  - Use to enable CDC at the database and table level.
- Configure-Tde-Template.sql
  - Use to enable Transparent Data Encryption for a database.
- Configure-Mirroring-Template.sql
  - Use as a setup and validation checklist for database mirroring.
- Configure-AlwaysOn-AvailabilityGroup-Template.sql
  - Use as a planning and validation runbook for AG setup.
- Restore-Database-NoRecovery-Template.sql
  - Use for DR or secondary recovery preparation with NORECOVERY.
- Database-Consistency-Check-Template.sql
  - Use to run a repeatable CHECKDB-style validation pass.
- Pre-OSUpgrade-Readiness.sql
  - Use to gather evidence before an OS or host upgrade.

## Safety notes

- Review permissions and service account requirements before running.
- Prefer a non-production test pass first.
- Capture output and backups before enabling new features or changing database settings.
