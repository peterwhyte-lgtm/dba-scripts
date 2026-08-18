# sqldba MCP server

A working DBA's verified SQL Server reference, given to your AI agent as tools it can call.

Ask Claude Code (or any MCP client) *"my server is on 16.0.4165.4, is it patched?"*, *"I'm seeing
PAGEIOLATCH_SH, does it matter?"*, or *"find me a script for blocking chains"* — and it looks the
answer up here instead of recalling it. Every answer comes back with a link to the full write-up.

**Why bother when the model already knows SQL Server?** Because build numbers, CU levels and support
end dates go stale within weeks, and a model that half-remembers a build will tell you a server is
patched when it is three CUs behind. This data is checked by a DBA against real instances and carries
the date it was checked — and says so when that date gets old.

## The six tools

| Tool | Ask it | Returns |
|------|--------|---------|
| `lookup_error` | "what is error 18456?" / "login failed" | Message text, what it actually means, severity, link |
| `explain_wait` | "explain PAGEIOLATCH_SH", or paste a whole `sys.dm_os_wait_stats` result | One wait explained, or a triaged result set: worth chasing first, noise you can filter, and what is not covered |
| `check_build` | "is 16.0.4165.4 current?" (or paste `@@VERSION`) | Version, patch level on its servicing train, support status, the KB to install |
| `find_script` | "find blocking chains", "check backup coverage" | Matching scripts with purpose, required permission, and **safety class** — anything not read-only leads with a warning |
| `get_script` | "get Get-BlockingChains" | The complete verbatim script, header and safety annotations intact |
| `answer_question` | "should I add a second data file?" | The published answer to that question, plus the post it came from |

Six is a ceiling, not a target. Past roughly half a dozen, an agent starts picking the wrong tool,
and a wrong pick is worse than no server at all — so anything else this could expose is a Resource
or a Prompt instead. A test enforces the cap.

Covering **47 errors**, **232 wait types**, **7 SQL Server versions**, **230 scripts** (181 SQL,
49 PowerShell) and **434 answered questions**.

### Also included

**Resources** — the repo's docs at stable URIs (`sqldba://docs/standards`, `quick-start`,
`ai-assessment`, `ai-playbook`, `script-catalog`, `repo-structure`, `dba-quickref`, and more). A
client offers these; the model does not have to choose them, so they cost nothing against tool
selection.

**Prompt: `sql-server-health-triage`** — the assessment rubric that drives this repo's own AI health
check, as a prompt any client can run. It is a working DBA's actual methodology: what to flag, at
what threshold, in what order of severity. This is the part that carries *judgement* rather than
facts.

## Measured retrieval accuracy

Very few MCP servers publish a number for this. Run it yourself: `python tests/eval_faq.py`.

| Suite | n | top-1 | top-3 |
|---|---:|---:|---:|
| **FAQ, questions reworded** | 434 | **95.9%** | **99.5%** |
| FAQ, verbatim question | 434 | 98.6% | 99.8% |
| **Errors, phrase reworded** | 47 | **95.7%** | **100%** |
| Errors, by number | 46 | 100% | 100% |
| Wait types, by name | 232 | 100% | 100% |

**Only the bold rows are retrieval measures.** Searching with the verbatim question that is already
in the index scores 98.6% and means nothing — it is string equality wearing a costume. The headline
number asks each question in fewer words than published. Even that is an upper bound: the rewording
drops terms but cannot introduce synonyms, so treat 95.9% as the ceiling rather than a promise.

The error row used to read **100%**, and that number was wrong in exactly the way this section
warns about. It searched with each error's *verbatim title* against a substring match, so every
record contained its own query by construction, and it counted an answer as correct if the error
number appeared anywhere in it — including buried in a list of eight candidates. Scored the same
way as the headline row, the search behind it was really getting **29.8%**: a DBA who typed
`incorrect syntax` instead of `Incorrect syntax near` got *"not in the library yet"*. Fixed in
0.2.1 by putting error search through the same ranked index as everything else. **A test suite
that cannot fail is worse than no test suite, because it is quoted.**

The misses are written to `output-files/eval-misses-*.txt`. Each one is either a retrieval bug or a
genuine gap in the published content, which makes the list a content roadmap as well as a test.

## Install

Needs Python 3.10 or newer.

```bash
pip install "sqldba-mcp @ git+https://github.com/peterwhyte-lgtm/dba-tools.git#subdirectory=mcp"
sqldba-mcp --selftest      # confirms the datasets loaded
```

Then register it. For **Claude Code**:

```bash
claude mcp add sqldba -- sqldba-mcp
```

For **Claude Desktop**, in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sqldba": { "command": "sqldba-mcp" }
  }
}
```

Restart the client and the tools appear. *(Alpha: install from git. It goes to PyPI once the
accuracy figure has settled.)*

## What it does not do

It **never touches your SQL Server.** No connection string, no driver, no network calls at all — it
answers from data bundled inside the package, so it works on an air-gapped jump box, which is where
a DBA often is when they need it. To actually query an instance, use the scripts in the parent repo;
this server tells the agent which one to reach for, what permission it needs, and what its output
means.

There is deliberately **no `run_script` tool**. Having no database connection is a property worth
more than the convenience it costs.

All six tools declare themselves **read-only, non-destructive and closed-world** in their MCP
annotations, so a client can auto-approve them instead of asking you to confirm a reference lookup
six times. That is the same promise as the paragraph above, in the form a client can actually read.

The scripts it hands you are a different matter, and it says so. **14 of the 230 change something**
— they write data, create objects, install, patch or restart — and every one of those leads its
answer with a warning naming the class, the impact and the reason, before the body. The other 216
are read-only and stay uncluttered, because a warning on everything is a warning on nothing. A test
asserts that no script can ship without resolving to read-only *true or false*: "not stated" is not
an available answer.

It also **will not guess**. Ask about an error that is not in the library and it says so. Ask
something off-topic and it declines rather than returning the least-bad row — a question about an
nginx reverse proxy used to match a SQL Agent *proxy* answer, so queries now have to share enough
vocabulary with a record before it counts as a hit.

## What ships, and what stays on the blog

The boundary is deliberately asymmetric:

- **Scripts ship in full.** The body *is* the product, and this repo is already MIT and public, so
  withholding it would be theatre. It also makes the server useful offline.
- **Posts ship as an index.** Errors, wait types and FAQ answers ship as the entry plus a link. The
  reasoning, the examples and the screenshots stay in the articles on
  [sqldba.blog](https://sqldba.blog/).

Tests assert both directions, so a later refactor cannot quietly flip either one.

## The 38 scripts with no link

`find_script` returns a write-up URL for 143 of the 181 SQL scripts. The other 38 come back
with no link — and that is a **header** problem, not missing content. Checked against the live
site: most of those 38 already have a published write-up. Their `Author :` line just reads
`https://sqldba.blog` instead of naming the post, so nothing can map the script to it.

That is why script headers are treated as a product surface here rather than housekeeping.
`Author`, `Purpose`, `Requires`, `SAFE:` and `IMPACT:` are what your assistant shows you
*before* you run something. The list is in [`scripts-missing-post-url.txt`](scripts-missing-post-url.txt).

## The 22 errors with no link

The same gap on the other surface, and worth stating plainly because the tools promise a source
link with every answer: **25 of the 47 errors carry a write-up URL, and 22 do not.** Those 22 still
return the message text, what it means and the severity — all hand-written and verified — and the
answer now *says* no article exists rather than quietly omitting the link, so an agent can quote
them and knows it cannot cite them.

Unlike the scripts above this is a genuine **content** gap, not a header one: those errors have no
post yet. `102 Incorrect syntax near`, `208 Invalid object name`, `701 Insufficient system memory`
and `823 I/O error` are on that list, which makes it a fair reading order for the Error Library.

## Corrections — one source, three surfaces

`src/sqldba_mcp/datasets/*.json` are **generated**. Never hand-edit them: the change is lost at the
next export and, worse, silently disagrees with the post it cites. Corrections go to the source:

| Wrong thing | Fix it here |
|---|---|
| An error's meaning | the post on sqldba.blog |
| A wait type's verdict | the wait post |
| A script's purpose or safety class | the `.sql` header in this repo |
| A build, CU or support date | the builds data behind the lifecycle page |

Then re-export. There is one source of truth and three ways to reach it — the blog is where a
human reads it, this repo is where a DBA runs it, and the MCP server is where an AI agent calls
it. A correction made at the source improves all three at once; a correction typed into a dataset
improves nothing and is gone at the next export.

CI enforces this. `tests/check_freshness.py` re-derives the script, doc and prompt datasets from the
files in this repo and compares them byte for byte — a hand-edit or a stale export fails the build
and names the file.

**One practical note: the server reads its datasets once, at start-up.** After a re-export, a client
that already has the server running keeps answering from the data it loaded, so a correction can be
in the repo and still not be in the answer. Restart the MCP client (or the server process) to pick
it up. This is easy to miss precisely because the fix *looks* applied everywhere you check.

Found something wrong? Open an issue. Corrections from working DBAs are the point.

## Development

```bash
python -m unittest discover -s tests -v     # 116 tests, no test dependencies
python tests/eval_faq.py                    # retrieval scorecard
python tests/check_freshness.py             # dataset drift gate
pytest                                      # also works
```

The tests worth reading are the ones that are not happy paths:

- **`test_red_team.py`** — the refuse-rather-than-guess promise, in both directions. A refusal
  battery alone is passed by a server that refuses everything, so the positive case is asserted
  on the same shipped path.
- **`test_protocol.py`** — a real subprocess, a real stdio handshake. The only test that would
  notice the server failing to start at all.
- **the patch-level logic** — a server that is current on its train can still be behind on its
  series, and saying otherwise is the one answer this whole thing exists to prevent.
- the index/corpus boundary in both directions, and the leak gate.

## Licence

MIT — same as the rest of the repo. See [../LICENSE](../LICENSE).
