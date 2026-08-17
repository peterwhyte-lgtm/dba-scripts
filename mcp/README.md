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
| `explain_wait` | "explain PAGEIOLATCH_SH" | Worth chasing or normal noise, when to ignore, what to do, link |
| `check_build` | "is 16.0.4165.4 current?" (or paste `@@VERSION`) | Version, patch level on its servicing train, support status, the KB to install |
| `find_script` | "find blocking chains", "check backup coverage" | Matching scripts with purpose, required permission, and **safety class** |
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
| Errors, searched by phrase | 47 | 100% | 100% |
| Errors, by number | 46 | 100% | 100% |
| Wait types, by name | 232 | 100% | 100% |

**Only the first row is a retrieval measure.** Searching with the verbatim question that is already
in the index scores 98.6% and means nothing — it is string equality wearing a costume. The headline
number asks each question in fewer words than published. Even that is an upper bound: the rewording
drops terms but cannot introduce synonyms, so treat 95.9% as the ceiling rather than a promise.

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

Found something wrong? Open an issue. Corrections from working DBAs are the point.

## Development

```bash
python -m unittest discover -s tests -v     # 55 tests, no test dependencies
python tests/eval_faq.py                    # retrieval scorecard
python tests/check_freshness.py             # dataset drift gate
pytest                                      # also works
```

The tests worth reading are the ones that are not happy paths: the servicing-train logic (a wrong
train silently misstates whether a server is patched), the index/corpus boundary in both directions,
the leak gate, and tool routing — a question answered by the wrong tool is a defect even when the
answer reads fine.

## Licence

MIT — same as the rest of the repo. See [../LICENSE](../LICENSE).
