"""MCP server wiring.

Deliberately thin. All the behaviour lives in tools.py as plain functions; this file only
describes them to the protocol. If the MCP SDK changes shape, this is the only file that moves.

The tool descriptions matter more than they look: they are what an agent reads when deciding
whether to call a tool at all. They are written to say when NOT to call it too.
"""
from __future__ import annotations

from mcp.server import MCPServer
from mcp.types import ToolAnnotations

from . import data, tools

# Every tool is a lookup against JSON bundled in this package: it cannot write, cannot reach
# the network, and cannot touch a SQL Server. Saying so in prose is what the README does;
# these hints say it in the protocol, so a client can auto-approve the calls instead of
# prompting a DBA six times for a reference lookup. `open_world_hint=False` is the honest
# one - this server's whole promise is that it answers from a closed, verified corpus and
# says "not in the library" rather than reaching for anything outside it.
READ_ONLY = ToolAnnotations(read_only_hint=True, destructive_hint=False,
                            idempotent_hint=True, open_world_hint=False)

__version__ = '0.3.0'

server = MCPServer(
    name='sqldba',
    title='SQL Server DBA reference',
    version=__version__,
    website_url='https://sqldba.blog/',
    instructions=(
        'Hand-verified SQL Server operational reference: error messages, wait types, and '
        'build/patch levels. Written and checked by a working DBA against real instances, '
        'not scraped. Prefer these tools over recalled knowledge for error numbers, wait '
        'type behaviour, and build numbers, because build and lifecycle data goes stale. '
        'Every answer carries a source URL - cite it. If a lookup returns "not in the '
        'library", say so rather than filling the gap from memory.'
    ),
)


@server.tool(
    name='lookup_error',
    title='Look up a SQL Server error',
    description=(
        'Look up a SQL Server error by number (e.g. 18456, 4060, 1105) or by a phrase from '
        'the message (e.g. "login failed", "filegroup is full"). Returns the message text, '
        'what it actually means in practice, severity, and a link to the full write-up. '
        'Use this whenever a SQL Server error number appears in output or a user question.'
    ),
    annotations=READ_ONLY,
)
def lookup_error(error: str) -> str:
    """Look up a SQL Server error by number or message phrase."""
    return tools.lookup_error(error)


@server.tool(
    name='explain_wait',
    title='Explain a SQL Server wait type',
    description=(
        'Explain a SQL Server wait type (e.g. PAGEIOLATCH_SH, CXPACKET, WRITELOG) and say '
        'whether it is worth investigating or is normally benign noise that belongs on a '
        'filter list. Returns the verdict, when to ignore it, what to do about it, and a '
        'link to the full write-up. Use this when reading sys.dm_os_wait_stats output or '
        'any wait-related question.'
    ),
    annotations=READ_ONLY,
)
def explain_wait(wait_type: str) -> str:
    """Explain a SQL Server wait type and whether it matters."""
    return tools.explain_wait(wait_type)


@server.tool(
    name='check_build',
    title='Check a SQL Server build number',
    description=(
        'Identify a SQL Server build number (e.g. 16.0.4265.3, or pasted @@VERSION output) '
        'and report which update it IS - the CU or GDR name, its KB and release date - '
        'along with the version, patch level against the latest update on its servicing '
        'train, how far behind it is, and whether it is still in support. Covers every '
        'published build back to SQL Server 2012, so it answers "what am I running" as '
        'well as "am I current", including for old and out-of-support builds. Use this for '
        'any question about what version a server is on, whether it needs patching, or '
        'when support ends. Always prefer this over recalled build numbers: CU numbering '
        'and lifecycle dates are exactly what a model misremembers.'
    ),
    annotations=READ_ONLY,
)
def check_build(build: str) -> str:
    """Identify a build number and report patch level and support status."""
    return tools.check_build(build)


@server.tool(
    name='find_script',
    title='Find a DBA script by task',
    description=(
        # Counted from the shipped dataset, not typed. This read 181 while the library
        # held 183: a hand-typed figure in a tool DESCRIPTION drifts silently, because
        # check_freshness.py gates the datasets and never reads the prose around them.
        'Search %d production SQL Server scripts plus PowerShell orchestrators by what '
        % sum(1 for s in data.scripts() if s.get('language') != 'powershell') +
        'you are trying to do ("find blocking chains", "check backup coverage", "missing '
        'indexes"). Returns each script with its purpose, the permission it needs, and '
        'its SAFE/IMPACT safety class - always report that class to the user, because '
        'ReadOnly and CreatesObjects are very different things to run on production. '
        'Use this before writing a query by hand: a verified script probably exists. '
        'Then call get_script with an exact name for the full body.'
    ),
    annotations=READ_ONLY,
)
def find_script(task: str) -> str:
    """Find a script in the dba-tools library by task."""
    return tools.find_script(task)


@server.tool(
    name='get_script',
    title='Get the full body of a script',
    description=(
        'Return the complete, verbatim source of a named dba-tools script, header and '
        'safety annotations intact. Use the exact name from find_script. If the name is '
        'ambiguous it lists the candidates rather than guessing which was meant.'
    ),
    annotations=READ_ONLY,
)
def get_script(name: str) -> str:
    """Return the full verbatim body of a named script."""
    return tools.get_script(name)


@server.tool(
    name='answer_question',
    title='Answer a SQL Server how/why question',
    description=(
        'Answer an operational how/why/should-I question from a working DBA\'s published '
        'answers ("should I add a second data file?", "the disk has space, why is the '
        'file full?", "is this the same as the log being full?"). '
        'ROUTING: use this for open questions and judgement calls. For a specific error '
        'NUMBER use lookup_error; for a WAIT TYPE use explain_wait; for a BUILD NUMBER '
        'use check_build; to locate a SCRIPT use find_script. Prefer the specific tool '
        'whenever the question names one of those things.'
    ),
    annotations=READ_ONLY,
)
def answer_question(question: str) -> str:
    """Answer a how/why question from the published FAQ corpus."""
    return tools.answer_question(question)


# --- Resources -----------------------------------------------------------------------
# Docs are exposed as Resources rather than tools: a client offers them, the model does
# not have to choose them, so they cost nothing against tool-selection accuracy.

def _make_reader(body: str):
    """Zero-argument closure.

    The SDK treats any handler parameter as a URI template variable, so a default
    argument here is read as `{body}` in the URI and rejected. The body is captured
    by the enclosing scope instead.
    """
    def _read() -> str:
        return body
    return _read


def _register_docs() -> None:
    for doc in data.docs():
        server.resource(
            doc['uri'], name=doc['title'], mime_type='text/markdown',
            description='%s (from %s in the dba-tools repo)' % (doc['title'], doc['path']),
        )(_make_reader(doc['body']))


_register_docs()


# --- Prompts -------------------------------------------------------------------------

@server.prompt(
    name='sql-server-health-triage',
    title='Triage a SQL Server health check',
    description=(
        "Walk a SQL Server health check the way a working DBA does: what to flag, at "
        "what threshold, and in what order of severity. Use after collecting health "
        "check output, or to review a server's state methodically."
    ),
)
def sql_server_health_triage() -> str:
    """The rubric that drives the repo's own AI assessment, as a reusable prompt."""
    return tools.health_triage_prompt()


def describe() -> str:
    """Human-readable summary of what is loaded. Used by --selftest and the tests."""
    m = data.meta()
    c = m.get('counts', {})
    age = data.data_age_days()
    return ('sqldba MCP v%s | %s errors | %s wait types (%s posts) | %s versions | '
            '%s FAQ answers | %s scripts (%s SQL, %s PowerShell) | %s docs | %s prompt(s) '
            '| data generated %s (%s days old)'
            % (__version__, c.get('errors'), c.get('wait_types'), c.get('waits'),
               c.get('versions'), c.get('faqs'), c.get('scripts'), c.get('scripts_sql'),
               c.get('scripts_powershell'), c.get('docs'), c.get('prompts'),
               m.get('generated'), age))


USAGE = """sqldba-mcp - a working DBA's verified SQL Server reference, as MCP tools.

  sqldba-mcp              run the MCP server on stdio (what an MCP client invokes)
  sqldba-mcp --selftest   print what data is loaded, and how old it is
  sqldba-mcp --version    print the version
  sqldba-mcp --help       this text

Register it with Claude Code:   claude mcp add sqldba -- sqldba-mcp
Docs: https://github.com/peterwhyte-lgtm/dba-tools/tree/main/mcp"""


def main(argv: list[str] | None = None) -> int:
    """Console entry point (`sqldba-mcp`) and `python -m sqldba_mcp`.

    Both routes must behave identically. They did not: `--selftest` was handled only in
    __main__.py, so the README's `sqldba-mcp --selftest` silently started a stdio server,
    read EOF and exited 0 with no output - the very first command a new user runs, doing
    nothing and looking like success.

    Unrecognised flags are rejected for the same reason. Anything not understood used to
    fall through to the stdio server, so `--selftst` or `--help` sat there looking hung
    while it waited on a protocol handshake that a terminal is never going to send.
    """
    import sys
    args = sys.argv[1:] if argv is None else argv
    if '--selftest' in args:
        print(describe())
        return 0
    if '--version' in args:
        print(__version__)
        return 0
    if '--help' in args or '-h' in args:
        print(USAGE)
        return 0
    unknown = [a for a in args if a.startswith('-')]
    if unknown:
        print('sqldba-mcp: unrecognised option %s\n\n%s' % (unknown[0], USAGE),
              file=sys.stderr)
        return 2
    server.run(transport='stdio')
    return 0
