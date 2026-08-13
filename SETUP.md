# Environment Setup

Everything you need to go from a fresh clone to running your first query. Run the setup script for an automated check, or follow the manual steps below.

---

## Quick setup

```powershell
# Clone the repo
git clone https://github.com/peterwhyte-lgtm/dba-tools
cd dba-tools

# Run the setup script — checks prerequisites and creates output directories
.\Initialize-Environment.ps1

# With a target server — also tests connectivity and sets the session default
.\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019

# Fully automated — install missing modules + persist the server to your PS profile
.\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019 -AutoInstall -PersistProfile
```

The setup script checks everything in the sections below and tells you exactly what needs fixing. You can also do it manually.

---

## Prerequisites

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| PowerShell | 5.1 | 7+ | PS7 required for `-Parallel` in multi-server scripts and some collectors |
| SQL execution | `sqlcmd.exe` | SqlServer module | Module gives richer output; `sqlcmd.exe` is the fallback |
| SQL Server | 2016 (13.x) | 2019+ | A few scripts use DMVs added in 2017/2019 — noted in each script header |
| Network | Port 1433 reachable | — | Or custom port if SQL Server is on a non-default port |

### Install the SqlServer module

```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
```

### Install Pester (optional — for running tests)

```powershell
Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
```

### Execution policy

On a fresh Windows machine, script execution is often blocked. Fix it once:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Connect to your first SQL Server

Set the session default once — all scripts pick it up automatically:

```powershell
# Windows auth (recommended when on the same domain)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019

# SQL auth (prompts for password)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01 -Username sa

# Local instance (. = default local instance)
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance .

# Show what is currently set
.\tools\local-sql\Set-SqlConnection.ps1 -Show
```

Test that it works:

```powershell
.\tools\local-sql\Test-SqlConnectivity.ps1
```

### Making the connection survive session restarts

The `Set-SqlConnection.ps1` settings only last for the current PowerShell session. To persist across sessions, add the env var to your PowerShell profile:

```powershell
# Open your profile (creates it if it doesn't exist)
if (-not (Test-Path $PROFILE)) { New-Item $PROFILE -Force }
notepad $PROFILE

# Add this line:
$env:DBASCRIPTS_SERVER = 'PROD01\SQL2019'
```

Or let the setup script do it: `.\Initialize-Environment.ps1 -ServerInstance PROD01\SQL2019 -PersistProfile`

---

## First queries

```powershell
# Run any script by name — fuzzy search, no paths needed
.\run.ps1 Get-WaitStatistics
.\run.ps1 Get-BlockingChains
.\run.ps1 Get-BackupCoverage

# Run against a specific server
.\run.ps1 Get-WaitStatistics -ServerInstance PROD01\SQL2019

# Save output to CSV
.\run.ps1 Get-WaitStatistics -OutputFormat Csv
# Output goes to: output-files\reviews\performance\Get-WaitStatistics-<timestamp>.csv

# Find scripts by keyword
.\tools\triage\Find-UsefulScript.ps1 -Keyword blocking
.\tools\triage\Find-UsefulScript.ps1 -Keyword backup
```

---

## Health check (full instance review)

```powershell
# Run 45 scripts against an instance — saves named CSVs
.\powershell\reporting\Invoke-HealthCheckCollection.ps1 -ServerInstance PROD01\SQL2019

# Review the output — surfaces CRITICAL / WARNING / INFO findings
.\powershell\reporting\Review-HealthCheckOutput.ps1
```

What it flags: offline databases, missing backups, stale DBCC CHECKDB, suspect pages, sa enabled, percent-based autogrowth, weak SQL logins, I/O latency above threshold, memory not configured, transaction log pressure, and more.

For a client handover or ownership review:

```powershell
.\powershell\reporting\Invoke-AssessmentReport.ps1 -ServerInstance PROD01\SQL2019 -AssessedBy "Peter Whyte"
# Output: output-files\assessment\<server>-<timestamp>.md
```

---

## Browser UI

A local web interface for browsing scripts and visualising CSV output:

```powershell
.\web-ui\Start-WebUi.ps1
# Opens http://localhost:8787
```

No external dependencies for the server itself. Chart.js is loaded from CDN on the CSV chart page (requires internet for that page only).

---

## Multi-server scripts

Scripts in `powershell/multi-server/` run operations across multiple servers simultaneously. They have two extra requirements:

**For PowerShell remoting scripts** (GetDiskSpace, GetFirewallRules, GetRecentEventLogs, RestartService):

```powershell
# Run this as admin on each TARGET server:
Enable-PSRemoting -Force
```

**For SQL scripts** (GetWaitStats, GetBlockingSessions, etc.): port 1433 reachable from your machine — no remoting needed, queries run locally via `Invoke-Sqlcmd`.

```powershell
# Example: check backup status across three instances
.\tools\multi-server-scripts\sql\MultiServer-GetBackupStatus.ps1 -Servers "SVR01,SVR02,SVR03"

# Generate a custom multi-server wrapper from any SQL file
.\tools\multi-server-query\New-MultiServerScript.ps1 `
    -ScriptPath sql\performance\Get-WaitStatistics.sql `
    -Servers "SVR01,SVR02,SVR03" `
    -OutputFile C:\Temp\run-waits.ps1
```

---

## Collectors (scheduled monitoring)

Collectors run on a schedule and build timestamped CSV histories for trend analysis and post-incident review. Set them up once in SQL Agent and forget.

See [sql/collectors/](sql/collectors/) for the full list — one `Generate-CollectorJob-*.sql` per collector; running it creates the SQL Agent job and its DBAMonitor table.

**Minimum permissions** for the SQL Agent service account:

```sql
-- Most collectors
GRANT VIEW SERVER STATE TO [domain\sqlsvc];

-- Storage-IO and Database Growth collectors additionally need:
GRANT VIEW ANY DATABASE TO [domain\sqlsvc];
GRANT VIEW DATABASE STATE TO [domain\sqlsvc];
```

The service account also needs write access to the `output-files\collectors\` folder on the server.

---

## SQL Server permissions

Most read-only scripts require:

```sql
GRANT VIEW SERVER STATE TO [domain\youraccount];
GRANT VIEW ANY DATABASE TO [domain\youraccount];
```

Scripts that query individual databases (statistics health, Query Store, TempDB) additionally need:

```sql
-- In each user database:
GRANT VIEW DATABASE STATE TO [domain\youraccount];
```

Security scripts (`Get-SysadminMembers`, `Get-UserPermissionsAudit`) require `sysadmin` or a granular `VIEW ANY DEFINITION` grant depending on the script.

---

## Troubleshooting

### Scripts won't run — "execution of scripts is disabled"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Invoke-Sqlcmd not found

```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
# Or install SSMS / SQL Server Management Tools which includes sqlcmd.exe
```

### Cannot connect to SQL Server

- Verify port 1433 is reachable: `Test-NetConnection -ComputerName PROD01 -Port 1433`
- Check SQL Server Browser is running if using named instances
- Confirm the SQL Server service account has a firewall exception on the target

### Multi-server scripts fail with "Access denied" or "WinRM cannot complete the operation"

```powershell
# On each TARGET server (as admin):
Enable-PSRemoting -Force
# And add your management machine to trusted hosts if not domain-joined:
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "MGMT01" -Force
```

### Output CSVs are large / output-files/ is filling up

```powershell
.\tools\maintenance\Clear-OutputFiles.ps1
```

### PowerShell 5.1 — parallel switch does nothing

`ForEach-Object -Parallel` requires PowerShell 7+. Install from [aka.ms/powershell](https://aka.ms/powershell) or via winget:

```powershell
winget install Microsoft.PowerShell
```

### "The file is not digitally signed" on AllSigned policy

```powershell
# Either change execution policy:
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or unblock the downloaded files:
Get-ChildItem -Recurse -Filter "*.ps1" | Unblock-File
```

---

## Keeping up to date

```powershell
git pull
# Re-run the setup script after pulling to catch any new module requirements
.\Initialize-Environment.ps1
```
