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

from sqldba_mcp import tools

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
