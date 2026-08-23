# Contributing

This is Peter Whyte's production SQL Server toolkit — built by a working DBA, for working DBAs. The goal is a single repo that covers every diagnostic, monitoring, performance, security, and migration script a production DBA actually needs. The brain. The efficiency layer. The thing you reach for first.

It's open source because that's the right model for shared professional tooling. You're welcome to use it, fork it, and contribute to it. Peter is the lead — he decides direction, scope, and standards. That's not gatekeeping, it's just how a focused, opinionated toolkit stays useful.

---

## What belongs here

Scripts that a production DBA would actually run during an incident, a health check, a migration, or a routine review. If it answers a real operational question against a real SQL Server instance, it belongs here.

What doesn't belong:

- Scripts that require elevated permissions beyond `VIEW SERVER STATE` / `VIEW ANY DATABASE` without a strong reason
- Scripts that modify data or schema (unless clearly labelled, categorised separately, and safe to run twice)
- Vendor-specific tooling or non-SQL-Server scripts
- Abstract frameworks or wrappers around wrappers

---

## Reporting issues

Open a GitHub issue with:

- SQL Server version and edition
- The script name and the exact error or unexpected output
- What you expected vs what you got

For security issues, see [SECURITY.md](SECURITY.md).

---

## Pull requests

Small, focused PRs. One script, one fix, one idea per PR. Before opening one:

- Run the script against a real SQL Server instance (2016+ minimum)
- Confirm it is read-only if it claims to be
- Check it returns a single result set — multi-result-set scripts can't be exported as CSV via the runner

### SQL script standards

Every SQL script must have this header:

```sql
/*
Script Name : Get-ExampleScript
Category    : performance
Purpose     : One-line description of what this returns.
Author      : Peter Whyte (https://sqldba.blog)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;
```

`-- SAFE:` values: `ReadOnly` / `WritesData` / `CreatesObjects`
`-- IMPACT:` values: `Low` / `Medium` / `High`

Additional rules:

- No `USE database; GO` — pass `-Database` at execution time instead
- No `WITH (NOLOCK)` without a comment explaining the trade-off
- Modern DMVs only — `sys.objects` not `sys.sysobjects`, `sys.server_principals` not `sys.syslogins`
- `OUTER APPLY` not `CROSS APPLY` when the applied function may return no rows
- Single result set per script
- No trailing blank lines

### PowerShell script standards

SQL logic stays in `.sql` files. Wrappers delegate to `tools\local-sql\Invoke-RepoSql.ps1` — they don't re-implement execution.

```powershell
# Standard thin wrapper — lives at powershell/wrappers/<category>/<subfolder>/
$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')  # 4 levels if subfoldered, 3 if at category root
$sqlScript = Join-Path $repoRoot 'sql\<category>\<subfolder>\Get-Something.sql'
$runner    = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'
& $runner -ScriptPath $sqlScript -ServerInstance $ServerInstance -Database $Database -OutputFormat $OutputFormat -OutputPath $OutputPath
```

Required `.NOTES` fields:

| Field | Values |
|-------|--------|
| `ScriptType` | `runner` / `automation` / `hybrid` |
| `TargetScope` | `single server` / `multi-server` |
| `RiskLevel` | `SAFE` / `MEDIUM` / `HIGH IMPACT` |

### Where new scripts go

| Type | Location |
|------|----------|
| SQL diagnostic or monitoring script | `sql/<category>/<subfolder>/Get-Something.sql` |
| PowerShell wrapper for a SQL script | `powershell/wrappers/<category>/<subfolder>/Get-Something.ps1` — required for web UI |
| PowerShell orchestration script | `powershell/<subfolder>/` |
| Change order template | `docs/ops/change-orders/` |
| Operational checklist | `docs/ops/checklists/` |

The wrapper must mirror the SQL path exactly. The web UI discovers scripts through wrappers, not SQL files directly. If a new top-level category is needed, open an issue first.

### The MCP datasets are generated — never edit them by hand

`mcp/src/sqldba_mcp/datasets/*.json` are exported from this repo and from the published
write-ups. A correction typed into a dataset is lost on the next export, and CI
(`mcp/tests/check_freshness.py`) compares the datasets byte for byte against their sources, so
a hand-edit fails the build and names the file. Fix the source instead: a script's purpose or
safety class belongs in its `.sql` header; a wrong error or wait explanation is a content
correction — open an issue and it gets fixed at the source. See [mcp/README.md](mcp/README.md).

---

## Running tests before submitting

```powershell
$cfg = New-PesterConfiguration
$cfg.Run.Path = 'tests'
$cfg.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $cfg
```

All tests must pass. The suite checks SQL header standards, SQL path resolution, and wrapper parity.
