# Multi-server scripts

Thirteen scripts for running one check across a list of servers instead of one at a time. Every script
in this folder is **self-contained** — copy it out on its own and it still runs. No repo dependency at
runtime.

All of them take `-Servers` (comma-separated) and a `-Parallel` switch.

## SQL scripts

Connect to each SQL Server over port 1433 via `Invoke-Sqlcmd`. Queries run from your machine — no
remoting to the SQL Server host needed.

| Script | What it does |
|--------|--------------|
| `MultiServer-GetWaitStats.ps1` | Top wait types per instance, background noise filtered out |
| `MultiServer-GetBlockingSessions.ps1` | Active blocking sessions across instances |
| `MultiServer-GetBackupStatus.ps1` | Backup coverage — last full, diff, and log per database |
| `MultiServer-GetDatabaseSizes.ps1` | Data and log file sizes per database per instance |
| `MultiServer-GetPatchLevel.ps1` | Version, edition, and CU level per instance — patch compliance across the estate |
| `MultiServer-GetMaintenanceJobStatus.ps1` | Maintenance job outcomes across instances |
| `MultiServer-Compare-Configuration.ps1` | `sp_configure` drift detection — finds settings where any server differs from the majority |

**Prerequisite:**

```powershell
Install-Module -Name SqlServer -Scope CurrentUser -Force
```

The scripts check for this at startup and tell you how to install it if it is missing.

## Windows scripts

Connect to remote hosts rather than to SQL Server. No SQL Server needed.

| Script | What it does | Remoting |
|--------|--------------|----------|
| `MultiServer-TestSqlPort.ps1` | Test TCP 1433 reachability — no auth needed at all | None (raw TCP) |
| `MultiServer-GetDiskSpace.ps1` | Disk free and used per volume across hosts | WinRM |
| `MultiServer-GetFirewallRules.ps1` | List local Windows Firewall rules | WinRM |
| `MultiServer-RestartService.ps1` | Restart a named Windows service on multiple hosts | WinRM |
| `MultiServer-GetServiceStatus.ps1` | Service running/stopped state across hosts | RPC (no WinRM) |
| `MultiServer-GetRecentEventLogs.ps1` | Recent Error and Warning events from the event logs | RPC (no WinRM) |

**WinRM prerequisite**, for the four scripts that need it:

```powershell
# Run as admin on each TARGET server:
Enable-PSRemoting -Force
```

`MultiServer-TestSqlPort.ps1` is the one to reach for first on an unfamiliar estate — it needs no
credentials and no remoting, so it tells you which servers are even reachable before you debug auth.

## Parameters

| Parameter | Available on | Description |
|-----------|--------------|-------------|
| `-Servers "SVR01,SVR02,SVR03"` | all | Comma-separated server names or IPs |
| `-Parallel` | all | Run against every server at once (PowerShell 7+). Sequential is the default |
| `-Credential` | GetDiskSpace, GetFirewallRules, GetRecentEventLogs, RestartService | Alternate Windows credentials. **Not** on GetServiceStatus (RPC is pass-through auth only) or TestSqlPort |
| `-SqlAuth` | SQL scripts | Prompt for SQL credentials instead of using Windows auth |
| `-Database` | GetWaitStats, GetBlockingSessions, GetBackupStatus, GetDatabaseSizes | Connection database, default `master` |
| `-ServiceName` | GetServiceStatus, RestartService | Which Windows service to act on |
| `-Hours` | GetRecentEventLogs | How far back to look |

## Examples

Run these from the repo root:

```powershell
# Which of my SQL servers are even reachable?
.\powershell\reporting\multi-server\MultiServer-TestSqlPort.ps1 -Servers "SVR01,SVR02,SVR03"

# Is anything blocked right now?
.\powershell\reporting\multi-server\MultiServer-GetBlockingSessions.ps1 -Servers "SVR01,SVR02,SVR03"

# Disk space across the estate
.\powershell\reporting\multi-server\MultiServer-GetDiskSpace.ps1 -Servers "SVR01,SVR02" -Parallel

# Are they all on the same patch level?
.\powershell\reporting\multi-server\MultiServer-GetPatchLevel.ps1 -Servers "SVR01,SVR02,SVR03"

# Restart SQL Agent on three servers
.\powershell\reporting\multi-server\MultiServer-RestartService.ps1 -Servers "SVR01,SVR02,SVR03" -ServiceName SQLSERVERAGENT
```

## Related

- **Estate-wide health check:** `powershell/reporting/Invoke-MultiServerHealthCheck.ps1` runs the full
  collection per server and aggregates the findings, rather than one check at a time.
- **Generate your own:** `.\tools\scaffolding\New-MultiServerScript.ps1` turns any repo script into a
  self-contained multi-server wrapper. See
  [`tools/scaffolding/README-multi-server.md`](../../../tools/scaffolding/README-multi-server.md).
