"""End-to-end test over the real MCP protocol, in a real subprocess.

Everything else in this directory imports `tools` and calls functions. That proves the
answers are right and proves nothing about the server, because the entire protocol layer -
the stdio transport, the handshake, tool registration, the resource closures, the prompt -
is skipped. If the SDK changed shape under us, all 74 of those tests would still pass and
`claude mcp add sqldba` would be broken for every user.

So this file speaks the protocol properly: it spawns `python -m sqldba_mcp` as a separate
process, does the initialize handshake over stdio, and exercises one of each surface. It is
the only test here that would notice the server failing to start at all.

Slower than the rest (a process launch and a handshake, roughly a second). Worth it once.
"""
from __future__ import annotations

import asyncio
import os
import pathlib
import sys
import unittest

MCP_DIR = pathlib.Path(__file__).resolve().parent.parent

try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    HAVE_CLIENT = True
except ImportError:                                                # pragma: no cover
    HAVE_CLIENT = False

TIMEOUT_SECONDS = 60


def _params() -> 'StdioServerParameters':
    """Run the server the way a client does, from a separate process.

    PYTHONPATH is set explicitly rather than relying on the install: this has to work both
    in CI (where the package is pip-installed) and from a bare checkout.
    """
    env = dict(os.environ)
    env['PYTHONPATH'] = str(MCP_DIR / 'src') + os.pathsep + env.get('PYTHONPATH', '')
    # The console this runs on is cp1252 on Windows; a non-ASCII byte in a script body
    # would otherwise take the subprocess down mid-handshake.
    env['PYTHONIOENCODING'] = 'utf-8'
    return StdioServerParameters(command=sys.executable, args=['-m', 'sqldba_mcp'], env=env)


async def _talk_to_server():
    """One session, every surface. Returns what was collected for the assertions."""
    async with stdio_client(_params()) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            tool_list = await session.list_tools()
            resources = await session.list_resources()
            prompts = await session.list_prompts()
            error = await session.call_tool(
                'lookup_error', {'error': 'Msg 18456, Level 14, State 1, Line 1'})
            build = await session.call_tool('check_build', {'build': '15.0.4430.1'})
            unknown = await session.call_tool(
                'answer_question', {'question': 'how do I configure an nginx reverse proxy'})
            first_doc = await session.read_resource(resources.resources[0].uri)
            rubric = await session.get_prompt('sql-server-health-triage')
            return {
                'name': init.server_info.name,
                'version': init.server_info.version,
                'tools': [t.name for t in tool_list.tools],
                'annotations': {t.name: t.annotations for t in tool_list.tools},
                'resources': [str(r.uri) for r in resources.resources],
                'prompts': [p.name for p in prompts.prompts],
                'error_text': error.content[0].text,
                'build_text': build.content[0].text,
                'unknown_text': unknown.content[0].text,
                'doc_text': first_doc.contents[0].text,
                'rubric_text': rubric.messages[0].content.text,
            }


@unittest.skipUnless(HAVE_CLIENT, 'the MCP client SDK is not importable')
class TestOverTheWire(unittest.TestCase):
    """One handshake, shared by every assertion - a process launch per test is wasteful."""

    @classmethod
    def setUpClass(cls):
        from sqldba_mcp import server
        cls.expected_version = server.__version__
        cls.result = asyncio.run(asyncio.wait_for(_talk_to_server(), TIMEOUT_SECONDS))

    def test_the_server_starts_and_completes_a_handshake(self):
        self.assertEqual(self.result['name'], 'sqldba')
        self.assertEqual(self.result['version'], self.expected_version)

    def test_all_six_tools_are_advertised(self):
        self.assertEqual(set(self.result['tools']),
                         {'lookup_error', 'explain_wait', 'check_build', 'find_script',
                          'get_script', 'answer_question'})

    def test_annotations_survive_serialisation(self):
        """They are set in Python; what matters is that they reach the client."""
        for name, ann in self.result['annotations'].items():
            with self.subTest(tool=name):
                self.assertIsNotNone(ann)
                self.assertTrue(ann.read_only_hint)
                self.assertFalse(ann.open_world_hint)

    def test_a_tool_call_returns_the_real_answer(self):
        text = self.result['error_text']
        self.assertIn('18456', text)
        self.assertIn('Login failed', text)

    def test_the_patch_level_warning_survives_the_round_trip(self):
        """The highest-value sentence in the server; assert it over the wire, not in-process."""
        self.assertIn('NOT the highest build on this series', self.result['build_text'])

    def test_a_refusal_comes_back_as_a_refusal(self):
        self.assertIn('nothing in the published faq', self.result['unknown_text'].lower())

    def test_resources_are_listed_and_readable(self):
        self.assertEqual(len(self.result['resources']), 9)
        for uri in self.result['resources']:
            self.assertTrue(uri.startswith('sqldba://docs/'), uri)
        self.assertGreater(len(self.result['doc_text']), 500)

    def test_the_prompt_is_listed_and_returns_the_rubric(self):
        self.assertEqual(self.result['prompts'], ['sql-server-health-triage'])
        self.assertGreater(len(self.result['rubric_text']), 1000)
        self.assertIn('CRITICAL', self.result['rubric_text'])


if __name__ == '__main__':
    unittest.main()
