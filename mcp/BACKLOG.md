# sqldba MCP — backlog

Observations that have not been fixed yet. `CHANGELOG.md` records what shipped; this file
records what was noticed. An entry earns its place by having been *seen* against a real
instance or a real question, not by being a good idea in the abstract. When one ships, it
moves to the changelog and comes out of here.

Each entry: what was observed, why it matters, what the fix looks like.

> **⚠️ Every entry below was observed against 0.2.0** (the pip-installed build, pinned to
> commit `968dbeb`), discovered 2026-08-19 to be seven commits behind local. The first two
> may already be fixed by `8a2ca43` (0.2.1, patch-level correctness) and `118fec3` (0.2.2,
> classify every script). **Re-verify against a current install before acting on them.**

---

## Open

### ~~`check_build` hedges on a train it can already identify~~ — WITHDRAWN

**Withdrawn 2026-08-19.** Raised against 0.2.0 and wrong. The 0.2.1 entry in `CHANGELOG.md`
makes the naming deliberate: identifying the train and judging currency were split into
separate questions, and the train is *"still named and still assumed out loud"* on purpose,
because preferring the CU train within a series is exactly what produced false `UP TO DATE`
verdicts on post-final-CU versions. The hedge is the fix, not a weakness. Original text kept
below as a record of how a stale install misleads a reviewer.

### `check_build` hedges on a train it can already identify

**Observed 2026-08-19**, asking "is my server patched?" against the local SQL 2025 instance
(build `17.0.4075.5`).

The answer was right and the lifecycle dates were right, but it carried this line:

> **Servicing train assumed:** CU - check this is the train you are on.

GDR and CU builds carry distinct build numbers. If the build table is complete for a given
major version, the number identifies the train on its own and there is nothing for the
reader to check. Handing the verification back to the user weakens an otherwise sharp
answer, and it is the flagship question.

**Fix:** where the build resolves to exactly one train, state it rather than assuming it.
Keep the hedge only for genuinely ambiguous input, for example a partial build or a major
version whose table has gaps, and say which of those two applies.

### The flagship question needs an input the reader does not have

**Observed 2026-08-19.**

"Is my server patched?" only completed because the agent went and found the build itself,
via `HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\<instance>\Setup\PatchLevel`. A reader
following the README has no build number in front of them and nothing tells them where to
get one. The gap between the question the README advertises and the input `check_build`
requires is undocumented.

Also worth stating wherever that lands: the registry value is the *installed* patch level.
If the service has not been restarted since patching, the running build can lag it, and
`SELECT @@VERSION` is the authoritative answer.

**Fix:** a short "getting your build number" section in `mcp/README.md` covering both
sources and the restart caveat. Consider whether a one-line PowerShell snippet belongs
there too, given the toolkit already has wrappers for this.

### A declined permission prompt is indistinguishable from a broken server

**Observed 2026-08-19.** Not a defect in this server, but it is this server's demo that
breaks, so it belongs in these docs.

When the host declines the permission prompt for an MCP tool call, the call returns nothing
and the agent answers from whatever else it can reach. There is no error surfaced to the
user. From the outside this looks exactly like the server not being wired up, and the first
instinct is to go and re-check the install, which is fine.

**Fix:** a troubleshooting line in `mcp/README.md`. If answers are arriving without a
sqldba.blog link on the end, check `claude mcp list` for connection state first, then check
whether the tool prompt was approved. Pre-approving the `mcp__sqldba__*` tools avoids it
entirely and is worth doing before any demo.

---

### ~~A stale install is invisible at runtime~~ — CLOSED in 0.3.1 (2026-08-21)

Every answer now ends with `_sqldba-mcp <version> - datasets generated <date>_`, refusals
included, so the running install names itself on the one surface a user always sees.
Asserted at the function layer and over the wire. The README reinstall documentation
(`--no-cache-dir` / explicit `@<commit>`) is still worth doing. Original entry kept below.

**Observed 2026-08-19**, and the reason the three entries above are all suspect.

`pip install "sqldba-mcp @ git+...#subdirectory=mcp"` resolves to a commit and pins there.
The installed build was 0.2.0 at commit `968dbeb` while local was 0.2.2 plus seven commits.
Nothing surfaces this. `claude mcp list` reports `✔ Connected` either way, the tools answer
normally, and the answers are simply built from older data. It was only caught because
`find_script` returned *"safety class not stated"* for `MultiServer-GetDatabaseSizes` while
the file on disk plainly carries `Safe : Read-only`, and the installed dataset had `None`
where the working tree had `SAFE` / `Low`.

The failure mode is worse than a crash. A stale build answers confidently with retired data,
which is precisely the thing this server exists to prevent for SQL Server builds.

**Fix:** surface the version and dataset date in *tool output*. `--selftest` already reports
both (`sqldba MCP v0.2.2 | ... | data generated 2026-08-18 (1 days old)`), which is exactly
why this went unnoticed: the one place the staleness was visible is a command you run once
at install time and never again. The agent calling `find_script` forty times never sees it.
`data.freshness_warning()` already exists, so the mechanism is there. Also document the
reinstall properly in the README: pip caches
the git clone, so `--force-reinstall` on its own can still land on a stale commit, and
`--no-cache-dir` or an explicit `@<commit>` is what makes it deterministic.

---

### check_build's version-only answer is a secret

**Observed 2026-08-21**, first layer-2 tool-selection run (13 human questions, isolated
gagged session, model sonnet, 11/13 first-call accuracy).

Asked *"can you give me a link for downloading the latest 2025 cu"*, the agent called no
tool and said the library "doesn't serve download URLs" — while `check_build` given just a
product name returns the latest CU **with its KB download link** (`_fmt_version_only`,
`Download:` line). The capability exists and the description never mentions it: it talks
entirely in build numbers. **Possible fix:** one sentence in the description saying a
product name alone ("SQL Server 2025") returns the latest CU, its KB and the KB link.
**Held for Peter:** it is a description change judged against a probe that found it, and
tuning descriptions to the probe set is the eval-gaming this repo's own docs warn about.

---

### find_script loses to the model's own T-SQL on security asks

**Observed 2026-08-21**, same layer-2 run.

*"show me who has sysadmin"* got hand-written `IS_SRVROLEMEMBER` T-SQL from model memory,
no tool call — the exact failure the server exists to prevent, against a library that
ships `Get-SysadminMembers`. The agent even offered to "wrap it as one of your sqldba
library snippets", so it knew the library existed and still did not search it. The
description's examples ("find blocking chains", "check backup coverage", "missing
indexes") are all performance/maintenance-flavoured; security asks may simply not
pattern-match. **Held for Peter** for the same tuning-judgment reason as above.

---

### ~~explain_wait silently truncates the "What to do" section mid-sentence~~ — CLOSED same day (2026-08-21)

**Observed 2026-08-21** against 0.3.1, asking about PAGEIOLATCH_SH: "What to do" cut off
mid-parenthetical at *"...Windows Performance Monitor (..."*, with nothing marking it as
an elision.

**Root cause, verified — the original entry's presumption was backwards.** The formatter
was innocent: `tools.py` renders `what_to_do` verbatim. The *dataset* was truncated at
export: the exporter passed the section through `first_sentence(limit=240)`, and the
sections that matter most are bulleted lists with no early full stop, so it word-trimmed
at 240 chars and appended `...` right after the open parenthesis of
`(PhysicalDisk\Current Disk Queue Length)`. Exactly **6 records** were affected —
ASYNC_NETWORK_IO, BACKUPIO, CXPACKET, HADR_SYNC_COMMIT, PAGEIOLATCH_SH, WRITELOG — the
six most-asked waits, because they carry the longest step lists.

**Fix shipped:** Peter ruled the full step list crosses the index-not-corpus boundary for
this one field. The exporter now ships `what_to_do` whole (capped at ~1500 with an explicit
`[trimmed for size - the full steps are in the write-up linked below]` marker — today only
BACKUPIO at 1502 chars trips it), the boundary test documents the exception at 1600, and
the datasets are re-exported. PAGEIOLATCH_SH now ships all 883 chars of its steps.

---

## Noted, not yet an entry

- The MCP has no section in `docs/roadmap.md` at all, despite shipping at 0.2.2. The roadmap
  still describes the repo as of 2026-06-21 and predates the server.
- 37 records in `scripts.json` carry a `safe` value with no `impact`. Not investigated.
- `safe` values across the library are inconsistent in kind: `ReadOnly` (177), `SAFE` (41),
  `HIGH IMPACT` (6), `CreatesObjects` (4), `WritesData` (2), `MEDIUM` (2). Some name a class,
  some name an impact level. Worth deciding whether that is intentional.
