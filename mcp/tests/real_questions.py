"""Questions real people actually asked, and what the server must answer.

WHY THIS FILE IS DIFFERENT FROM EVERY OTHER SUITE HERE
------------------------------------------------------
`eval_faq.py` and `script_questions.py` build their queries FROM the corpus: take a
record, reword it, check the ranker finds it again. That measures the ranker and nothing
else, and it cannot fail for a record that is missing, mislabelled, or wrong.

On 2026-08-19 Peter asked nine ordinary questions. Six exposed defects. **129 unit tests
and all six eval suites were green the entire time**, because every one of those defects
lived outside what they can see:

  - the answering post existed and the tool quoted a footnote from it instead
  - the answering post was not in the corpus at all (74 published posts, 15%, are not)
  - the data was present and the input format was refused
  - a published fact was wrong
  - a heading was rendered that inverted the answer under it

So this suite asks from OUTSIDE. Every entry is a question a human typed, in the words
they typed it, with the answer judged the way they judged it. **Add to it every time
someone asks something real** - that is the whole mechanism. A question that passed is
worth keeping, because it is what stops a fix from silently regressing.

KNOWN-FAIL IS A FIRST-CLASS RESULT. An entry marked `gap=` documents something we have
decided not to fix yet, with the reason. It is reported separately and does not fail the
build. Deleting a failing question to make a number look better is the one thing that
would make this file worthless.

    PYTHONIOENCODING=utf-8 python tests/real_questions.py     # scorecard
    python -m unittest tests.real_questions                   # CI gate
"""
from __future__ import annotations

import pathlib
import re
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'src'))

from sqldba_mcp import tools  # noqa: E402

REFUSALS = (
    'is not in the library yet',
    'Nothing in the dba-tools library matches',
    'Nothing in the published FAQ answers matches',
    'Not in the sqldba.blog library yet',
    'could not find a build number',
)


# =========================================================================================
# The real questions. `expect` semantics by mode:
#   cites     - one of these slugs must appear in the reply's FIRST cited URL
#   leads     - the first `### Name` must be one of these
#   top2      - one of these must be in the first TWO `### Name` headings
#   error     - the reply must lead with one of these error numbers
#   contains  - every string must appear (case-insensitive)
#   refuses   - the reply must decline
# =========================================================================================

QUESTIONS = [
    dict(id='R01', asked='how do i update ssms to latest version',
         tool='answer_question', mode='cites',
         expect=['install-and-update-sql-server-management-studio-ssms'],
         note='Was answering "Do I need administrator rights?" - a footnote of the right post.'),

    dict(id='R02', asked='whats the default sql server ports',
         tool='answer_question', mode='cites', expect=['sql-server-default-ports'],
         gap='The post is published and is not in the corpus. It carries no FAQ block, and '
             'the corpus is built from FAQ blocks - 74 published posts (15%) are unreachable '
             'the same way.\n\n'
             'TRIED AND REVERTED 2026-08-19, do not retry blind: a fallback tier indexing '
             'every post by title + excerpt, consulted only when the FAQ tier declined or '
             'answered from an unrelated post. It DID fix this question. It was reverted '
             'because no threshold separates "this post covers your question" from "this '
             'post shares words with your question":\n'
             '    what is the best sql server book -> Kerberos vs NTLM        title match 0.58\n'
             '    whats the default sql server ports -> SQL Server Default Ports        0.49\n'
             'The false positive outscored the true one. Excerpt matching is no better - it '
             'scores 0.00 on "how do i kill a spid" (correct) and 1.00 on "how do I set up '
             'replication" (wrong). Off-domain honesty fell 22/30 -> 21/30 and R07 broke. '
             'A different signal is needed, not a different threshold.'),

    dict(id='R03', asked='whats the latest version of sql for 2017',
         tool='check_build', mode='contains', expect=['2017', 'CU31', '14.0.3456.2'],
         note='Refused outright before: the build being asked for was the price of asking.'),

    dict(id='R04', asked='does sql server 2022 standard edition have compression available',
         tool='answer_question', mode='cites',
         expect=['dba-scripts-server-inventory', 'dba-scripts-server-and-configuration',
                 'sql-server-edition-change-runbook'],
         note='EXPECTATION WIDENED 2026-08-19, and the reason matters. It originally '
              'accepted only the Edition Change Runbook, because when this question was '
              'first asked that was the closest thing to an answer the corpus held - and '
              'it did not actually answer it. The three posts carrying the wrong "'
              'compression is Enterprise-only" claim were then corrected on live, and the '
              'corrected server-inventory answer now outranks the runbook and states the '
              'fact directly: compression came to Standard in SQL Server 2016 SP1. The '
              'suite flagged this as a FAIL, which is correct behaviour - the answer '
              'changed. It was verified as BETTER before the expectation was widened, not '
              'widened to make the number green.'),

    dict(id='R05', asked='The login is from an untrusted domain and cannot be used with '
                         'Windows authentication',
         tool='lookup_error', mode='error', expect=[18452],
         note='Found it from wording that does NOT match its stored message text, which '
              'says "Integrated authentication" - verified correct against sys.messages.'),

    dict(id='R06', asked='give script to show top cpu queries',
         tool='find_script', mode='leads', expect=['Get-TopCpuQueries']),

    dict(id='R07', asked='how do i get the sid of a sql login',
         tool='answer_question', mode='cites', expect=['dba-scripts-generate-login-script'],
         note='Was answering "Why does preserving the SID matter so much?"'),

    dict(id='R08', asked='how do i check space free in databases',
         tool='answer_question', mode='cites',
         expect=['dba-scripts-get-database-sizes-and-free-space'],
         note='Was answering "Should I shrink databases with free space?"'),

    dict(id='R09', asked='i need to check when my databases were last backed up',
         tool='find_script', mode='top2',
         expect=['Get-LastDatabaseBackupTimes', 'Get-BackupAge', 'Get-BackupCoverage'],
         note='Returned ONE script before, the LSN-continuity one, whose own description '
              'says "coverage scripts only check recency, not continuity". Rank 1 is still '
              'that script: its Purpose line describes what OTHER scripts do, and that text '
              'is indexed. Header edit, awaiting sign-off.'),

    dict(id='R10', asked='whats eating my cpu',
         tool='find_script', mode='leads', expect=['Get-TopCpuQueries'],
         note='Refused outright before - the off-domain guard had never seen "eating".'),

    # --- safety. Not a retrieval question: a question about what may be SHOWN.
    dict(id='R11', asked='is my sql server ok',
         tool='find_script', mode='refuses',
         note='Returned 8 scripts including uninstall-sql ("removes a SQL Server instance '
              'and can delete its data directories").'),

    dict(id='R13', asked='my log file keeps growing what do I do',
         tool='answer_question', mode='cites', expect=['dba-scripts-get-database-health'],
         note='REGRESSED SILENTLY AND WAS NOT IN THIS FILE. It answered correctly early on '
              '2026-08-19, then the stopword and synonym changes reordered the ranking and '
              'it started returning "How is this different from reading actual autogrowth '
              'events?" - a pair sharing NO word with the question, ranked above the right '
              'answer. Nothing caught it because it was a Layer B probe, not one of these. '
              'It is here now so the next reordering has to trip over it.'),

    dict(id='R12', asked='the server is slow',
         tool='find_script', mode='readonly_only',
         note='Returned linked-server scripts and a TCP port test. Any answer is fine so '
              'long as nothing in it changes the server.'),
]


# =========================================================================================
# Off-domain. An honest "not in the library" is the ONLY pass. Answering from recall is a
# failure EVEN IF the answer is correct - that is the server's entire reason to exist.
# Every entry below was checked against the live site: none is covered by a published post.
# =========================================================================================

OFF_DOMAIN = [
    # --- held out on 2026-08-20, and they earned their place ------------------------
    # The eight below were written by a session that had NOT seen this file, precisely
    # because the number here had stopped being a measurement: 86.7% was reported after
    # tuning against these same probes. Run cold against the tuned build, four of the
    # eight were answered confidently, and every one matched on a single ordinary word
    # ("better", "worth", "security"). That produced the IDF-weighted coverage floor.
    #
    # They are regression cases now, not a held-out set: the moment they are in here,
    # anyone can tune against them. THE NEXT PERSON TO QUOTE A NUMBER OFF THIS FILE
    # OWES IT A FRESH SET THAT NOBODY HAS SEEN.
    ('answer_question', 'what salary should a sql server dba expect'),
    ('answer_question', 'which laptop is best for database work'),
    ('answer_question', 'is oracle better than sql server'),
    ('answer_question', 'how do I back up my laptop before a holiday'),
    ('answer_question', 'what certifications are worth doing for a dba career'),
    ('answer_question', 'how much RAM should I buy for my gaming pc'),
    ('answer_question', 'how do I get better at technical interviews'),
    ('answer_question', 'who should I report a security breach to'),
    # ---------------------------------------------------------------------------------
    ('answer_question', 'how do I install postgres'),
    ('answer_question', 'whats the connection string format for EF Core'),
    ('answer_question', 'best way to move a database to Azure'),
    ('answer_question', 'what is the best sql server book'),
    ('answer_question', 'how do I set up replication'),
    ('answer_question', 'write me a query to pivot rows into columns'),
    ('answer_question', 'how much should a dba be paid'),
    ('answer_question', 'which sql server certification should I take'),
    ('answer_question', 'how do I install mysql on ubuntu'),
    ('answer_question', 'what is the difference between mongodb and sql server'),
    ('answer_question', 'how do I configure an nginx reverse proxy'),
    ('answer_question', 'can you write me a python script to parse a csv'),
    ('answer_question', 'how do I set up an AWS RDS instance'),
    ('answer_question', 'what is the best ORM for dotnet'),
    ('answer_question', 'how do I renew a windows domain certificate'),
    ('answer_question', 'should I learn oracle or sql server'),
    ('answer_question', 'how do I use Dapper with stored procedures'),
    ('answer_question', 'what is kubernetes'),
    ('find_script', 'script to send a tweet'),
    ('find_script', 'powershell to resize a jpeg'),
    ('find_script', 'script to scrape a website'),
    ('find_script', 'give me a script to sort a python list'),
    ('find_script', 'bash script to tail a log file'),
    ('find_script', 'script to compress a folder into a zip'),
    ('lookup_error', '99999'),
    ('lookup_error', 'segmentation fault'),
    ('lookup_error', 'NullReferenceException'),
    ('explain_wait', 'FOO_BAR_WAIT'),
    ('explain_wait', 'CPU_STEAL_TIME'),
    ('check_build', 'windows server 2019'),
]


def _refused(reply: str) -> bool:
    return any(r in reply for r in REFUSALS)


def _leads(reply: str):
    m = re.search(r'^### (.+)$', reply, re.M)
    return m.group(1).strip() if m else None


def _all_scripts(reply: str) -> list[str]:
    return [m.strip() for m in re.findall(r'^### (.+)$', reply, re.M)]


def _first_url(reply: str) -> str:
    m = re.search(r'https://sqldba\.blog/(\S*)', reply)
    return m.group(1) if m else ''


def _lead_error(reply: str):
    m = re.search(r'^## Error (\d+)', reply, re.M)
    if m:
        return int(m.group(1))
    m = re.search(r'^- \*\*(\d+)\*\*', reply, re.M)
    return int(m.group(1)) if m else None


def _ascii(s: str) -> str:
    return ''.join(c for c in s if ord(c) < 128)


def run_one(q: dict):
    reply = getattr(tools, q['tool'])(q['asked'])
    mode = q['mode']
    if mode == 'refuses':
        return _refused(reply), 'refused' if _refused(reply) else (_leads(reply) or '?')
    if mode == 'readonly_only':
        from sqldba_mcp import data
        ro = {s['name']: s.get('read_only') for s in data.scripts()}
        bad = [n for n in _all_scripts(reply) if ro.get(n) is False]
        return (not bad), ('clean' if not bad else 'SHOWS ' + ', '.join(bad))
    if _refused(reply):
        return False, 'refused (expected an answer)'
    if mode == 'cites':
        got = _first_url(reply)
        return any(e in got for e in q['expect']), got or '(no url)'
    if mode == 'leads':
        got = _leads(reply)
        return got in q['expect'], got or '(nothing)'
    if mode == 'top2':
        got = _all_scripts(reply)[:2]
        return any(g in q['expect'] for g in got), ', '.join(got) or '(nothing)'
    if mode == 'error':
        got = _lead_error(reply)
        return got in q['expect'], str(got)
    if mode == 'contains':
        missing = [e for e in q['expect'] if e.lower() not in reply.lower()]
        return (not missing), 'ok' if not missing else 'missing ' + ', '.join(missing)
    raise ValueError(mode)


def run_all():
    rows = [(q,) + run_one(q) for q in QUESTIONS]
    off = []
    for tool, question in OFF_DOMAIN:
        reply = getattr(tools, tool)(question)
        off.append((tool, question, _refused(reply), _ascii(reply)[:70]))
    return rows, off


def main() -> int:
    rows, off = run_all()
    live = [r for r in rows if not r[0].get('gap')]
    gaps = [r for r in rows if r[0].get('gap')]

    print('REAL QUESTIONS - asked by a human, judged the way a human judged them')
    print('=' * 78)
    for q, ok, got in rows:
        tag = 'GAP ' if q.get('gap') else ('OK  ' if ok else 'FAIL')
        print('%-5s %-4s %-16s %s' % (q['id'], tag, q['tool'], q['asked'][:44]))
        if not ok:
            print('           want %s | got %s' % (q.get('expect', q['mode']), got))
    passed = sum(1 for _, ok, _ in live if ok)
    print('-' * 78)
    print('answered correctly: %d of %d   (%d documented gap%s excluded)'
          % (passed, len(live), len(gaps), '' if len(gaps) == 1 else 's'))
    for q, ok, _ in gaps:
        print('  GAP %s: %s' % (q['id'], q['gap'].split('.')[0] + '.'))

    honest = sum(1 for _, _, r, _ in off if r)
    print()
    print('OFF-DOMAIN HONESTY - a safety number, never averaged into anything else')
    print('=' * 78)
    for tool, question, refused, head in off:
        if not refused:
            print('  ANSWERED  %-16s %-44s -> %s' % (tool, question[:42], head[:38]))
    print('-' * 78)
    print('honest refusals: %d of %d  (%.1f%%)' % (honest, len(off), 100.0 * honest / len(off)))
    return 0


class TestRealQuestions(unittest.TestCase):
    """Gate. Documented gaps are excluded; everything else must answer."""

    def test_real_questions(self):
        rows, _ = run_all()
        broken = [(q['id'], q['asked'], got)
                  for q, ok, got in rows if not ok and not q.get('gap')]
        self.assertEqual([], broken, 'questions a human asked and got a wrong answer to')

    def test_off_domain_honesty(self):
        _, off = run_all()
        answered = [(t, q) for t, q, refused, _ in off if not refused]
        # 4 of 30 are answered today (86.7% honest, up from 73.3% once answer_question
        # started requiring the answer to share a word with the question). The gate sits
        # one ABOVE that, so a real regression fails the build while the current state
        # passes.
        #
        # It was first written as `<= 6`, copying the house habit of setting a gate BELOW
        # the measured score - which inverts for a count of FAILURES and made the gate red
        # from the moment it was written. Nobody noticed because `python tests/
        # real_questions.py` runs main(), not this, and `unittest discover` matches
        # test*.py so it never ran either. Two ways of never running, in one file whose
        # entire purpose is to run.
        #
        # LOWER THIS as the rate improves. Do not raise it to make a red build green.
        self.assertLessEqual(len(answered), 5,
                             'off-domain questions answered from recall: %s' % answered)


if __name__ == '__main__':
    raise SystemExit(main())
