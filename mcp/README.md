# sqldba MCP server

Your AI agent, given a SQL Server DBA's reference library.

Ask Claude Code (or any MCP client) *"my server is on 16.0.4165.4, is it patched?"* or *"I'm seeing
PAGEIOLATCH_SH, does it matter?"* and it looks the answer up here instead of recalling it. Every
answer comes back with a link to the full write-up.

**Why bother when the model already knows SQL Server?** Because build numbers, CU levels and support
end dates go stale within weeks, and a model that half-remembers a build number will tell you a
server is patched when it is three CUs behind. This data is checked by a working DBA against real
instances and carries the date it was checked.

## What it gives your agent

| Tool | Ask it | Returns |
|------|--------|---------|
| `lookup_error` | "what is error 18456?" / "login failed" | Message text, what it actually means, severity, link |
| `explain_wait` | "explain PAGEIOLATCH_SH" | Whether it is worth chasing or is normal noise, when to ignore it, what to do, link |
| `check_build` | "is 16.0.4165.4 current?" (or paste `@@VERSION`) | Version, patch level on its servicing train, support status, the KB to install |

Currently covering **47 errors**, **232 wait types** and **7 SQL Server versions**.

## Install

Needs Python 3.10 or newer.

```bash
pip install "sqldba-mcp @ git+https://github.com/peterwhyte-lgtm/dba-tools.git#subdirectory=mcp"
sqldba-mcp --selftest      # confirms the datasets loaded
```

Then register it with your MCP client. For **Claude Code**:

```bash
claude mcp add sqldba -- sqldba-mcp
```

For **Claude Desktop**, add this to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sqldba": { "command": "sqldba-mcp" }
  }
}
```

Restart the client, and the three tools appear.

## Running from a clone

```bash
git clone https://github.com/peterwhyte-lgtm/dba-tools.git
cd dba-tools/mcp
pip install -e .
python -m sqldba_mcp --selftest
```

## What it does not do

It **never touches your SQL Server.** It has no connection string, no driver, no network calls at
all — it answers from data bundled inside the package, so it works on an air-gapped jump box. To
actually query an instance, use the scripts in the parent repo; this server tells the agent which
one to reach for and what the output means.

It also will not fill gaps by guessing. Ask about an error that is not in the library and it says
so, rather than inventing a plausible answer. That is the point of a verified source.

## Where the data comes from

Generated from [sqldba.blog](https://sqldba.blog/) and the script library in this repo. Each record
is a **lookup entry plus a link** — the reasoning, the examples and the screenshots stay in the
articles. `src/sqldba_mcp/datasets/_meta.json` records when it was generated and what it contains.

Build and lifecycle data is the part that ages. `check_build` reports the date its data was checked;
if that is months old, verify against Microsoft before acting on it.

## Development

```bash
python -m unittest discover -s tests -v     # no test dependencies needed
pytest                                      # also works
```

The test suite covers the servicing-train logic (a wrong train silently misstates whether a server
is patched), the leak gate on shipped data, and the rule that every answer cites its source.

## Licence

MIT — same as the rest of the repo. See [../LICENSE](../LICENSE).
