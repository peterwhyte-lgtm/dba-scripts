# Traces (Extended Events)

Six scripts for the "something specific happened and I need evidence" problem: stand up a targeted
Extended Events session, check what is already running, read the captured events, and clean up.

**This is the only folder in `sql/` where a script changes your server.** The three `Create-*` scripts
are marked `SAFE:CreatesObjects` — running one creates a live XE session on the instance. Everything
else here reads.

## The scripts

| Script | Safe | What it does |
|--------|------|--------------|
| `Create-LoginActivitySession` | CreatesObjects | Captures every successful and failed login — who, from where, and with which application |
| `Create-DecommissionAuditSession` | CreatesObjects | Captures activity against a server you are about to retire, so "nothing uses this any more" is evidence rather than a hope |
| `Create-SpExecutionSession` | CreatesObjects | Captures stored procedure execution, for finding what actually calls a procedure |
| `Get-ActiveXeSessions` | ReadOnly | Currently running sessions with target, output file, buffer size, dropped-event counts, and whether they restart with the instance |
| `Get-XeSessionActivity` | ReadOnly | Reads the captured events back out of the `.xel` files |
| `Remove-XeSession` | ReadOnly | Lists the DBA-created sessions and generates the stop-and-drop DDL for each |

## Before you run a `Create-*` script

Each one has a configuration block at the top. Read it — the defaults will not match your server.

| Setting | Default | Notes |
|---------|---------|-------|
| `@SessionName` | `LoginActivity` / `DecommissionAudit` / `SpExecution` | The session name on the instance |
| `@TraceFolder` | `D:\SQLTrace` | **Must already exist.** The SQL Server service account needs write access to it |
| `@MaxFileMB` | 100 | Size cap per `.xel` file |
| `@MaxFiles` | 6, 14, or 7 depending on the script | Rollover count. Oldest file is overwritten first, so this plus `@MaxFileMB` is your real disk ceiling |
| `@RetentionDays` | 3 or 7 | SQL Server 2025 (v17) and later only — the session auto-stops after this many days. **On older versions it has no effect** and the session runs until you stop it |

Permissions: `ALTER ANY EVENT SESSION` and `VIEW SERVER STATE`.

The `@TraceFolder` default of `D:\SQLTrace` is the one that catches people out. The folder is not
created for you; if it does not exist or the service account cannot write to it, the session is created
but captures nothing.

**Re-running a `Create-*` script is safe and idempotent.** If a session with that name already exists,
the script stops and drops it first, then recreates it. You will lose whatever that session had
buffered, so read it with `Get-XeSessionActivity` before you re-run.

## The lifecycle

```text
Create-*Session.sql     →  session running, writing .xel files to @TraceFolder
Get-ActiveXeSessions    →  confirm it started, see what else is running and what it costs
Get-XeSessionActivity   →  read the events back
Remove-XeSession        →  generates the DDL to stop and drop it — you run that DDL
```

`Remove-XeSession` deliberately does not drop anything itself. It hands you a `remove_cmd` column per
session and you run the ones you want. Unlike `Get-ActiveXeSessions` it lists stopped sessions as well
as running ones, so it is the one to use when cleaning up. Both scripts exclude the built-in sessions
(`system_health`, `AlwaysOn_health`, `telemetry_xevents`, and friends) so you cannot accidentally drop
those.

**The `.xel` files on disk are never deleted by any of these scripts.** Once you have dropped a
session, its files stay in `@TraceFolder` until you remove them. Read them first, then clean up.

## Leaving one running

All three `Create-*` scripts set `STARTUP_STATE = ON`, so the session comes back after a SQL Server
restart and keeps consuming disk until someone stops it. `Get-ActiveXeSessions` reports
`auto_start_on_restart` alongside `dropped_event_count` for exactly this reason — worth running on any
instance you have inherited, not just ones you set up yourself.
