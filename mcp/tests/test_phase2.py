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
        """FAQ answers and wait entries are extracts, never the article.

        Exception, ruled by Peter 2026-08-21: `what_to_do` ships the FULL step list
        (exporter caps it at ~1500 plus an explicit trim marker). It is the payload of a
        WORTH INVESTIGATING verdict, and the 260-char extract was shipping a mid-word
        trim ("...Performance Monitor (...") on exactly the six most-asked waits. The
        article body still never crosses - steps are a section, not the write-up.
        """
        for w in data.waits():
            for field in ('verdict', 'when_to_ignore'):
                self.assertLessEqual(
                    len(w.get(field) or ''), 260,
                    'wait field long enough to be a body: %s' % w['url'])
            self.assertLessEqual(
                len(w.get('what_to_do') or ''), 1600,
                'what_to_do long enough to be a body: %s' % w['url'])
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
            # Locally an SDK bump degrades to a skip; in CI a skip here would mean the
            # six-tool cap and the routing rules are no longer tested by anything, and
            # a suite that can vanish without failing is the drift this repo documents.
            import os
            if os.environ.get('CI'):
                self.fail('SDK internals moved (server.server._tool_manager gone) - '
                          'port _registered() instead of letting these tests skip in CI')
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
        # Every shipped dataset, discovered rather than listed: posts.json shipped on
        # 2026-08-20 and sat outside a hand-kept tuple until 0.3.1. New corpus, new
        # leak surface, no edit here required.
        for path in sorted(d.glob('*.json')):
            blob = path.read_text(encoding='utf-8')
            name = path.stem
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


    def test_shipped_bodies_use_lf_only(self):
        """Datasets must not carry CRLF.

        They are generated on Windows and consumed by Linux CI. When they carried CRLF the
        freshness gate reported all 230 scripts as drifted the moment it ran anywhere but
        the generating machine - a gate that fails for everyone on the wrong platform is a
        gate people learn to ignore.
        """
        for corpus in (data.scripts(), data.docs(), data.prompts()):
            for record in corpus:
                self.assertNotIn(chr(13), record['body'],
                                 'CRLF in %s' % record.get('path') or record.get('name'))

    def test_meta_counts_match_the_new_corpora(self):
        c = data.meta()['counts']
        self.assertEqual(c['faqs'], len(data.faqs()))
        self.assertEqual(c['scripts'], len(data.scripts()))
        self.assertEqual(c['docs'], len(data.docs()))
        self.assertEqual(c['prompts'], len(data.prompts()))


if __name__ == '__main__':
    unittest.main()


class TestEntryPoints(unittest.TestCase):
    """`sqldba-mcp` and `python -m sqldba_mcp` must behave identically.

    They did not. --selftest was implemented only in __main__.py, so the README's first
    command started a stdio server, read EOF, and exited 0 printing nothing. A new user's
    first impression was a command that looks like it worked and did nothing at all.
    """

    def test_selftest_prints_the_summary(self):
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            server.main(['--selftest'])
        out = buf.getvalue()
        self.assertIn('sqldba MCP', out)
        self.assertIn('errors', out)

    def test_version_flag(self):
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            server.main(['--version'])
        self.assertIn(server.__version__, buf.getvalue())


class TestErrorLookupTakesWhatPeoplePaste(unittest.TestCase):
    """The forms an error arrives in, as opposed to the form the eval used to test.

    `Msg 18456, Level 14, State 1, Line 1` is what SQL Server prints, so it is what lands
    in a chat window. Until 0.2.1 the number was only read when the input was nothing but
    digits, and the phrase search behind it was a raw substring test - so this exact paste
    came back "not in the sqldba.blog library yet" for an error the library has always
    covered. A false negative is the worst answer this server can give: the whole promise
    is that "not in the library" can be trusted.
    """

    PASTES = ['18456', ' 18456 ', 'Msg 18456', 'msg 18456, Level 14, State 1, Line 1',
              'error 18456', 'SQL Server error 18456', 'Error: 18456']

    def test_every_paste_form_finds_the_error(self):
        for paste in self.PASTES:
            with self.subTest(paste=paste):
                self.assertIn('18456', tools.lookup_error(paste))
                self.assertNotIn('not in the sqldba.blog library',
                                 tools.lookup_error(paste).lower())

    def test_level_and_state_are_not_mistaken_for_the_error_number(self):
        """`Msg 9002, Level 17, State 2` must not resolve to error 17 or error 2."""
        out = tools.lookup_error('Msg 9002, Level 17, State 2, Line 1')
        self.assertIn('9002', out)
        self.assertIn('Transaction log', out)

    def test_word_order_and_extra_words_still_match(self):
        """A substring search failed both of these; ranked search must not."""
        for phrase in ('failed login', 'incorrect syntax', 'transaction log full'):
            with self.subTest(phrase=phrase):
                self.assertNotIn('not in the sqldba.blog library',
                                 tools.lookup_error(phrase).lower())

    def test_a_number_that_is_genuinely_absent_still_says_so(self):
        """The fix must not turn 'we do not have it' into a guess."""
        out = tools.lookup_error('99999')
        self.assertIn('99999', out)
        self.assertIn('not in the', out.lower())

    def test_off_topic_is_still_refused(self):
        """The coverage floor and off-domain guard have to survive the rewrite."""
        for q in ('how do I configure an nginx reverse proxy',
                  'what is the capital of France'):
            with self.subTest(q=q):
                self.assertIn('not in the sqldba.blog library', tools.lookup_error(q).lower())


class TestToolAnnotations(unittest.TestCase):
    """The 'it never touches your SQL Server' promise, made machine-readable.

    Prose in the README cannot be read by a client deciding whether to prompt the user.
    These hints can, so a reference lookup is auto-approvable instead of asking a DBA to
    confirm six times. If a tool is ever added that writes, connects, or reaches outside
    the bundled corpus, this test is what fails.
    """

    def _tools(self):
        import asyncio
        return asyncio.run(server.server.list_tools())

    def test_every_tool_declares_itself_read_only_and_closed_world(self):
        for t in self._tools():
            with self.subTest(tool=t.name):
                self.assertIsNotNone(t.annotations, '%s has no annotations' % t.name)
                self.assertTrue(t.annotations.read_only_hint)
                self.assertFalse(t.annotations.destructive_hint)
                self.assertTrue(t.annotations.idempotent_hint)
                self.assertFalse(t.annotations.open_world_hint,
                                 '%s claims an open world; this corpus is closed' % t.name)


class TestCliContract(unittest.TestCase):
    """Flags a user actually types, including the ones they mistype.

    Anything unrecognised used to fall through to the stdio server, where it sat waiting
    on a handshake a terminal never sends - so a typo looked like a hang, and exited 0.
    """

    def _run(self, args):
        import contextlib
        import io
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = server.main(args)
        return code, out.getvalue(), err.getvalue()

    def test_help_is_help_not_a_hung_server(self):
        code, out, _ = self._run(['--help'])
        self.assertEqual(code, 0)
        self.assertIn('--selftest', out)
        self.assertIn('claude mcp add sqldba', out)

    def test_a_mistyped_flag_fails_loudly(self):
        code, _, err = self._run(['--selftst'])
        self.assertEqual(code, 2, 'a bad flag must not exit 0')
        self.assertIn('--selftst', err)

    def test_known_flags_exit_zero(self):
        for flag in ('--selftest', '--version'):
            with self.subTest(flag=flag):
                self.assertEqual(self._run([flag])[0], 0)


class TestVersionHasOneSourceOfTruth(unittest.TestCase):
    """__version__ and the packaged version must not drift.

    They are declared in two files. A release that bumps one and not the other ships a
    server that reports a version it is not, which is the same class of error as a stale
    build number - the thing this whole server exists to stop.
    """

    def test_pyproject_matches_dunder_version(self):
        import pathlib
        import re
        pyproject = (pathlib.Path(__file__).resolve().parents[1] / 'pyproject.toml')
        declared = re.search(r'(?m)^version\s*=\s*"([^"]+)"',
                             pyproject.read_text(encoding='utf-8'))
        self.assertIsNotNone(declared, 'no version in pyproject.toml')
        self.assertEqual(declared.group(1), server.__version__)


class TestSafetyClassification(unittest.TestCase):
    r"""The class an agent shows a DBA *before* they run something.

    Three header dialects exist in this repo and the exporter read one of them, so scripts
    that were classified at source shipped as "safety class not stated":

        sql/**             -- SAFE:ReadOnly       + -- IMPACT:Low
        powershell/**      RiskLevel   : SAFE
        multi-server .ps1  Safe        : Read-only  (the SQL dialect, inside a .ps1)

    Twelve multi-server scripts were lost to the third. Ten more - every installation,
    patching and SSMS script, which is to say the six most dangerous things in the library -
    carried no class at all. And `-- SAFE:Creates objects` was captured by a `(\w+)` group
    as "Creates", a class in no vocabulary, and shipped without a complaint.
    """

    SQL_CLASSES = ('ReadOnly', 'WritesData', 'CreatesObjects')
    PS_CLASSES = ('SAFE', 'MEDIUM', 'HIGH IMPACT')

    def test_every_script_resolves_to_read_only_true_or_false(self):
        """None means 'nobody said', which is the state this test exists to prevent."""
        unclassified = [s['path'] for s in data.scripts() if s.get('read_only') is None]
        self.assertEqual(unclassified, [],
                         '%d script(s) carry no usable safety class: %s'
                         % (len(unclassified), unclassified[:6]))

    def test_every_class_is_in_its_vocabulary(self):
        for s in data.scripts():
            allowed = self.SQL_CLASSES if s['language'] == 'sql' else self.PS_CLASSES
            with self.subTest(path=s['path']):
                self.assertIn(s['safe'], allowed)

    def test_the_multi_server_dialect_is_read(self):
        """These were classified at source the whole time and shipped as unstated."""
        by_name = {s['name']: s for s in data.scripts()}
        self.assertTrue(by_name['MultiServer-GetBackupStatus']['read_only'])
        restart = by_name['MultiServer-RestartService']
        self.assertFalse(restart['read_only'],
                         'a script that restarts services on every target host is not read-only')

    def test_the_dangerous_installers_are_classified(self):
        by_name = {s['name']: s for s in data.scripts()}
        for name in ('install-sql', 'uninstall-sql', 'configure-sql', 'Invoke-SqlPatch'):
            with self.subTest(script=name):
                self.assertEqual(by_name[name]['safe'], 'HIGH IMPACT')
                self.assertFalse(by_name[name]['read_only'])


class TestDangerLeadsTheAnswer(unittest.TestCase):
    """Position, not just presence.

    The class was always in the response - rendered as `SAFE: WritesData   IMPACT: High`,
    carrying exactly the weight of the `path:` line under it. That is a label. An agent
    summarising a tool result leads with whatever is loudest, so the sentence a DBA must
    not miss has to BE the loudest and has to arrive before the body.
    """

    def _first_lines(self, text, n=6):
        return '\n'.join(text.splitlines()[:n])

    def test_a_non_read_only_script_warns_before_its_body(self):
        out = tools.get_script('Kill-BlockingSession')
        self.assertIn('NOT READ-ONLY', out)
        self.assertLess(out.index('NOT READ-ONLY'), out.index('```'),
                        'the warning must come before the script body')
        self.assertIn('NOT READ-ONLY', self._first_lines(out),
                      'the warning must be in the first few lines, not buried')

    def test_the_warning_names_the_class_and_the_impact(self):
        out = tools.get_script('Kill-BlockingSession')
        self.assertIn('WritesData', out)
        self.assertIn('High', out)

    def test_a_read_only_script_is_not_cluttered_with_warnings(self):
        """189 of 230 are read-only. A warning on all of them is a warning on none."""
        out = tools.get_script('Get-WaitStatistics')
        self.assertNotIn('NOT READ-ONLY', out)
        self.assertIn('SAFE: ReadOnly', out)

    def test_find_script_carries_the_warning_too(self):
        """The first place a DBA meets a script is usually the search result."""
        out = tools.find_script('kill a blocking session')
        self.assertIn('Kill-BlockingSession', out)
        self.assertIn('NOT READ-ONLY', out)

    def test_every_non_read_only_script_produces_a_warning(self):
        for s in data.scripts():
            if s['read_only'] is False:
                with self.subTest(script=s['name']):
                    self.assertIn('NOT READ-ONLY', tools.get_script(s['path']))


class TestPosts(unittest.TestCase):
    """The post tier shipped 2026-08-20 with no tests at all - the newest data is the
    least trusted, and this tier had already been tried once and reverted. These pin the
    contract: every record is complete and citable, the count is gated, and the index
    actually surfaces a post from words a reader would use.
    """

    def test_every_post_is_complete_and_citable(self):
        posts = data.posts()
        self.assertGreaterEqual(len(posts), 400, 'post corpus collapsed')
        for p in posts:
            with self.subTest(url=p.get('url')):
                self.assertTrue(p.get('title'), 'post with no title')
                self.assertRegex(p.get('url') or '',
                                 r'^https://sqldba\.blog/[a-z0-9\-/]+/$')

    def test_meta_count_matches(self):
        self.assertEqual(data.meta().get('counts', {}).get('posts'),
                         len(data.posts()))

    def test_index_surfaces_a_post_from_reworded_titles(self):
        """Sampled, reworded, rank-1 - the same discipline as eval_faq, so this cannot
        become the verbatim-lookup test the README warns about. A handful of misses is
        retrieval reality, not a defect; total failure is the defect."""
        import pathlib
        import sys
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
        import eval_faq
        posts = data.posts()
        sample = posts[:: max(1, len(posts) // 25)]
        hits = 0
        for p in sample:
            q = eval_faq._degrade(p['title'], keep=0.6)
            got = data.post_index().search(q, limit=1, min_coverage=0.0)
            if got and got[0][0]['url'] == p['url']:
                hits += 1
        self.assertGreaterEqual(hits / len(sample), 0.6,
                                'post index found %d/%d reworded titles'
                                % (hits, len(sample)))

    def test_answer_question_can_lead_with_a_post(self):
        """The covered-in path must actually fire: a question that names a post's
        subject but matches no FAQ pair well should still name the post."""
        answer = tools.answer_question('sqldba mcp server verified reference')
        self.assertIn('sqldba.blog', answer)


class TestAnswerStamp(unittest.TestCase):
    """Every answer names the server version and dataset date - refusals included.

    A stale install is invisible at runtime: pip pins a commit, the client says
    Connected, and the answers are simply older. The stamp makes the one observable
    surface - the answer itself - state what produced it (BACKLOG, 2026-08-19).
    """

    def _assert_stamped(self, answer: str):
        self.assertIn('_sqldba-mcp %s' % server.__version__, answer)
        self.assertIn('datasets generated %s' % data.meta().get('generated'), answer)

    def test_all_six_wired_handlers_stamp_their_answers(self):
        for call in (lambda: server.lookup_error('18456'),
                     lambda: server.explain_wait('PAGEIOLATCH_SH'),
                     lambda: server.check_build('16.0.4265.3'),
                     lambda: server.find_script('blocking chains'),
                     lambda: server.get_script('Get-BlockingChains'),
                     lambda: server.answer_question('should I add a second data file?')):
            self._assert_stamped(call())

    def test_refusals_are_stamped_too(self):
        """A stale refusal misleads exactly like a stale answer - 'not in the library'
        may be true of an old export and false of the current one."""
        self._assert_stamped(server.lookup_error('99999999'))

    def test_pure_tools_stay_unstamped(self):
        """The stamp is wiring-layer dressing; tools.py functions stay pure."""
        self.assertNotIn('_sqldba-mcp', tools.lookup_error('18456'))
