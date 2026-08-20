"""Scored retrieval eval over the whole verified corpus.

This is the part Peter meant by "use all faq / related questions as a training tool". An
MCP server has no weights and cannot be trained, but 434 questions with known-good answers
are a **scored exam**, and that is worth more than training would be: it is a regression
gate, a public claim, and a roadmap all at once.

Five suites. Only the first is a real retrieval measure; the rest are plumbing, and the
scorecard says so rather than letting a flattering number stand unqualified:

  faq-reworded  434  questions asked in FEWER words than published -> must find that post
  faq-exact     434  the verbatim question, which is already in the index. A dictionary
                     lookup, not retrieval - it scored 98.6% and means nothing on its own
  err-phrase     47  the error's TITLE reworded the same way -> must find that error.
                     Real retrieval, and only since the substring search was replaced:
                     scored honestly, the old one got 29.8% while publishing 100%
  err-number     46  exact number in -> exact record out. Plumbing
  wait-name     232  exact wait name in -> exact record out. Plumbing, by design: waits
                     are looked up by name, so 100% here is correctness, not cleverness

The number is published even when it is poor (Peter's ruling): a 61% you can improve beats
a 100% rigged by writing the test after looking at the search. Misses are written to
output-files/eval-misses-*.txt, and every miss is either a retrieval bug or a genuine
content gap on the blog.

    python tests/eval_faq.py            # print the scorecard, write the miss lists
    python -m unittest tests.eval_faq   # same, as a CI regression gate

The gate thresholds are set BELOW the current score on purpose, so an accidental
regression fails the build while an improvement never has to be chased.
"""
from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'src'))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from sqldba_mcp import data, tools  # noqa: E402

OUT_DIR = pathlib.Path(__file__).resolve().parents[2] / 'output-files'

# Regression gates. Below the measured score, not equal to it - a gate that tracks the
# score exactly turns every unrelated data refresh into a red build.
MIN_FAQ_TOP1 = 0.60
MIN_FAQ_TOP3 = 0.70
MIN_ERROR = 0.90
MIN_ERR_PHRASE = 0.80
MIN_WAIT = 0.90
# Raised from 0.60 with the harness fix above: the old figure was set against a
# number produced by not calling the tool. 0.75 sits below today's 84.1% with
# room to move, and above the 65.9% the broken harness reported.
MIN_SCRIPT_RECALL = 0.75


def _ascii(s: str) -> str:
    return ''.join(c for c in s if ord(c) < 128)


def _degrade(question: str, keep: float = 0.6) -> str:
    """Turn a question into a plausible paraphrase of itself.

    THIS IS THE WHOLE POINT OF THE EVAL, so it is worth being explicit. Searching the FAQ
    index with the verbatim question that is already IN that index scores 98.6%, and that
    number is meaningless - it measures string equality, not retrieval. A real user asks
    in their own words and usually in fewer of them.

    So the query keeps a deterministic ~60% of the question's content tokens and drops the
    rest. It is a proxy, not a real paraphrase (it cannot introduce synonyms), so treat the
    result as an upper bound on real-world accuracy rather than a promise.
    """
    toks = data.tokens(question)
    if len(toks) <= 2:
        return question
    n = max(2, int(round(len(toks) * keep)))
    # Deterministic pick spread across the question, so the same input always scores the
    # same and a rerank is comparable run to run.
    step = len(toks) / n
    picked = [toks[min(len(toks) - 1, int(i * step))] for i in range(n)]
    return ' '.join(dict.fromkeys(picked))


def _faq_suite(name: str, transform) -> dict:
    """Scored against the SHIPPED path, coverage floor included.

    Querying the raw index would score higher and measure something the user never gets:
    `answer_question` applies min_coverage=0.5 so a single shared term is not treated as
    an answer. An eval that skips the guard is measuring a build that was never shipped.
    """
    index = data.faq_index()
    total = top1 = top3 = 0
    misses = []
    for row in data.faqs():
        total += 1
        hits = index.search(transform(row['question']), limit=3, min_coverage=0.5)
        urls = [h['url'] for h, _ in hits]
        if urls[:1] == [row['url']]:
            top1 += 1
            top3 += 1
        elif row['url'] in urls:
            top3 += 1
        else:
            misses.append((row['question'], row['url'], urls[0] if urls else '(nothing)'))
    return {'name': name, 'total': total, 'top1': top1, 'top3': top3, 'misses': misses}


def eval_faq_verbatim() -> dict:
    """Plumbing check only. A high score here proves nothing about retrieval quality."""
    return _faq_suite('faq-exact', lambda q: q)


def eval_faq() -> dict:
    """THE headline number: can it find the answer when the question is reworded?"""
    return _faq_suite('faq-reworded', _degrade)


def eval_errors_by_phrase() -> dict:
    """Real retrieval: search by what the error SAYS, in fewer words than it says it.

    This row used to score 100% and that number was worthless, in exactly the way this
    file warns about two suites further down. It queried with each error's VERBATIM
    title while `search_errors` was a substring test, so every record contained its own
    query by construction - and it accepted an answer as correct if the error number
    appeared anywhere in it, including buried in a list of eight candidates. Two
    independent ways to be unfalsifiable, stacked.

    So it is scored like the headline FAQ row now: the same deterministic rewording, and
    the record itself has to come back top, not merely be somewhere in the output. Under
    that measure the substring search scored 29.8% - which is what a DBA typing
    "incorrect syntax" rather than "Incorrect syntax near" was actually getting.
    """
    index = data.error_index()
    total = top1 = top3 = 0
    misses = []
    for e in data.errors():
        if not e.get('title'):
            continue
        total += 1
        query = _degrade(e['title'])
        hits = [h for h, _ in index.search(query, limit=3, min_coverage=0.34)]
        if hits[:1] == [e]:
            top1 += 1
            top3 += 1
        elif e in hits:
            top3 += 1
        else:
            misses.append((query, e.get('url') or e['title'],
                           hits[0]['title'] if hits else '(nothing)'))
    return {'name': 'err-phrase', 'total': total, 'top1': top1, 'top3': top3,
            'misses': misses}


def eval_errors() -> dict:
    """Canonical phrasing: 'what is SQL Server error 18456'."""
    total = hit = 0
    misses = []
    for e in data.errors():
        if e['error_number'] is None:
            continue
        total += 1
        answer = tools.lookup_error(str(e['error_number']))
        if str(e['error_number']) in answer and (
                not e.get('url') or e['url'] in answer):
            hit += 1
        else:
            misses.append((str(e['error_number']), e.get('url') or '', answer[:60]))
    return {'name': 'err-number', 'total': total, 'top1': hit, 'top3': hit,
            'misses': misses}


def eval_waits() -> dict:
    """Every wait type must resolve to its own write-up."""
    total = hit = 0
    misses = []
    for name, row in data.waits_by_type().items():
        total += 1
        answer = tools.explain_wait(name)
        if row['url'] in answer:
            hit += 1
        else:
            misses.append((name, row['url'], answer[:60]))
    return {'name': 'wait-name', 'total': total, 'top1': hit, 'top3': hit,
            'misses': misses}


# --- scripts ------------------------------------------------------------------------------

def eval_scripts() -> dict:
    """Can a DBA find the script they mean, asking in their own words?

    See tests/script_questions.py for the set and why it is scored on recall@8.
    """
    from script_questions import QUESTIONS
    from sqldba_mcp import tools
    total = top1 = top8 = 0
    misses = []
    for question, expected in QUESTIONS:
        total += 1
        # THROUGH THE TOOL, not the raw index. This called index.search() directly until
        # 2026-08-20, which skipped the ask-frame cleaning find_script applies to every
        # real query - so it scored the phrasing a DBA uses against a code path no DBA
        # reaches. "show me who has sysadmin" was recorded as "(nothing)" while the tool
        # returned Get-SysadminMembers at rank 1.
        #
        # It made this the worst suite here by a distance and sent two sessions looking
        # for a ranker defect that was mostly a harness one: 38.6/65.9 measured on the
        # index, 47.7/84.1 measured on the tool, and genuine misses 15 -> 7.
        #
        # Measure the thing that ships.
        hits = [line[4:].strip()
                for line in tools.find_script(question).splitlines()
                if line.startswith('### ')]
        if hits[:1] and hits[0] in expected:
            top1 += 1
        if any(h in expected for h in hits):
            top8 += 1
        else:
            misses.append((question, '/'.join(expected), ', '.join(hits[:3]) or '(nothing)'))
    return {'name': 'script-nl', 'total': total, 'top1': top1, 'top3': top8,
            'misses': misses}


def run_all(write_misses: bool = True) -> list[dict]:
    results = [eval_faq(), eval_faq_verbatim(), eval_errors_by_phrase(),
               eval_errors(), eval_waits(), eval_scripts()]
    if write_misses:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        for r in results:
            path = OUT_DIR / ('eval-misses-%s.txt' % r['name'])
            lines = ['%d misses of %d (%s suite)' % (len(r['misses']), r['total'], r['name']), '']
            for q, want, got in r['misses']:
                lines.append('Q:    %s' % _ascii(q))
                lines.append('want: %s' % want)
                lines.append('got:  %s' % _ascii(got))
                lines.append('')
            path.write_text('\n'.join(lines), encoding='utf-8')
    return results


def scorecard() -> str:
    rows = run_all()
    out = ['', 'RETRIEVAL EVAL', '=' * 58,
           '%-14s %6s %9s %9s' % ('suite', 'n', 'top-1', 'top-3'), '-' * 58]
    for r in rows:
        out.append('%-14s %6d %8.1f%% %8.1f%%'
                   % (r['name'], r['total'],
                      100 * r['top1'] / r['total'], 100 * r['top3'] / r['total']))
    out.append('-' * 58)
    head = next(r for r in rows if r['name'] == 'faq-reworded')
    out.append('HEADLINE (reworded questions, top-1): %.1f%%   top-3: %.1f%%'
               % (100 * head['top1'] / head['total'],
                  100 * head['top3'] / head['total']))
    out.append('')
    out.append('faq-exact / err-number / wait-name are PLUMBING checks - they query with')
    out.append('the exact indexed string, so a high score there proves nothing.')
    out.append('')
    out.append('miss lists: %s' % (OUT_DIR / 'eval-misses-*.txt'))
    return '\n'.join(out)


class TestRetrievalEval(unittest.TestCase):
    """Regression gate. Re-rank the search and these move immediately."""

    @classmethod
    def setUpClass(cls):
        cls.results = {r['name']: r for r in run_all(write_misses=False)}

    def test_faq_top1(self):
        r = self.results['faq-reworded']
        score = r['top1'] / r['total']
        self.assertGreaterEqual(score, MIN_FAQ_TOP1,
                                'FAQ top-1 fell to %.1f%%' % (100 * score))

    def test_faq_top3(self):
        r = self.results['faq-reworded']
        score = r['top3'] / r['total']
        self.assertGreaterEqual(score, MIN_FAQ_TOP3,
                                'FAQ top-3 fell to %.1f%%' % (100 * score))

    def test_errors(self):
        r = self.results['err-number']
        score = r['top1'] / r['total']
        self.assertGreaterEqual(score, MIN_ERROR,
                                'error lookup fell to %.1f%%' % (100 * score))

    def test_errors_by_phrase(self):
        """The suite that was unfalsifiable until 0.2.1. Gate it like a real one."""
        r = self.results['err-phrase']
        score = r['top1'] / r['total']
        self.assertGreaterEqual(score, MIN_ERR_PHRASE,
                                'error phrase retrieval fell to %.1f%%' % (100 * score))

    def test_scripts_natural_language(self):
        """recall@8: is the script a DBA meant among the eight they are shown?"""
        r = self.results['script-nl']
        score = r['top3'] / r['total']
        self.assertGreaterEqual(score, MIN_SCRIPT_RECALL,
                                'script recall@8 fell to %.1f%%' % (100 * score))

    def test_waits(self):
        r = self.results['wait-name']
        score = r['top1'] / r['total']
        self.assertGreaterEqual(score, MIN_WAIT,
                                'wait lookup fell to %.1f%%' % (100 * score))


if __name__ == '__main__':
    print(scorecard())
