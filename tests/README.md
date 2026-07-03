# Tests

Pester v5 tests. Run from the repo root:

```powershell
Invoke-Pester tests/
```

No SQL Server connection required — all tests work offline.

---

## SqlHeaderStandards.Tests.ps1

**What it does:** Checks that every `.sql` script in `sql/` meets the header standard defined in CLAUDE.md. Catches scripts added without the required block comment fields or missing safety annotations.

Excluded from the check (different format or lower standard):
- `sql/lab/` — dev/test scripts
- `sql/collectors/` — SQL Agent job DDL generators

| Test | Purpose |
|------|---------|
| found SQL scripts to check | Sanity check — confirms the scanner found SQL files |
| `<path>` has all required header fields | Confirms the script block comment contains `Script Name`, `Category`, `Purpose`, `Author`, and `Requires` |
| `<path>` has valid `-- SAFE:` and `-- IMPACT:` annotations | Confirms both inline safety annotations are present with a recognised value (`ReadOnly`/`WritesData`/`CreatesObjects` and `Low`/`Medium`/`High`) |

---

## SqlPathResolution.Tests.ps1

**What it does:** Scans every `.ps1` file under `powershell/` for hardcoded `sql\...\*.sql` path references and confirms that each referenced file actually exists on disk.

This catches the most common breakage: a wrapper still points to a SQL file that was renamed, moved to a different category folder, or never created.

| Test | Purpose |
|------|---------|
| found at least one wrapper with a SQL reference | Sanity check — confirms the scanner found SQL references at all (guards against the scanner itself being broken) |
| wrapper `<file>` references existing SQL file `<path>` | One test per unique SQL reference found — confirms the file exists at the expected path |

---

## WrapperParity.Tests.ps1

**What it does:** Checks that every `.sql` script in `sql/` has a matching PowerShell wrapper in `powershell/wrappers/`. The wrapper is what makes a SQL script appear in the web UI and runnable via `run.ps1`.

Excluded from the check (intentionally wrapper-free):
- `sql/lab/` — dev/test scripts, not exposed in the web UI
- `sql/collectors/` — SQL Agent job DDL; deployed directly, no wrapper needed
- `sql/migration/Generate-*.sql` — served by orchestrators in `powershell/migration/`, not thin wrappers
- `Get-ActiveRequests`, `Get-ActiveRequestsWithPlan`, `Get-BlockingChains`, `Get-BlockingChainsWithPlan` — served by dedicated diagnostics scripts (powershell/diagnostics/)

| Test | Purpose |
|------|---------|
| found SQL scripts to check | Sanity check — confirms the scanner found SQL files |
| `<path>` has a matching wrapper in powershell/wrappers/ | One test per SQL file — confirms a `.ps1` wrapper with the same base name exists somewhere under `powershell/wrappers/` |
