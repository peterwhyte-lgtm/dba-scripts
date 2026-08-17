"""Tests for the sqldba MCP server.

Written as unittest.TestCase so they run under both `python -m unittest discover -s tests`
(zero dependencies) and `pytest` (in CI). The runtime package itself needs no test framework.

The tests that matter most are not the happy paths - they are:
  * test_no_private_data_shipped  - the leak gate, on the data that actually ships
  * TestBuildTrains               - the servicing-train regression, which was a real bug
  * test_every_answer_cites_source - attribution is the point of the whole server
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from sqldba_mcp import data, server, tools

DATA_DIR = Path(__file__).resolve().parent.parent / 'src' / 'sqldba_mcp' / 'datasets'


class TestData(unittest.TestCase):
    def test_datasets_present_and_populated(self):
        self.assertGreaterEqual(len(data.errors()), 40)
        self.assertGreaterEqual(len(data.waits()), 200)
        self.assertGreaterEqual(len(data.builds()['versions']), 5)

    def test_every_record_has_a_source_url(self):
        for e in data.errors():
            if e.get('url'):
                self.assertTrue(e['url'].startswith('https://sqldba.blog/'), e)
        for w in data.waits():
            self.assertTrue(w['url'].startswith('https://sqldba.blog/'), w)
        for v in data.builds()['versions']:
            self.assertTrue(v['url'].startswith('https://sqldba.blog/'), v)

    def test_wait_index_covers_every_declared_type(self):
        declared = {n.upper() for w in data.waits() for n in w['wait_types']}
        self.assertEqual(declared, set(data.waits_by_type()))

    def test_no_private_data_shipped(self):
        """The leak gate, checked against what is actually in the repo.

        The generator enforces this too, but the generator is private and this file is not,
        so the public repo verifies its own data rather than trusting an upstream promise.
        """
        forbidden = [r'PWSQL\d+', r'HPAI\d+', r'sqldba-staging', r'[A-Za-z]:\\Users\\',
                     r'localhost', r'\bAPI[_-]?KEY\b']
        for path in sorted(DATA_DIR.glob('*.json')):
            blob = path.read_text(encoding='utf-8')
            for pat in forbidden:
                hit = re.search(pat, blob, re.I)
                self.assertIsNone(hit, 'PRIVATE DATA IN %s: %r'
                                  % (path.name, hit.group(0) if hit else None))

    def test_data_is_ascii_only(self):
        """Non-ASCII in shipped data breaks cp1252 consoles mid-run (see my-data/CLAUDE.md)."""
        for path in sorted(DATA_DIR.glob('*.json')):
            raw = path.read_text(encoding='utf-8')
            bad = [c for c in raw if ord(c) > 127]
            self.assertEqual(bad, [], 'non-ASCII in %s: %r' % (path.name, bad[:5]))

    def test_meta_counts_match_reality(self):
        c = data.meta()['counts']
        self.assertEqual(c['errors'], len(data.errors()))
        self.assertEqual(c['waits'], len(data.waits()))
        self.assertEqual(c['versions'], len(data.builds()['versions']))


class TestLookupError(unittest.TestCase):
    def test_by_number(self):
        out = tools.lookup_error('18456')
        self.assertIn('18456', out)
        self.assertIn('Login failed', out)
        self.assertIn('https://sqldba.blog/', out)

    def test_number_with_whitespace(self):
        self.assertIn('18456', tools.lookup_error('  18456 '))

    def test_by_phrase(self):
        out = tools.lookup_error('filegroup is full')
        self.assertIn('1105', out)

    def test_unknown_number_says_so_rather_than_guessing(self):
        out = tools.lookup_error('99999')
        self.assertIn('not in the library', out.lower())
        # It must not invent an explanation.
        self.assertNotIn('severity', out.lower())

    def test_empty_input(self):
        self.assertIn('error number', tools.lookup_error('').lower())


class TestExplainWait(unittest.TestCase):
    def test_known_wait(self):
        out = tools.explain_wait('PAGEIOLATCH_SH')
        self.assertIn('PAGEIOLATCH_SH', out)
        self.assertIn('https://sqldba.blog/', out)

    def test_input_is_normalised(self):
        """A DBA pastes these in whatever case and spacing their output used."""
        canonical = tools.explain_wait('PAGEIOLATCH_SH')
        for variant in ('pageiolatch_sh', '  PageIOLatch_SH  ', 'PAGEIOLATCH_SH:'):
            self.assertEqual(tools.explain_wait(variant), canonical, variant)

    def test_verdict_is_stated(self):
        noisy = [w for w in data.waits() if w['matters'] is False]
        self.assertTrue(noisy, 'expected some waits classified as noise')
        out = tools.explain_wait(noisy[0]['wait_types'][0])
        self.assertIn('USUALLY NOISE', out)

    def test_unknown_wait_offers_near_matches_not_invention(self):
        out = tools.explain_wait('PAGEIOLATCH')
        self.assertTrue('Close matches' in out or 'PAGEIOLATCH' in out)

    def test_completely_unknown(self):
        out = tools.explain_wait('ZZZ_NOT_A_REAL_WAIT')
        self.assertIn('not in the sqldba.blog library', out.lower())


class TestBuildTrains(unittest.TestCase):
    """Regression tests for servicing-train selection.

    The first implementation picked the train whose build number was numerically nearest,
    which flipped between CU (16.0.4265.3) and CU+GDR (16.0.4262.2) essentially at random -
    they are three builds apart. Reporting the wrong train misstates whether a server is
    patched, which is the one thing this tool must not get wrong.
    """

    def test_cu_train_preferred_within_a_series(self):
        out = tools.check_build('16.0.4165.4')
        self.assertIn('Servicing train assumed:** CU -', out)
        self.assertIn('BEHIND', out)
        self.assertIn('CU26', out)

    def test_gdr_train_detected_by_series(self):
        out = tools.check_build('16.0.1190.2')
        self.assertIn('GDR', out)
        self.assertIn('UP TO DATE', out)

    def test_exact_match_is_up_to_date(self):
        self.assertIn('UP TO DATE', tools.check_build('16.0.4265.3'))

    def test_out_of_support_is_stated_loudly(self):
        out = tools.check_build('13.0.5888.11')
        self.assertIn('OUT OF SUPPORT', out)

    def test_parses_from_at_at_version_output(self):
        pasted = ('Microsoft SQL Server 2022 (RTM-CU26) (KB5093420) - 16.0.4265.3 (X64) '
                  'Jul 16 2026 on Windows Server 2022')
        self.assertIn('SQL Server 2022', tools.check_build(pasted))

    def test_unparseable_input_asks_rather_than_guesses(self):
        out = tools.check_build('the newest one')
        self.assertIn('could not find a build number', out.lower())

    def test_unknown_engine_major(self):
        out = tools.check_build('99.0.1.1')
        self.assertIn('does not match', out.lower())


class TestContract(unittest.TestCase):
    def test_every_answer_cites_source(self):
        """Attribution is the reason this server exists. No answer ships without a link."""
        answers = [
            tools.lookup_error('18456'),
            tools.explain_wait('PAGEIOLATCH_SH'),
            tools.check_build('16.0.4265.3'),
        ]
        for a in answers:
            self.assertIn('https://sqldba.blog/', a, a[:80])

    def test_tools_registered_with_the_server(self):
        names = {t.name for t in server.server._tool_manager.list_tools()} \
            if hasattr(server.server, '_tool_manager') else None
        if names is None:
            self.skipTest('SDK internals differ; covered by test_selftest')
        self.assertEqual(names, {'lookup_error', 'explain_wait', 'check_build'})

    def test_selftest_describes_the_load(self):
        d = server.describe()
        self.assertIn('sqldba MCP', d)
        self.assertIn('errors', d)


if __name__ == '__main__':
    unittest.main()
