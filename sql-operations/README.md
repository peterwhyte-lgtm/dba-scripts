# sql-operations

Production SQL Server operational scripts and automation — organised by lifecycle phase.

## Structure

```text
sql-operations/
  change-templates/    — SQL operational runbook templates (CDC, TDE, AG, statistics, etc.)
  installation/        — SQL Server installation automation
    templates/         — INI answer files per environment/edition
  patches/             — SQL Server CU updates and SSMS updates
```

## change-templates

SQL-level runbook templates for common DBA change operations. Copy, review, and adapt before running in production.

| Template | Purpose |
|----------|---------|
| `Configure-AlwaysOn-AvailabilityGroup-Template.sql` | AG creation and replica configuration |
| `Configure-Cdc-Template.sql` | Enable CDC on a database |
| `Configure-Mirroring-Template.sql` | Database mirroring setup |
| `Configure-Tde-Template.sql` | Transparent Data Encryption |
| `Database-Consistency-Check-Template.sql` | DBCC CHECKDB workflow |
| `Pre-OSUpgrade-Readiness.sql` | Pre-flight checks before OS upgrade |
| `Recompile-Procedure-Template.sql` | Force recompile stored procedures |
| `Restore-Database-NoRecovery-Template.sql` | Restore with NORECOVERY for log shipping/AG |
| `Update-Statistics-Template.sql` | Statistics update workflow |

## installation

```powershell
# Interactive mode — prompts for all settings
.\sql-operations\installation\Install-SqlServer.ps1

# Unattended with params
.\sql-operations\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -SAPassword (ConvertTo-SecureString 'MyStr0ng!Pass' -AsPlainText -Force)

# Using an answer file (recommended for repeatable env installs)
.\sql-operations\installation\Install-SqlServer.ps1 `
    -SetupPath D:\SQL2022\setup.exe `
    -AnswerFile .\sql-operations\installation\templates\sql-server-install-default.ini `
    -SAPassword (ConvertTo-SecureString 'MyStr0ng!Pass' -AsPlainText -Force)
```

**What the installer does:**
- Validates elevation, directories, and SA password complexity
- Calculates recommended MaxMemory and MaxDOP from hardware
- Runs `setup.exe` with TCP enabled, named pipes off, SQL Agent set to Automatic
- Applies MaxMemory, MaxDOP, and cost threshold for parallelism post-install
- Logs everything to `output-files\installation\`

## patches

```powershell
# Apply a CU to all instances (patch file downloaded separately)
.\sql-operations\patches\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe

# Apply to a specific instance only
.\sql-operations\patches\Update-SqlServer.ps1 `
    -PatchPath C:\Patches\SQLServer2022-KB5046059-x64.exe `
    -InstanceName SQL2022

# Update SSMS via winget (default)
.\sql-operations\patches\Update-Ssms.ps1

# Update SSMS via direct download
.\sql-operations\patches\Update-Ssms.ps1 -Method download
```

Download SQL Server CU patches from:
https://support.microsoft.com/en-us/help/321185
