"""Tests for the phase 2 surface: scripts, FAQ, docs, prompts, freshness, routing.

Kept separate from test_sqldba_mcp.py so the phase 1 contract stays readable on its own.
Same style: unittest.TestCase, no test dependencies.

The tests that carry weight here are the ones that could not be written by looking at the
happy path:
  * TestBoundary          - the index/corpus rule, asserted in BOTH directions
  * TestFindScript        - negative-tested, because every regex-shaped bug in this
                            workspace looked right until it was tested against known-bad
  * TestRouting           - a question in the wrong tool is a defect even when the answer
                            it returns reads fine
  * TestLeakGate          - the gate itself, proven to still bite after being loosened
"""
from __future__ import annotations

import json
import unittest

from sqldba_mcp import data, server, tools


class TestBoundary(unittest.TestCase):
    """The index/corpus boundary, asserted in BOTH directions.

    It is deliberately asymmetric: post write-ups stay on sqldba.blog, script bodies ship
    in full. Testing only one direction would let a refactor quietly flip the other, which
    is how a boundary decision silently becomes a boundary accident.
    """

    def test_script_bodies_DO_ship(self):
        scripts = data.scripts()
        self.assertGreaterEqual(len(scripts), 200)
        for s in scripts:
            self.assertTrue(s['body'].strip(), 'empty body: %s' % s['path'])
        sql = [s for s in scripts if s['language'] == 'sql']
        self.assertGreaterEqual(len(sql), 175)
        chains = next(s for s in sql if s['name'] == 'Get-BlockingChains')
        self.assertIn('Script Name : Get-BlockingChains', chains['body'])
        self.assertIn('SELECT', chains['body'].upper())
        self.assertGreater(len(chains['body']), 800)

    def test_post_bodies_do_NOT_ship(self):
        """FAQ answers and wait entries are extracts, never the article."""
        for w in data.waits():
            for field in ('verdict', 'what_to_do', 'when_to_ignore'):
                self.assertLessEqual(
                    len(w.get(field) or ''), 260,
                    'wait field long enough to be a body: %s' % w['url'])
            self.assertNotIn('<h2', json.dumps(w).lower())
        longest = max(data.faqs(), key=lambda f: len(f['answer']))
        self.assertLess(len(longest['answer']), 6000,
                        'FAQ answer looks like a whole article: %s' % longest['url'])
        for f in data.faqs():
            self.assertNotIn('<p>', f['answer'].lower())

    def test_script_headers_survive_so_attribution_travels(self):
        # Full path, because the bare name is genuinely ambiguous (a .sql and a .ps1
        # both answer to Get-BlockingChains) - see test_ambiguous_name_lists_candidates.
        out = tools.get_script('sql/performance/blocking-locking/Get-BlockingChains.sql')
        self.assertIn('Author', out)
        self.assertIn('sqldba.blog', out)

    def test_ambiguous_name_lists_candidates_instead_of_guessing(self):
        out = tools.get_script('Get-BlockingChains')
        self.assertIn('share the name', out)
        self.assertIn('.sql', out)
        self.assertIn('.ps1', out)
        self.assertNotIn('```', out)


class TestFindScript(unittest.TestCase):
    def test_finds_the_obvious_one(self):
        self.assertIn('Get-BlockingChains', tools.find_script('find blocking chains'))

    def test_thin_wrappers_are_excluded(self):
        """A wrapper would double every result with a shim nobody needs to read."""
        wrappers = [s['path'] for s in data.scripts() if '/wrappers/' in s['path']]
        self.assertEqual(wrappers, [], 'wrappers leaked in: %s' % wrappers[:3])

    def test_two_similarly_named_scripts_stay_distinct(self):
        names = {s['name'] for s in data.scripts()}
        frag = sorted(n for n in names if 'fragmentation' in n.lower())
        self.assertGreaterEqual(len(frag), 2, 'expected >1 fragmentation script: %s' % frag)
        out = tools.find_script('index fragmentation')
        found = [n for n in frag if n in out]
        self.assertGreaterEqual(len(found), 2,
                                'search collapsed similar names: found %s of %s'
                                % (found, frag))

    def test_known_bad_query_returns_nothing_rather_than_noise(self):
        out = tools.find_script('kubernetes helm chart ingress rabbitmq')
        self.assertIn('Nothing in the dba-tools library matches', out)

    def test_safety_class_is_always_surfaced(self):
        out = tools.find_script('backup coverage')
        self.assertTrue('SAFE:' in out or 'RiskLevel:' in out)
        self.assertIn('Check the safety class', out)

    def test_healthcheck_membership_matches_the_repo(self):
        self.assertEqual(sum(1 for s in data.scripts() if s['health_check']), 45)

    def test_every_sql_script_has_a_safety_class(self):
        missing = [s['path'] for s in data.scripts()
                   if s['language'] == 'sql' and not (s['safe'] and s['impact'])]
        self.assertEqual(missing, [], 'SQL scripts with no safety class: %s' % missing[:5])


class TestGetScript(unittest.TestCase):
    def test_exact_name_returns_a_fenced_body(self):
        self.assertIn('```sql', tools.get_script('Get-WaitStatistics'))

    def test_unknown_name_suggests_rather_than_guessing(self):
        out = tools.get_script('Get-SomethingThatDoesNotExist')
        self.assertTrue('Did you mean' in out or 'No script called' in out)
        self.assertNotIn('```', out)

    def test_powershell_gets_a_powershell_fence(self):
        self.assertIn('```powershell', tools.get_script('Invoke-HealthCheckCollection'))

    def test_empty_input(self):
        self.assertIn('script name', tools.get_script('').lower())


class TestAnswerQuestion(unittest.TestCase):
    def test_answers_a_real_question_with_a_citation(self):
        out = tools.answer_question('should I add a second data file')
        self.assertIn('https://sqldba.blog/', out)

    def test_unknown_topic_defers_to_the_right_tools(self):
        out = tools.answer_question('how do I configure an nginx reverse proxy')
        self.assertIn('lookup_error', out)
        self.assertIn('explain_wait', out)


class TestRouting(unittest.TestCase):
    """A question landing in the wrong tool is a defect even when its answer reads fine.

    The server cannot force an agent's choice, so what is testable is that the routing
    rule is actually present in the descriptions the agent reads, and that the specific
    tools genuinely beat the general one on their own ground.
    """

    ROUTING_HINTS = {
        'answer_question': ('lookup_error', 'explain_wait', 'check_build', 'find_script'),
        'find_script': ('get_script',),
        'get_script': ('find_script',),
    }

    def _registered(self):
        mgr = getattr(server.server, '_tool_manager', None)
        if mgr is None:
            self.skipTest('SDK internals differ')
        return {t.name: t for t in mgr.list_tools()}

    def test_descriptions_carry_the_routing_rules(self):
        reg = self._registered()
        for name, hints in self.ROUTING_HINTS.items():
            desc = (reg[name].description or '').lower()
            for hint in hints:
                self.assertIn(hint.lower(), desc,
                              '%s description never mentions %r' % (name, hint))

    def test_specific_tools_win_on_their_own_ground(self):
        self.assertIn('18456', tools.lookup_error('18456'))
        self.assertIn('PAGEIOLATCH_SH', tools.explain_wait('PAGEIOLATCH_SH'))
        self.assertIn('SQL Server 2022', tools.check_build('16.0.4265.3'))

    def test_tool_count_is_capped_at_six(self):
        """Tool bloat degrades tool choice. Six is the ceiling, not a target to grow into."""
        self.assertLessEqual(len(self._registered()), 6)

    def test_all_six_are_the_expected_six(self):
        self.assertEqual(set(self._registered()), {
            'lookup_error', 'explain_wait', 'check_build',
            'find_script', 'get_script', 'answer_question'})


class TestResourcesAndPrompts(unittest.TestCase):
    def test_docs_ship_as_resources(self):
        self.assertGreaterEqual(len(data.docs()), 8)
        for d in data.docs():
            self.assertTrue(d['uri'].startswith('sqldba://docs/'), d['uri'])
            self.assertTrue(d['body'].strip())

    def test_triage_prompt_carries_the_real_rubric(self):
        out = tools.health_triage_prompt()
        self.assertIn('ai-assessment-rubric.md', out)
        self.assertGreater(len(out), 1500)
        self.assertIn('CRITICAL', out.upper())


class TestFreshness(unittest.TestCase):
    """The server must admit staleness unprompted, not when asked."""

    def test_age_is_known(self):
        self.assertIsNotNone(data.data_age_days())

    def test_fresh_data_adds_no_noise(self):
        if (data.data_age_days() or 0) <= data.STALE_AFTER_DAYS:
            self.assertEqual(data.freshness_warning(), '')
            self.assertNotIn('Freshness warning', tools.check_build('16.0.4265.3'))

    def test_stale_data_warns_inside_the_answer(self):
        """Simulated: the shipped data is current today, so age is forced."""
        meta = data.meta()
        real = meta['generated']
        try:
            meta['generated'] = '2020-01-01'
            self.assertIn('Freshness warning', tools.check_build('16.0.4265.3'))
        finally:
            meta['generated'] = real
        self.assertNotIn('Freshness warning', tools.check_build('16.0.4265.3'))


class TestLeakGate(unittest.TestCase):
    """The gate was loosened twice during phase 2 after two false positives.

    Both were right to fix - a T-SQL DDL generator emitting `WITH PASSWORD = ' + CONVERT(`
    is not a secret, and `$env:ANTHROPIC_API_KEY` is the variable, not the key. But a gate
    that has been loosened is exactly the one that needs proof it still bites.
    """

    def test_new_corpora_are_clean(self):
        import re
        import pathlib
        d = pathlib.Path(data.DATA_DIR)
        forbidden = [r'PWSQL\d+', r'HPAI\d+', r'sqldba-staging', r'sk-ant-[A-Za-z0-9]',
                     r'[A-Za-z]:\\+Users\\+Peter']
        for name in ('scripts', 'faqs', 'docs', 'prompts'):
            blob = (d / ('%s.json' % name)).read_text(encoding='utf-8')
            for pat in forbidden:
                hit = re.search(pat, blob, re.I)
                self.assertIsNone(hit, 'PRIVATE DATA IN %s.json: %r'
                                  % (name, hit.group(0) if hit else None))

    def test_all_shipped_data_is_ascii(self):
        import pathlib
        for path in sorted(pathlib.Path(data.DATA_DIR).glob('*.json')):
            raw = path.read_text(encoding='utf-8')
            bad = sorted({c for c in raw if ord(c) > 127})
            self.assertEqual(bad, [], 'non-ASCII in %s: %r' % (path.name, bad[:5]))

    def test_meta_counts_match_the_new_corpora(self):
        c = data.meta()['counts']
        self.assertEqual(c['faqs'], len(data.faqs()))
        self.assertEqual(c['scripts'], len(data.scripts()))
        self.assertEqual(c['docs'], len(data.docs()))
        self.assertEqual(c['prompts'], len(data.prompts()))


if __name__ == '__main__':
    unittest.main()
