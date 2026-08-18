"""Adversarial battery: the promise that this server declines rather than guesses.

The retrieval eval measures whether the right record comes back for a question the corpus
CAN answer. It says nothing about the two ways this server actually hurts someone in the
field, so they get their own file:

  * a FALSE NEGATIVE - "not in the library" for something that is in the library. Worse
    than a wrong answer, because the instructions tell the agent to trust that phrase and
    stop looking. This is what shipped in 0.2.0 for `Msg 18456, Level 14, State 1`.
  * a FALSE POSITIVE - a confident, plausible, irrelevant answer to a question outside the
    corpus. "How do I configure an nginx reverse proxy" once matched a SQL Agent *proxy*
    answer, which reads perfectly and is useless.

Both are behaviour, not retrieval, so neither shows up in a top-1 score. Everything here
is asserted against the shipped tool functions - coverage floors and off-domain guard
included - because a guard that is bypassed by the test is not a guard.
"""
from __future__ import annotations

import unittest

from sqldba_mcp import data, tools

# The phrases the tools use to decline. If a refusal is ever reworded, this list is the
# single place it has to change - and a reword that forgets to update it fails loudly
# rather than silently turning every refusal assertion into a pass.
REFUSALS = ('not in the', 'nothing in the', 'could not find', 'does not match',
            'no script is named', 'no script called', 'give me a', 'ask a question',
            'describe the task')


def declined(answer: str) -> bool:
    return any(marker in answer.lower() for marker in REFUSALS)


class TestItDeclinesRatherThanGuessing(unittest.TestCase):
    """Off-domain, absent, and outright nonsense input. All must be refused."""

    OFF_DOMAIN = [
        ('answer_question', 'how do I configure an nginx reverse proxy'),
        ('answer_question', 'how do I vacuum a postgres table'),
        ('answer_question', 'how do I tune the innodb buffer pool in mysql'),
        ('answer_question', 'what is the best oracle RAC interconnect'),
        ('answer_question', 'how do I create a kubernetes ingress'),
        ('answer_question', 'write me a python script to sort a list'),
        ('answer_question', 'what is the capital of France'),
        ('find_script', 'deploy a react frontend'),
        ('find_script', 'make me a sandwich'),
    ]

    ABSENT_BUT_PLAUSIBLE = [
        ('lookup_error', '12345678'),
        ('lookup_error', 'error 31337'),
        ('explain_wait', 'FAKE_WAIT_THAT_DOES_NOT_EXIST'),
        ('explain_wait', 'NGINX_LATCH'),
        ('check_build', '99.0.1000.0'),
        ('check_build', 'not a version at all'),
        ('get_script', 'Get-TotallyMadeUpScript'),
    ]

    def test_off_domain_questions_are_refused(self):
        for tool, question in self.OFF_DOMAIN:
            with self.subTest(tool=tool, q=question):
                answer = getattr(tools, tool)(question)
                self.assertTrue(declined(answer),
                                '%s answered an off-domain question: %r' % (tool, answer[:120]))

    def test_plausible_but_absent_input_is_refused(self):
        """The hardest case: shaped exactly like a real query, simply not covered."""
        for tool, question in self.ABSENT_BUT_PLAUSIBLE:
            with self.subTest(tool=tool, q=question):
                answer = getattr(tools, tool)(question)
                self.assertTrue(declined(answer),
                                '%s invented an answer: %r' % (tool, answer[:120]))

    def test_a_refusal_still_points_somewhere_useful(self):
        """Declining is correct; declining into a dead end is not."""
        answer = tools.lookup_error('12345678')
        self.assertIn('sqldba.blog', answer)


class TestItAnswersWhatItActuallyCovers(unittest.TestCase):
    """The other half. A refusal battery alone is passed by a server that refuses
    everything, so the same shipped path is asserted in the positive direction."""

    MUST_ANSWER = [
        ('lookup_error', '18456'),
        ('lookup_error', 'Msg 18456, Level 14, State 1, Line 1'),
        ('lookup_error', 'login failed'),
        ('lookup_error', 'incorrect syntax'),
        ('explain_wait', 'PAGEIOLATCH_SH'),
        ('explain_wait', 'cxpacket'),
        ('check_build', '16.0.4265.3'),
        ('check_build', 'Microsoft SQL Server 2022 (RTM-CU12) - 16.0.4115.5 (X64)'),
        ('find_script', 'find blocking chains'),
        ('find_script', 'check backup coverage'),
        ('answer_question', 'should I add a second data file'),
    ]

    def test_covered_questions_are_answered(self):
        for tool, question in self.MUST_ANSWER:
            with self.subTest(tool=tool, q=question):
                answer = getattr(tools, tool)(question)
                self.assertFalse(declined(answer),
                                 '%s refused something it covers: %r' % (tool, question))


class TestCrossToolContamination(unittest.TestCase):
    """A question belongs to one tool. The others should mostly stand down.

    This is the closest a deterministic test gets to measuring tool routing, which is
    otherwise only testable with a live model. It cannot check that an agent PICKS the
    right tool, but it can check the damage when it picks wrong.

    `answer_question` is deliberately exempt: it is the broad tool, its own description
    carries the ROUTING rule that sends numbers and wait types elsewhere, and it holds
    genuinely on-topic FAQ answers about error 18456 and about blocking. Overlap there is
    the design working, not a leak - the specific tools are the ones that must not stray.
    """

    SPECIFIC = ('lookup_error', 'explain_wait', 'check_build', 'find_script')

    OWNED = [
        ('check_build', '16.0.4165.4'),
        ('explain_wait', 'PAGEIOLATCH_SH'),
        ('lookup_error', '18456'),
        ('find_script', 'find blocking chains'),
    ]

    def test_the_specific_tools_stay_on_their_own_ground(self):
        for owner, question in self.OWNED:
            for tool in self.SPECIFIC:
                if tool == owner:
                    continue
                with self.subTest(owner=owner, wrong_tool=tool, q=question):
                    answer = getattr(tools, tool)(question)
                    self.assertTrue(
                        declined(answer),
                        '%s answered a question owned by %s: %r'
                        % (tool, owner, answer[:120]))

    def test_the_owning_tool_does_answer(self):
        for owner, question in self.OWNED:
            with self.subTest(owner=owner, q=question):
                self.assertFalse(declined(getattr(tools, owner)(question)))


class TestEveryAnswerCanBeCited(unittest.TestCase):
    """Rule 1 in tools.py: an agent quoting this must be able to cite it.

    Errors are the known exception - 22 of the 47 have no post yet - so this asserts the
    rule where it can be kept and documents the gap where it cannot, rather than being
    quietly weakened to whatever currently passes.
    """

    def test_waits_builds_scripts_and_faqs_all_carry_a_link(self):
        answers = {
            'explain_wait': tools.explain_wait('PAGEIOLATCH_SH'),
            'check_build': tools.check_build('16.0.4265.3'),
            'find_script': tools.find_script('find blocking chains'),
            'answer_question': tools.answer_question('should I add a second data file'),
        }
        for tool, answer in answers.items():
            with self.subTest(tool=tool):
                self.assertIn('https://sqldba.blog/', answer)

    def test_an_error_that_has_a_post_cites_it(self):
        self.assertIn('https://sqldba.blog/', tools.lookup_error('18456'))


class TestInputItShouldNotChokeOn(unittest.TestCase):
    """Nothing here should raise. A tool that throws takes the whole call out."""

    JUNK = ['', '   ', '\n\t', 'a', '?', '!!!', '0', '-1', '999999999999999999',
            'SELECT * FROM sys.databases', '<script>alert(1)</script>',
            'DROP TABLE users; --', '%s %d %r', '{}', '[]', 'null', 'None',
            '../../etc/passwd', 'x' * 5000, 'Msg , Level , State ,']

    def test_no_tool_raises_on_junk(self):
        for tool in ('lookup_error', 'explain_wait', 'check_build', 'find_script',
                     'get_script', 'answer_question'):
            for junk in self.JUNK:
                with self.subTest(tool=tool, input=junk[:40]):
                    try:
                        result = getattr(tools, tool)(junk)
                    except Exception as exc:                       # noqa: BLE001
                        self.fail('%s raised %r on %r' % (tool, exc, junk[:40]))
                    self.assertIsInstance(result, str)
                    self.assertTrue(result.strip(), '%s returned empty' % tool)


if __name__ == '__main__':
    unittest.main()


class TestEveryErrorAnswerSaysWhereItStands(unittest.TestCase):
    """Rule 1 of tools.py, made assertable instead of aspirational.

    22 of the 47 errors have no post yet. The URL line was simply omitted for those, so a
    verified answer was indistinguishable from an uncited one and an agent could not tell
    "there is no source" from "the source was withheld". Every error answer now ends with
    either a real write-up link or an explicit statement that none exists.
    """

    def test_every_single_error_answer_states_its_source_position(self):
        for e in data.errors():
            if e['error_number'] is None:
                continue
            with self.subTest(error=e['error_number']):
                answer = tools.lookup_error(str(e['error_number']))
                cited = 'https://sqldba.blog/' in answer and 'Full write-up:' in answer
                declared = 'No write-up published for this error yet' in answer
                self.assertTrue(cited or declared,
                                'error %s neither cites a post nor says it has none'
                                % e['error_number'])

    def test_an_uncited_error_still_hands_over_the_verified_content(self):
        """Saying "no post" must not become a refusal - the content is verified."""
        uncited = next(e for e in data.errors() if not e.get('url') and e['error_number'])
        answer = tools.lookup_error(str(uncited['error_number']))
        self.assertIn('No write-up published', answer)
        self.assertIn(str(uncited['error_number']), answer)
        self.assertNotIn('Not in the sqldba.blog library', answer)


class TestTheExporterIsLoudAboutWhatItCannotRead(unittest.TestCase):
    r"""The bug class that bit three times in one session, turned into a gate.

    Every one had the same shape: a parser read a source too narrowly and emitted None or
    a truncated value without complaint.

      * `Safe :` was never looked for, so 12 classified scripts shipped as "not stated"
      * `-- SAFE:Creates objects` matched `(\w+)` and became the class "Creates"
      * NEGATIVE anchored at the first word, so 13 wait verdicts inverted

    None of them broke anything visibly. They just quietly made the library wrong. These
    coverage floors are deliberately set below today's numbers so an unrelated content
    change does not turn the build red, but a parser that stops understanding a whole
    dialect will drop straight through them.
    """

    def _missing(self, rows, field):
        return [r for r in rows if not r.get(field) and r.get(field) is not False]

    def test_errors_carry_their_substance(self):
        errors = data.errors()
        for field in ('title', 'message', 'meaning', 'category'):
            with self.subTest(field=field):
                missing = self._missing(errors, field)
                self.assertLessEqual(len(missing), len(errors) * 0.10,
                                     '%d of %d errors have no %s'
                                     % (len(missing), len(errors), field))

    def test_every_wait_has_a_verdict_and_a_judgement(self):
        waits = data.waits()
        self.assertEqual([w['wait_types'] for w in waits if w.get('matters') is None], [],
                         'a wait with no matters flag cannot be triaged')
        self.assertLessEqual(len(self._missing(waits, 'verdict')), len(waits) * 0.05)
        self.assertLessEqual(len(self._missing(waits, 'what_to_do')), len(waits) * 0.15)

    def test_the_wait_verdict_split_stays_plausible(self):
        """A parser regression tends to slam everything to one side of the split."""
        waits = data.waits()
        chase = sum(1 for w in waits if w['matters'] is True)
        share = chase / len(waits)
        self.assertTrue(0.20 <= share <= 0.75,
                        '%.0f%% of waits flagged worth investigating - a split that lopsided '
                        'usually means the verdict parser broke, not that the library changed'
                        % (100 * share))

    def test_scripts_carry_purpose_and_class(self):
        scripts = data.scripts()
        self.assertLessEqual(len(self._missing(scripts, 'purpose')), len(scripts) * 0.05)
        self.assertEqual(self._missing(scripts, 'safe'), [],
                         'a script with no safety class must never ship')

    def test_faq_pairs_are_complete(self):
        faqs = data.faqs()
        for field in ('question', 'answer', 'url'):
            with self.subTest(field=field):
                self.assertEqual(self._missing(faqs, field), [])


class TestTheGuardDoesNotRefuseRealQuestions(unittest.TestCase):
    """The off-domain guard exists to stop false positives. It was causing false negatives.

    There is no stemmer here, so "corruption" was in the script corpus and "corrupt" was
    not. Asking `find_script("is my database corrupt")` put half the query in the unknown
    bucket, tripped the guard, and returned "nothing in the dba-tools library matches
    that" - from a library holding `Get-SuspectPages` and `Get-LastDbccCheckdb`. Refusing
    a corruption question is the worst false negative this library can produce.

    Both directions are asserted, because widening a guard is exactly the change that
    quietly turns a refusal promise into a suggestion.
    """

    MUST_ANSWER = ['is my database corrupt', 'database corruption check',
                   'check for corrupt pages', 'find blocking chains',
                   'check backup coverage', 'missing indexes']

    MUST_REFUSE = ['deploy a react frontend', 'make me a sandwich',
                   'how do I configure an nginx reverse proxy',
                   'what is the capital of France',
                   'how do I vacuum a postgres table',
                   'write me a python script to sort a list']

    def test_real_dba_questions_are_answered(self):
        for q in self.MUST_ANSWER:
            with self.subTest(q=q):
                self.assertFalse(declined(tools.find_script(q)),
                                 'refused a question the library can answer: %r' % q)

    def test_off_domain_questions_are_still_refused(self):
        for q in self.MUST_REFUSE:
            with self.subTest(q=q):
                self.assertTrue(declined(tools.find_script(q)),
                                'the widened guard let an off-domain query through: %r' % q)

    def test_the_prefix_rule_does_not_match_on_fragments(self):
        """Short tokens must not prefix-match half the corpus into looking familiar."""
        index = data.script_index()
        self.assertFalse(index._recognises('xyz'))
        self.assertTrue(index._recognises('corrupt'))
