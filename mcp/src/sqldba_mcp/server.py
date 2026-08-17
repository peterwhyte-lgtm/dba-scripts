"""MCP server wiring.

Deliberately thin. All the behaviour lives in tools.py as plain functions; this file only
describes them to the protocol. If the MCP SDK changes shape, this is the only file that moves.

The tool descriptions matter more than they look: they are what an agent reads when deciding
whether to call a tool at all. They are written to say when NOT to call it too.
"""
from __future__ import annotations

from mcp.server import MCPServer

from . import data, tools

__version__ = '0.1.0'

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
)
def explain_wait(wait_type: str) -> str:
    """Explain a SQL Server wait type and whether it matters."""
    return tools.explain_wait(wait_type)


@server.tool(
    name='check_build',
    title='Check a SQL Server build number',
    description=(
        'Identify a SQL Server build number (e.g. 16.0.4265.3, or pasted @@VERSION output) '
        'and report the version, patch level against the latest update on its servicing '
        'train, and whether it is still in support. Use this for any question about what '
        'version a server is on, whether it needs patching, or when support ends. Always '
        'prefer this over recalled build numbers, which go stale within weeks.'
    ),
)
def check_build(build: str) -> str:
    """Identify a build number and report patch level and support status."""
    return tools.check_build(build)


def describe() -> str:
    """Human-readable summary of what is loaded. Used by --selftest and the tests."""
    m = data.meta()
    c = m.get('counts', {})
    return ('sqldba MCP v%s | %s errors, %s wait types across %s posts, %s versions '
            '| data generated %s'
            % (__version__, c.get('errors'), c.get('wait_types'), c.get('waits'),
               c.get('versions'), m.get('generated')))


def main() -> None:
    server.run(transport='stdio')
