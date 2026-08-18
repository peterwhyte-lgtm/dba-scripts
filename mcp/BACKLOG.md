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

### A stale install is invisible at runtime

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

**Fix:** surface the version and dataset date in tool output, or at minimum in `--selftest`.
`_meta.json` already carries a dataset date and `data.freshness_warning()` already exists,
so the mechanism is there. Also document the reinstall properly in the README: pip caches
the git clone, so `--force-reinstall` on its own can still land on a stale commit, and
`--no-cache-dir` or an explicit `@<commit>` is what makes it deterministic.

---

## Noted, not yet an entry

- The MCP has no section in `docs/roadmap.md` at all, despite shipping at 0.2.2. The roadmap
  still describes the repo as of 2026-06-21 and predates the server.
- 37 records in `scripts.json` carry a `safe` value with no `impact`. Not investigated.
- `safe` values across the library are inconsistent in kind: `ReadOnly` (177), `SAFE` (41),
  `HIGH IMPACT` (6), `CreatesObjects` (4), `WritesData` (2), `MEDIUM` (2). Some name a class,
  some name an impact level. Worth deciding whether that is intentional.
