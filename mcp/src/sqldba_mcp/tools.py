"""The three tools, as pure functions.

Every one of these takes plain arguments and returns a markdown string. No MCP types, no I/O,
no globals. That means they can be unit tested directly, reused behind an HTTP API later, and
read by someone who has never seen the Model Context Protocol.

Two rules every response follows:

1. **Every answer ends with its source URL.** An agent quoting this should be able to cite it,
   and the reader should be able to go and check the working. That link is the whole point.
2. **Say what was assumed.** A build number does not state which servicing train it is on, so
   the tool names the train it picked. A DBA can spot a wrong assumption instantly; a silently
   wrong answer about patch level is worse than no answer.
"""
from __future__ import annotations

import re

from . import data

NOT_COVERED = (
    "Not in the sqldba.blog library yet.\n\n"
    "This library is hand-verified rather than scraped, so it covers what a working DBA has "
    "actually written up. Treat its absence as 'not covered here', not 'does not exist'.\n\n"
    "Full index: https://sqldba.blog/"
)


def _fmt_error(e: dict) -> str:
    num = e['error_number']
    head = 'Error %s' % num if num is not None else e['title']
    lines = ['## %s - %s' % (head, e['title'])]
    if e.get('severity') is not None:
        lines.append('**Severity:** %s   **Category:** %s' % (e['severity'], e.get('category')))
    else:
        lines.append('**Category:** %s' % e.get('category'))
    lines.append('')
    if e.get('message'):
        lines.append('**Message text**')
        lines.append('```')
        lines.append(e['message'])
        lines.append('```')
    if e.get('meaning'):
        lines.append('**What it actually means**')
        lines.append(e['meaning'])
    lines.append('')
    if e.get('ms_docs'):
        # Microsoft's own page, alongside the hand-written one. Two independent sources beat
        # one, and it lets a reader check the library rather than take its word. Every URL
        # was probed and kept only if it returned 200 and still named this error, so its
        # ABSENCE means Microsoft has no page, not that nobody looked.
        lines.append('Microsoft reference: %s' % e['ms_docs'])
    if e.get('url'):
        lines.append('Full write-up: %s' % e['url'])
    else:
        # Not every error has a post yet. Omitting the line silently made a verified
        # answer look like an uncited one, and left an agent unable to tell "no source" from
        # "source withheld". Saying it plainly costs nothing and is the difference between a
        # gap and a mystery. Rule 1 in this module is then assertable rather than aspirational.
        lines.append('**No write-up published for this error yet.** The message text, '
                     'meaning and severity above are from the hand-verified error pool, so '
                     'they can be quoted - but there is no article to cite. '
                     'Index: https://sqldba.blog/')
    return '\n'.join(lines)


def lookup_error(error: str) -> str:
    """Look up a SQL Server error by number ('18456') or by phrase ('login failed')."""
    term = (error or '').strip()
    if not term:
        return "Give me an error number (e.g. 18456) or a phrase from the message."

    # Take a number out of it if one is in there. `Msg 18456, Level 14, State 1, Line 1` is
    # what SQL Server prints and so what gets pasted; reading that as "no number given" had
    # the agent reporting 18456 missing from a library that has covered it since day one.
    # A number that misses still falls through to the phrase search rather than stopping.
    number = data.parse_error_number(term)
    if number is not None:
        hit = data.errors_by_number().get(number)
        if hit:
            return _fmt_error(hit)

    hits = data.search_errors(term)
    if not hits:
        if number is not None:
            return "Error %s is not in the library yet.\n\n%s" % (number, NOT_COVERED)
        return NOT_COVERED
    if len(hits) == 1:
        return _fmt_error(hits[0])

    out = ['Found %d matching errors:' % len(hits), '']
    for e in hits:
        num = e['error_number']
        # Not every error has a post to cite yet, so do not leave the trailing gap where
        # the link would have gone.
        row = '- **%s** - %s' % (num if num is not None else '(no number)', e['title'])
        out.append('%s   %s' % (row, e['url']) if e.get('url') else row)
    out.append('')
    out.append('Ask again with a number for the full entry.')
    return '\n'.join(out)


# Candidate tokens are matched in any case, because a lowercased report is still a report
# and a DBA pasting one should not silently get nothing. Case is used for one thing only:
# deciding whether an UNRECOGNISED token is worth naming as "not in the library".
#
# Wait types are upper-case by convention in DMV output while column headers are lower-case
# (`wait_type`, `wait_time_ms`), so requiring caps there keeps the not-covered list honest
# without ever suppressing a real answer - a known type is found by index lookup, which is
# case-insensitive and authoritative.
_TOKEN = re.compile(r'\b[A-Za-z][A-Za-z0-9_]+\b')

# Words that arrive in a pasted result set or query and are not wait types. Only used to
# keep the "not in the library" list honest - a known type is matched by index lookup, so
# nothing here can ever suppress a real answer.
_NOT_WAITS = {
    'SELECT', 'FROM', 'WHERE', 'ORDER', 'GROUP', 'DESC', 'INNER', 'OUTER', 'JOIN',
    'UNION', 'HAVING', 'SERVER', 'DATABASE', 'MASTER', 'TEMPDB', 'TOTAL', 'PERCENT',
    'WAITING', 'TASKS', 'COUNT', 'SIGNAL', 'RESOURCE_MS', 'NULL', 'ROWS', 'AFFECTED',
    'WAIT_TYPE', 'WAIT_TIME_MS', 'MAX_WAIT_TIME_MS', 'SIGNAL_WAIT_TIME_MS',
    'WAITING_TASKS_COUNT', 'SQL', 'CPU', 'AVG', 'MIN', 'MAX', 'SUM',
}


def _wait_types_in(text: str) -> tuple[list[str], list[str]]:
    """Every wait type in a block of text, split into known and unrecognised.

    Nobody reads sys.dm_os_wait_stats one row at a time, so the tool has to accept the
    shape the data actually arrives in. Order is preserved and duplicates dropped.
    """
    index = data.waits_by_type()
    seen, known, unknown = set(), [], []
    for token in _TOKEN.findall(text or ''):
        name = data.normalise_wait(token)
        if not name or name in seen or name in _NOT_WAITS:
            continue
        seen.add(name)
        if name in index:
            known.append(name)
        elif token.isupper() and ('_' in name or len(name) >= 8):
            # Shaped like a wait type, upper-case like one, and not in the library.
            # Reported, never dropped: silently swallowing these is how a refusal promise
            # dies at scale. Lower-case tokens are skipped here rather than filling the
            # not-covered list with ordinary prose.
            unknown.append(name)
    return known, unknown


def _triage_waits(known: list[str], unknown: list[str]) -> str:
    """Rank a pasted result set by the verdict, which is the judgement worth having."""
    index = data.waits_by_type()
    chase, noise, unrated, seen_posts = [], [], [], set()
    for name in known:
        hit = index[name]
        if hit['url'] in seen_posts:
            continue          # one post can cover several types; do not repeat it
        seen_posts.add(hit['url'])
        verdict = hit.get('matters')
        (chase if verdict is True else noise if verdict is False else unrated).append(
            (name, hit))

    lines = ['Triaged %d wait type(s) from that. **%d worth investigating.**'
             % (len(known), len(chase)), '']
    if chase:
        lines += ['**WORTH INVESTIGATING**', '']
        for name, hit in chase:
            lines.append('- **%s** - %s  \n  %s'
                         % (name, (hit.get('verdict') or '').strip(), hit['url']))
        lines.append('')
    if noise:
        lines += ['**USUALLY NOISE - normally belongs on your filter list**', '',
                  ', '.join('`%s`' % n for n, _ in noise), '']
    if unrated:
        lines += ['**NO VERDICT RECORDED**', '',
                  ', '.join('`%s`' % n for n, _ in unrated), '']
    if unknown:
        lines += ['**NOT IN THE LIBRARY (%d)** - covered nowhere on sqldba.blog yet, so '
                  'no verdict is offered on them:' % len(unknown), '',
                  ', '.join('`%s`' % n for n in unknown[:25])
                  + (' ... and %d more' % (len(unknown) - 25) if len(unknown) > 25 else ''),
                  '']
    lines.append('Ask about any single one by name for the full write-up.')
    return '\n'.join(lines)


def explain_wait(wait_type: str) -> str:
    """Explain a SQL Server wait type, or triage a whole pasted result set."""
    # More than one recognised type means this is a result set, not a question about a
    # single wait. One type behaves exactly as it always has.
    known, unknown = _wait_types_in(wait_type or '')
    if len(known) > 1:
        return _triage_waits(known, unknown)

    name = data.normalise_wait(wait_type)
    if not name:
        return "Give me a wait type, e.g. PAGEIOLATCH_SH or CXPACKET."

    # One recognised type inside a sentence is still a question about that type. The
    # triage branch above only fires on two or more, so `explain PAGEIOLATCH_SH` used to
    # normalise the WHOLE string to EXPLAINPAGEIOLATCH_SH, match nothing, and refuse -
    # while pasting two waits worked perfectly. Only ever consulted when the raw string
    # failed to resolve, so nothing that already worked can change.
    if len(known) == 1 and name not in data.waits_by_type():
        name = data.normalise_wait(known[0])

    hit = data.waits_by_type().get(name)
    if not hit:
        near = data.search_waits(name)
        if near:
            out = ['No exact match for `%s`. Close matches:' % name, '']
            for w in near:
                out.append('- **%s** - %s' % (' / '.join(w['wait_types']), w['url']))
            return '\n'.join(out)
        return NOT_COVERED

    verdict = hit.get('matters')
    if verdict is True:
        badge = 'WORTH INVESTIGATING'
    elif verdict is False:
        badge = 'USUALLY NOISE - normally belongs on your filter list'
    else:
        badge = 'NO VERDICT RECORDED'

    lines = ['## %s' % ' / '.join(hit['wait_types']), '', '**%s**' % badge, '']
    if hit.get('verdict'):
        # Ask the question the POST asked. Most wait posts ask "Is This Wait Expected?"
        # and a handful ask "Is It a Problem?", and those invert each other: under the
        # first, "No" means the wait is bad. Printing every answer under a hardcoded
        # "Is it a problem?" made THREADPOOL read "Is it a problem? No. There is no safe
        # level of THREADPOOL during production operations." - the opposite of the post,
        # directly under a WORTH INVESTIGATING badge.
        lines += ['**%s**' % (hit.get('verdict_question') or 'Is it a problem?'),
                  hit['verdict'], '']
    if hit.get('when_to_ignore'):
        lines += ['**When to ignore it**', hit['when_to_ignore'], '']
    if hit.get('what_to_do'):
        lines += ['**What to do**', hit['what_to_do'], '']
    lines.append('Full write-up: %s' % hit['url'])
    return '\n'.join(lines)


def _train_for(build: tuple[int, ...], version: dict) -> tuple[str, dict] | tuple[None, None]:
    """Pick the servicing train a build belongs to.

    SQL Server ships parallel trains - CU, CU+GDR, and the RTM security (GDR) train - and they
    carry different build numbers. A box fully patched on the GDR train sits at a LOWER build
    than one on the CU train, so comparing everything against latest_cu would wrongly call it
    out of date.

    The third octet identifies the SERIES, not the individual train: on 2022 the CU train is
    16.0.4xxx and the GDR train is 16.0.1xxx, so those separate cleanly. But CU (4265) and
    CU+GDR (4262) share a series and sit a few builds apart, so nearest-match would flip
    between them on a coin toss. Within a series the CU train is the primary one, and a
    CU+GDR build is a specific point release - so prefer CU unless the build is an exact
    match for one of the others.
    """
    trains = []
    for key, label, rank in (('latest_cu', 'CU', 0), ('latest_sp', 'Service Pack', 1),
                             ('latest_cu_gdr', 'CU + GDR', 2),
                             ('latest_gdr', 'GDR (RTM security)', 3)):
        t = version.get(key)
        if t and t.get('build'):
            parsed = data.parse_build(t['build'])
            if parsed:
                trains.append((label, t, parsed, rank))
    if not trains:
        return None, None

    # An exact build match settles it outright.
    for label, t, parsed, _ in trains:
        if parsed == build:
            return label, t

    series = build[2] // 1000
    same = [x for x in trains if x[2][2] // 1000 == series]
    pool = same or trains
    pool.sort(key=lambda x: (x[3], abs(x[2][2] - build[2])))
    return pool[0][0], pool[0][1]


def _higher_in_series(build: tuple[int, ...], version: dict) -> tuple[str, dict] | None:
    """The highest build on the same series, when it is above the one given.

    Naming the train is not the same question as judging whether a server is current, and
    conflating them produced the one answer this tool must never give.

    Once a version reaches its FINAL CU, Microsoft stops shipping CUs and puts later
    security fixes out as GDR on top of that CU - so `latest_cu_gdr` keeps climbing while
    `latest_cu` stands still. On SQL 2019 the final CU is 15.0.4430.1 from February 2025
    and CU32+GDR is 15.0.4480.2 from July 2026; on 2017 the gap is closer to four years.
    That inverts the shape `_train_for` was written against (on 2022, CU is the higher of
    the two), so preferring the CU train told a box sitting anywhere between the two that
    it was UP TO DATE while it was missing 17 months of security updates.

    Those are exactly the versions still in the field on extended support, where patch
    level is the entire conversation. So whenever something higher exists on the same
    series, it gets named - the verdict is additive rather than a silent reassurance.
    """
    series = build[2] // 1000
    candidates = []
    for key, label in (('latest_cu', 'CU'), ('latest_sp', 'Service Pack'),
                       ('latest_cu_gdr', 'CU + GDR'), ('latest_gdr', 'GDR (RTM security)')):
        t = version.get(key)
        if not (t and t.get('build')):
            continue
        parsed = data.parse_build(t['build'])
        if parsed and parsed[2] // 1000 == series and parsed > build:
            candidates.append((parsed, label, t))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1], candidates[0][2]


def _freshness_note() -> str:
    """When this build data was generated, and a warning once it is old.

    Build and lifecycle data is the fastest-rotting thing in the library - a new CU can
    ship the day after an export - and this is the one tool whose pitch is "prefer this
    over what a model remembers". It was never stating its own age, so a caller had no way
    to tell a fresh answer from a stale one. A running server answers from what it loaded
    at start-up, which makes that worse, not better.
    """
    stamp = data.meta().get('generated')
    if not stamp:
        return '_Build data generation date unknown - treat CU currency with caution._'
    age = data.data_age_days()
    # Only ever states the date. Escalating past STALE_AFTER_DAYS is data.freshness_warning()'s
    # job, and it is already appended to this reply - saying it twice reads like a bug.
    if age is None:
        return '_Build data generated %s._' % stamp
    return ('_Build data generated %s (%d day%s ago). CUs ship roughly monthly, so verify '
            'against the lifecycle page if currency matters._'
            % (stamp, age, '' if age == 1 else 's'))


def _fmt_version_only(version: dict) -> str:
    """Answer a question that named a PRODUCT but gave no build.

    Deliberately does not judge patch level: no build was supplied, so there is nothing to
    compare and "you are N behind" would be invented. It answers what was actually asked -
    what the latest update is, and how long the version is supported - and says plainly
    what it would need to go further.
    """
    lines = ['## %s' % version['name'], '',
             '**Engine:** %s (%s)   **Default compatibility level:** %s'
             % (version.get('engine_version'), version.get('major_build'),
                version.get('native_compat_level')), '']

    for key, label in (('latest_cu', 'Latest cumulative update'),
                       ('latest_cu_gdr', 'Latest CU + GDR (security on top of the final CU)'),
                       ('latest_gdr', 'Latest GDR (RTM security train)'),
                       ('latest_sp', 'Latest service pack')):
        u = version.get(key)
        if not u:
            continue
        lines.append('**%s:** %s - build **%s**%s%s'
                     % (label, u.get('name') or 'update', u.get('build'),
                        ', %s' % u['kb'] if u.get('kb') else '',
                        ', released %s' % u['date'] if u.get('date') else ''))
        if u.get('kb_url'):
            lines.append('Download: %s' % u['kb_url'])
    lines.append('')

    status = (version.get('support_status') or '').lower()
    if status == 'out of support':
        lines.append('**Support: OUT OF SUPPORT.** Extended support ended %s. No security '
                     'updates without ESU.' % version.get('extended_end'))
    else:
        lines.append('**Support:** %s. Mainstream ends %s, extended ends %s.'
                     % (version.get('support_status'), version.get('mainstream_end'),
                        version.get('extended_end')))
    if version.get('notes'):
        lines += ['', version['notes']]
    if version.get('servicing'):
        lines += ['', '**Servicing:** %s' % version['servicing']]

    lines += ['',
              '_No build number was given, so this does not say how far behind any '
              'particular server is. Paste `SELECT @@VERSION` or a build like %s for that._'
              % ((version.get('latest_cu') or {}).get('build') or '16.0.4265.3'),
              '',
              _freshness_note(), '',
              'Full version and lifecycle table: %s' % version.get('url')]
    return '\n'.join(lines)


def check_build(build: str) -> str:
    """Identify a SQL Server build number and say whether it is current and still supported."""
    parsed = data.parse_build(build)
    if not parsed:
        # No four-part build, but the question may still name a product. "we are on sql
        # 2016, when do we lose support" and "whats the latest version of sql for 2017"
        # were both refused while builds.json held every part of the answer, and the
        # refusal was circular: the build being asked for was the price of asking.
        named = data.version_for_name(build)
        if named:
            return _fmt_version_only(named)
        return ("I could not find a build number or a SQL Server version in that. Paste "
                "the output of `SELECT @@VERSION`, a build like 16.0.4265.3, or just the "
                "version, e.g. 'SQL Server 2019'.")

    version = data.version_for_engine(parsed[0])
    if not version:
        return ("Build %s does not match a SQL Server version in the library "
                "(engine major %s).\n\n%s"
                % ('.'.join(str(p) for p in parsed), parsed[0], NOT_COVERED))

    lines = ['## %s' % version['name'], '',
             '**You gave:** %s' % '.'.join(str(p) for p in parsed),
             '**Engine:** %s (%s)   **Default compatibility level:** %s'
             % (version.get('engine_version'), version.get('major_build'),
                version.get('native_compat_level')), '']

    # Name the build before judging it. "Are you patched" is only half the question a DBA
    # holding an unfamiliar @@VERSION has; the other half is "what IS this", and that is
    # the half a model will otherwise answer from memory.
    exact = data.identify_build(version, parsed)
    if exact:
        lines.append('**This build is:** %s%s, released %s.'
                     % (exact.get('name') or 'an update',
                        ' (%s)' % exact['kb'] if exact.get('kb') else '',
                        exact.get('date') or 'date not published'))
        if exact.get('kb_url'):
            lines.append('Details: %s' % exact['kb_url'])
        lines.append('')
    else:
        below, above = data.bracket_build(version, parsed)
        if below or above:
            span = []
            if below:
                span.append('above %s (%s, %s)'
                            % (below.get('name'), below['build'], below.get('date')))
            if above:
                span.append('below %s (%s, %s)'
                            % (above.get('name'), above['build'], above.get('date')))
            lines += ['**This build is not one Microsoft published publicly.** It sits %s '
                      '- most likely an on-demand hotfix issued between them. Treat the '
                      'lower one as your effective patch level.' % ' and '.join(span), '']

    label, train = _train_for(parsed, version)
    if train:
        latest = data.parse_build(train['build'])
        lines.append('**Servicing train assumed:** %s - check this is the train you are on.'
                     % label)
        higher = _higher_in_series(parsed, version)
        if higher and higher[1].get('build') == train.get('build'):
            higher = None

        if latest and parsed >= latest:
            # "UP TO DATE" must not be the headline when something higher exists on the
            # same series - an agent summarising this will carry the first bold phrase and
            # drop the qualifier underneath it.
            if higher:
                lines.append('**Patch level:** up to date on this train (%s, %s), but '
                             '**NOT the highest build on this series** - see below.'
                             % (train.get('name'), train['build']))
            else:
                lines.append('**Patch level:** UP TO DATE on this train (%s, %s).'
                             % (train.get('name'), train['build']))
        elif latest:
            lines.append('**Patch level:** BEHIND. Latest on this train is **%s** (%s, released %s).'
                         % (train.get('name'), train['build'], train.get('date')))
            # How far behind, counted from the published ladder rather than described
            # vaguely. Only when the build was identified exactly: counting from a build
            # whose train is a guess would put a specific-sounding number on an assumption.
            if exact and exact.get('train'):
                missed = data.newer_on_train(version, parsed, exact['train'])
                if missed:
                    oldest = missed[-1]
                    lines.append('That is **%d %s update(s) behind** on this train, the '
                                 'earliest of which shipped %s.'
                                 % (len(missed), exact['train'], oldest.get('date')))
            if train.get('kb_url'):
                lines.append('Download: %s (%s)' % (train['kb_url'], train.get('kb')))

        # Being current on your train is not the same as being current. See _higher_in_series.
        if higher:
            hlabel, ht = higher
            why = ('After the final CU, later security fixes ship as GDR on top of it, so '
                   'a server sitting past the last CU can still be missing them.'
                   if 'GDR' in hlabel else
                   'A newer cumulative update has shipped since that build.')
            lines.append('**Higher build on this series:** %s is **%s** (released %s). %s '
                         'Confirm which line you are on before treating this server as '
                         'patched.' % (hlabel, ht['build'], ht.get('date'), why))
            if ht.get('kb_url'):
                lines.append('Download: %s (%s)' % (ht['kb_url'], ht.get('kb')))
        lines.append('')

    status = (version.get('support_status') or '').replace('_', ' ')
    if status == 'out of support':
        lines.append('**Support: OUT OF SUPPORT.** Extended support ended %s. No security '
                     'updates without ESU.' % version.get('extended_end'))
    else:
        lines.append('**Support:** %s. Mainstream ends %s, extended ends %s.'
                     % (status or 'unknown', version.get('mainstream_end'),
                        version.get('extended_end')))
    if version.get('notes'):
        lines += ['', version['notes']]
    lines += ['', _freshness_note(), '',
              'Full version and lifecycle table: %s' % version['url']]
    # Build data ages badly. The server volunteers this rather than waiting to be asked.
    return '\n'.join(lines) + data.freshness_warning()


# --- scripts --------------------------------------------------------------------------

def _safety(s: dict) -> str:
    """The class line, worded the way the script's own header words it."""
    label = 'RiskLevel' if s.get('language') == 'powershell' else 'SAFE'
    out = '%s: %s' % (label, s['safe']) if s.get('safe') else ''
    if s.get('impact'):
        out += '   IMPACT: %s' % s['impact']
    if out and s.get('safety_note'):
        out += ' - %s' % s['safety_note']
    return out or 'safety class not stated'


def _warning(s: dict) -> str | None:
    """A loud line for anything that changes a server, or that nobody classified.

    The class was already present in every response - as `SAFE: WritesData   IMPACT: High`,
    carrying exactly the same visual weight as the line below it that says `path:`. That is
    a label, not a warning. An agent summarising a tool result leads with whatever is
    loudest in it, so the sentence a DBA must not miss has to BE the loudest, and it has to
    come before the body rather than after the purpose.

    Returns None for read-only scripts: 189 of 230 are read-only, and a warning on all of
    them is a warning on none of them.
    """
    if s.get('read_only') is None:
        return ("**UNCLASSIFIED - this script's header states no safety class.** Treat it "
                "as unsafe until you have read it in full.")
    if s['read_only']:
        return None
    bits = ['**NOT READ-ONLY - %s.' % (s.get('safe') or 'class not recognised')]
    if s.get('impact'):
        bits.append(' Impact: %s.' % s['impact'])
    bits.append('** This changes the server.')
    if s.get('safety_note'):
        bits.append(' %s.' % s['safety_note'].rstrip('.'))
    bits.append(' Read the header and confirm the target before running it on production.')
    return ''.join(bits)


# A DBA asking a question wants to SEE, not to change. "give me a script to find blocking"
# led with `Create-BlockingScenario` - a lab script that CREATES blocking - and "orphaned
# users" led with `Fix-OrphanedUsers`. Both are near-ties on wording, and on a near-tie the
# read-only script is both the better answer and the safer one. The nudge is small enough
# that a clearly better match still wins, and it is switched off entirely when the query
# actually asks for an action.
_ACTION_WORDS = {'fix', 'kill', 'create', 'generate', 'rebuild', 'drop', 'delete', 'set',
                 'change', 'apply', 'install', 'uninstall', 'patch', 'restore', 'shrink',
                 'enable', 'disable', 'add', 'remove', 'update', 'configure', 'make',
                 'build', 'restart', 'reboot', 'deploy', 'provision'}


def _prefer_reading(query: str, hits: list) -> list:
    """Withhold the 14 scripts that change a server unless the question asked to change one.

    This used to multiply their score by 0.8, which is a preference, not a guarantee - and
    a preference is not enough here. "is my sql server ok" returned an eight-script list
    with `uninstall-sql` in it ("removes a SQL Server instance and can delete its data
    directories"), alongside Patch-SqlServer and configure-sql. The reply did label each
    one NOT READ-ONLY, and that labelling is good, but a beginner's health question should
    never have surfaced them at all.

    So: no action word in the question, no server-changing script in the answer. Asking to
    install, patch, kill, uninstall or create still returns exactly what it always did -
    "create test databases" still leads with New-TestDatabases and its HIGH IMPACT
    warning. The cost of being wrong in this direction is a script a DBA runs.
    """
    if any(t in _ACTION_WORDS for t in data.tokens(query)):
        return hits
    return [(record, score) for record, score in hits if record.get('read_only') is not False]


def find_script(task: str) -> str:
    """Find a script in the dba-tools library by what you are trying to do."""
    term = (task or '').strip()
    if not term:
        return ("Describe the task, e.g. 'find blocking chains', 'check backup coverage', "
                "'list missing indexes'.")

    # Strip the ask before scoring it. "show me who has sysadmin" and "sysadmin members"
    # are the same question, and only one of them used to work.
    cleaned, is_browse = data.normalise_script_query(term)
    if is_browse:
        return (
            "That is a request for a curated list rather than a search, and this library "
            "cannot rank one honestly - it carries no usage or popularity data, so any "
            "'top 10' would be whatever scored highest on the word 'top'.\n\n"
            "Browse the full catalogue instead: https://sqldba.blog/scripts/\n\n"
            "Or describe the task and it will find the script: 'find blocking chains', "
            "'check backup coverage', 'last time checkdb ran'."
        )

    hits = data.script_index().search(cleaned or term, limit=8, min_coverage=0.34)
    hits = _prefer_reading(cleaned or term, hits)
    if not hits:
        return ("Nothing in the dba-tools library matches that.\n\n"
                "The library is 183 SQL scripts plus PowerShell orchestrators, covering "
                "inventory, monitoring, performance, backups, security, HA and migration. "
                "Browse: https://sqldba.blog/scripts/")

    lines = ['Found %d script(s) for "%s":' % (len(hits), term), '']
    for s, _score in hits:
        lines.append('### %s' % s['name'])
        warn = _warning(s)
        if warn:
            lines.append(warn)
        if s.get('purpose'):
            lines.append(s['purpose'])
        meta_bits = [_safety(s), 'path: `%s`' % s['path']]
        if s.get('requires'):
            meta_bits.insert(1, 'requires: %s' % s['requires'])
        if s.get('health_check'):
            meta_bits.append('part of the health check suite')
        lines.append('  \n'.join(meta_bits))
        if s.get('url'):
            lines.append('Write-up: %s' % s['url'])
        else:
            # 89 of 232 scripts have no post yet. Omitting the line silently made an
            # uncited answer look identical to a cited one, against a README promising a
            # source on every answer - and left a caller unable to tell "no source" from
            # "source withheld". lookup_error has said this plainly since day one; there
            # was no reason for find_script to be quieter about the same gap. The script
            # body itself is still verbatim and still quotable.
            lines.append('_No write-up published for this script yet - the body and '
                         'safety class above are from the repo, but there is no article '
                         'to cite._')
        lines.append('')
    lines.append('Call `get_script` with an exact name for the full body.')
    lines.append('')
    lines.append('**Check the safety class before running anything.** `SAFE: ReadOnly` is '
                 'safe to run on production; `WritesData` or `CreatesObjects` changes the '
                 'server, and `IMPACT: High` means it can be expensive on a busy instance.')
    return '\n'.join(lines)


def get_script(name: str) -> str:
    """Return the full verbatim body of a named script."""
    want = (name or '').strip()
    if not want:
        return "Give me a script name, e.g. Get-BlockingChains."

    wl = want.lower()
    exact = [s for s in data.scripts() if s['name'].lower() == wl]
    if not exact:
        exact = [s for s in data.scripts()
                 if pathlib_stem(s['path']).lower() == wl or s['path'].lower() == wl]

    if not exact:
        near = data.script_index().search(want, limit=6)
        if not near:
            return ("No script called %r. Use `find_script` to search by task."
                    % want)
        lines = ['No script is named exactly %r. Did you mean:' % want, '']
        for s, _ in near:
            lines.append('- **%s** (`%s`)' % (s['name'], s['path']))
        lines.append('')
        lines.append('Call `get_script` again with one of these exact names.')
        return '\n'.join(lines)

    if len(exact) > 1:
        # Never guess which of several same-named scripts was meant.
        lines = ['%d scripts share the name %r:' % (len(exact), want), '']
        for s in exact:
            lines.append('- `%s` - %s' % (s['path'], s.get('purpose') or 'no purpose stated'))
        lines.append('')
        lines.append('Call `get_script` again with the full path to pick one.')
        return '\n'.join(lines)

    s = exact[0]
    fence = 'sql' if s['language'] == 'sql' else 'powershell'
    lines = ['## %s' % s['name'], '']
    # Before the purpose, and a long way before the body. See _warning.
    warn = _warning(s)
    if warn:
        lines += [warn, '']
    if s.get('purpose'):
        lines += [s['purpose'], '']
    lines.append('%s   \npath: `%s`' % (_safety(s), s['path']))
    if s.get('requires'):
        lines.append('requires: %s' % s['requires'])
    lines += ['', '```%s' % fence, s['body'].rstrip(), '```']
    if s.get('url'):
        lines += ['', 'Write-up with example output: %s' % s['url']]
    return '\n'.join(lines)


def health_triage_prompt() -> str:
    """The health-check triage rubric, shipped as a reusable prompt."""
    prompts = data.prompts()
    hit = next((p for p in prompts if p['name'] == 'sql-server-health-triage'), None)
    if not hit:
        return 'The triage rubric is not bundled in this build.'
    return (
        "Triage a SQL Server using the rubric below. It is a working DBA's own "
        "methodology: what to flag, at what threshold, and in what order of severity.\n\n"
        "Work through it in order, report CRITICAL findings first, and say explicitly "
        "when you do not have the data to judge a section rather than assuming it is "
        "healthy.\n\n---\n\n" + hit['body'].rstrip() +
        "\n\n---\n\nSource: %s in the dba-tools repo (https://sqldba.blog/scripts/)."
        % hit['source']
    )


def pathlib_stem(p: str) -> str:
    base = p.rsplit('/', 1)[-1]
    return base.rsplit('.', 1)[0] if '.' in base else base


# --- FAQ ------------------------------------------------------------------------------

# A question that asks for a PROCEDURE. The FAQ corpus is 4.7% "how do I" and 61%
# why/what/does/is, so a procedural question almost never has a pair written for it and
# lands on the nearest explanatory one instead - which is how "how do i update ssms"
# came back "Do I need administrator rights?". Kept deliberately tight: "what do I do"
# and "what should I look at first" are advisory, not procedural, and their pairs ARE
# the answer.
_PROCEDURAL = re.compile(r'^\s*(how do i|how to|how can i|how would i|how does one)', re.I)

# A pair that answers a procedure itself. If the pair is procedural too, it is the answer.
_PAIR_PROCEDURAL = re.compile(r'^\s*(how do i|how to|how can i|how would i)', re.I)


def _overlap(query: str, text: str) -> float:
    """Share of the QUESTION's information that `text` carries, idf-weighted.

    Weighted, because "sql" and "server" appear in half the corpus and matching them
    means nothing, while "ssms" or "sid" is the whole question.
    """
    idx = data.faq_index()
    q = set(data.tokens(query))
    if not q:
        return 0.0
    # A term the corpus has never seen counts AGAINST the score, at the weight of the most
    # informative term present. Scoring only the known terms made a question that is mostly
    # foreign vocabulary look like a strong match on the little that was familiar: "what is
    # the best sql server book" scored 1.0 against "SQL Server Kerberos vs NTLM", because
    # `book` contributed nothing to the denominator and `sql`+`server` were all that was
    # left. The unknown words are exactly what makes it a different question.
    known = {t: idx._idf.get(t, 0.0) for t in q}
    ceiling = max([v for v in known.values() if v] or [1.0])
    total = sum(v if v else ceiling for v in known.values())
    if total <= 0:
        return 0.0
    hit = sum(known[t] for t in q & set(data.tokens(text or '')) if known[t])
    return hit / total


def _lead_with_post(question: str, pair: dict) -> bool:
    """Should the reply name the POST, rather than quote this pair as the answer?

    Two independent triggers, both measured against the four questions that exposed this
    (update SSMS / 2022 Standard compression / get a login SID / check free space) and
    against four controls where the pair genuinely IS the answer and must not change
    ("is shrinking a database ever OK", "should I add a second data file to TempDB").

      1. The post title carries MORE of the question than the pair does. The ranker
         already found the right post; the pair it picked is simply not what was asked.
      2. The question asks for a procedure and the pair does not answer one, while the
         post is still on topic. This is the 4.7%-vs-61% mismatch.

    This never suppresses a pair - the pair is still shown, labelled as a related note -
    and it never lowers the bar for what counts as an answer: min_coverage is untouched,
    so a question with no good match still gets "nothing matches".
    """
    post_title = pair.get('post_title') or ''
    if not post_title:
        return False
    post_cov = _overlap(question, post_title)
    pair_cov = _overlap(question, pair['question'])
    if post_cov > pair_cov:
        return True
    return (post_cov >= 0.25
            and _PROCEDURAL.match(question or '')
            and not _PAIR_PROCEDURAL.match(pair['question'] or ''))


def answer_question(question: str) -> str:
    """Answer a how/why/should-I question from Peter's published FAQ answers."""
    q = (question or '').strip()
    if not q:
        return "Ask a question, e.g. 'should I add a second data file?'"

    # Coverage floor: a single shared term is not an answer. See Index.search.
    hits = data.faq_index().search(q, limit=4, min_coverage=0.5)
    cleared_floor = {id(h[0]) for h in hits}   # survived the COVERAGE floor

    # THE ANSWER MUST HAVE SOMETHING TO DO WITH THE QUESTION.
    #
    # min_coverage is computed against the whole record - question, post title and answer
    # body - so a pair can clear it on words that appear only deep in its answer and still
    # be about something else entirely. Measured against the off-domain set, four of the
    # eight questions this tool answered wrongly shared NOTHING with the pair it picked:
    #
    #     how do I set up replication           -> "Where do I find the deadlock graph?"
    #     how do I use Dapper with stored procs -> "How is this different from Top CPU Queries?"
    #
    # Requiring one informative term in common between the question ASKED and the question
    # ANSWERED is the weakest floor available, and weak is deliberate. The real questions
    # that must keep working go as low as 0.16 ("does sql server 2022 standard edition have
    # compression available" -> "Why does edition matter more than version?"), while wrong
    # answers reach 0.54, so no threshold above zero separates them. That was measured, not
    # assumed. Zero is the only honest line: an answer with no word in common with the
    # question is not a worse answer, it is a different subject.
    # Applied as a FILTER, not just a gate on the top hit, because a zero-overlap record can
    # outrank a real answer rather than merely replace it. "my log file keeps growing what do
    # I do" put "How is this different from reading actual autogrowth events?" (0.00) and
    # "Should TempDB autogrowth be a percentage or a fixed size?" (0.00) above "Why does my
    # transaction log keep growing even with regular full backups?" (0.50). Dropping the
    # zero-overlap rows promotes the answer that was there all along; BM25 order is untouched
    # among what survives.
    # ...but only among records BM25 already rated close to the best. Filtering the whole
    # list let an off-domain question reach far down it for anything with a word in common,
    # which cost more honesty than the promotion gained: 27/30 fell to 25/30. If the only
    # on-topic record is one the ranker put well below the top, that is the corpus saying it
    # does not really cover this. 0.85 keeps the transaction-log answer (10.59 against a top
    # of 11.37, 93%) and refuses the distant rescues.
    # ...and OVERRIDING the ranker costs more evidence than accepting it. Rank 1 passes on
    # any word in common. Promoting a lower-ranked record over BM25's own choice has to be
    # clearly on topic, because that is where an off-domain question goes fishing:
    #
    #     which sql server certification should I take   rank 2, overlap 0.20   refuse
    #     how do I renew a windows domain certificate    rank 3, overlap 0.22   refuse
    #     my log file keeps growing what do I do         rank 3, overlap 0.50   promote
    #
    # 0.35 sits in that gap. It is tuned on the cases above rather than derived, which is
    # worth knowing if it ever needs moving; the shape of the rule is the durable part.
    if hits:
        hits = [h for i, h in enumerate(hits)
                if _overlap(q, h[0].get('question') or '') > (0 if i == 0 else 0.35)]

    # WHEN THE FLOOR REMOVES THE BEST ANSWER, NAME ITS POST - do not serve the runner-up
    # from somewhere else.
    #
    # "how do i update ssms to latest version" ranked "Do I need administrator rights to
    # install or update SSMS?" first at 12.22, from the post Install and Update SSMS. The
    # coverage floor dropped it at 0.47, because "latest" is a real corpus term that pair
    # does not contain, and what survived was a pair at 10.25 from a post about the error
    # log. The tool had the right article and answered from the wrong one.
    #
    # Scoped to records the COVERAGE FLOOR removed, not ones the overlap filter
    # removed below - that filter drops zero-overlap records on purpose, and
    # rescuing those undid the transaction-log promotion it exists to make.
    # This CANNOT cost honesty, by construction: it only runs when `hits` is already
    # non-empty, so the tool was going to answer regardless. It changes which post gets
    # named, never whether one does.
    unfiltered = data.faq_index().search(q, limit=1)
    if hits and unfiltered and id(unfiltered[0][0]) not in cleared_floor:
        top_pair = unfiltered[0][0]
        if top_pair.get('url') != hits[0][0].get('url'):
            out = ['This is covered in **%s**'
                   % (top_pair.get('post_title') or top_pair['url']), top_pair['url'], '',
                   'The closest question-and-answer pair here answers a detail of it '
                   'rather than the question you asked:', '',
                   '- **%s**  %s' % (top_pair['question'], top_pair['url'])]
            return '\n'.join(out)

    # The post index runs regardless, not only as a fallback, because it answers a
    # different question from the FAQ tier: "which post is this ABOUT", not "which pair
    # shares words with the wording used". Consulted for both uses below.
    covering = data.post_index().search(q, limit=3, min_coverage=0.6)

    # A TITLE MATCH BEATS A PAIR FROM AN UNRELATED POST.
    #
    # "how do i update ssms to latest version" ranked "Do I need administrator rights to
    # install or update SSMS?" top at 12.22 - right post, wrong entry - and the coverage
    # floor then dropped it at 0.47, because "latest" is a real corpus term that pair does
    # not contain. What survived was "How do I read the SQL Server error log without
    # SSMS?" at 10.25, from a post about the error log. Loosening the floor to rescue the
    # first would let much worse through, so the floor is not the thing to change.
    #
    # A Q&A pair is scored on words; a title states a subject. When the post index is
    # confident - its own higher floor - and names a DIFFERENT post from the one the
    # surviving pair belongs to, the pair is the weaker evidence: it survived on
    # vocabulary borrowed from an article about something else.
    # ...but ONLY when the pair is not already being presented AS its post. If
    # _lead_with_post is true the tool is about to say "this is covered in <post>"
    # using the pair's own article, which is the same answer by a different route -
    # overriding that swapped a correct citation on "how do i get the sid of a sql
    # login" for a different post entirely.
    if (hits and covering and not _lead_with_post(q, hits[0][0])
            and covering[0][0]['url'] != hits[0][0].get('url')):
        top = covering[0][0]
        out = ['This is covered in **%s**' % top['title'], top['url']]
        if top.get('lead'):
            out += ['', top['lead']]
        pair = hits[0][0]
        out += ['', 'The closest question-and-answer pair here is from a different post, '
                    'so it is a related note rather than the answer:', '',
                '- **%s**%s  %s' % (pair['question'],
                                    ' (in: %s)' % pair['post_title']
                                    if pair.get('post_title') else '', pair['url'])]
        return '\n'.join(out)


    if not hits:
        # NOTHING MATCHED A Q&A PAIR. That is not the same as "the site does not cover
        # this", and until 2026-08-20 it was treated as if it were.
        #
        # The FAQ corpus is built from `<details>` accordions, and an accordion is an
        # addendum: it answers a post's leftover questions, never its main subject.
        # Measured against live: 319 of 489 published posts carry no accordion at all,
        # and 74 had no record of any kind in this server. Asking "how do I update SSMS"
        # could not reach the post titled *Install and Update SSMS* - not because it
        # ranked badly, but because the post was not in the index.
        #
        # A title IS the post stating its own subject. So before refusing, ask the post
        # index. The floor is the FAQ's own, not a lower one: this widens WHAT can be
        # found, and must not widen what counts as a match. If it still finds nothing,
        # the refusal below is now worth something, because it means both.
        # 0.6, ABOVE the FAQ tier's 0.5, and the gap is the point: this path overturns a
        # refusal, and overturning one has to cost more evidence than accepting a match -
        # the same rule already applied to promoting a lower-ranked FAQ pair. Measured
        # 0.55/0.60/0.65/0.70 and they behave identically on the suite, so this is the
        # middle of a plateau rather than a value tuned to the probes.
        if covering:
            top = covering[0][0]
            lines = ['This is covered in **%s**' % top['title'], top['url']]
            if top.get('lead'):
                lines += ['', top['lead']]
            lines += ['', '_No question-and-answer pair on this site matches your wording, '
                          'so that is the post rather than a quoted answer._']
            rest = [c for c, _ in covering[1:]]
            if rest:
                lines += ['', 'Also on this topic:']
                lines += ['- %s  %s' % (c['title'], c['url']) for c in rest]
            return '\n'.join(lines)

        return ("Nothing on sqldba.blog matches that.\n\n"
                "This covers %d questions answered across %d published posts. For a "
                "specific error number use `lookup_error`, for a wait type use "
                "`explain_wait`, for a build number use `check_build`, and to find a "
                "script use `find_script`." % (len(data.faqs()), len(data.posts())))

    best = hits[0][0]
    if _lead_with_post(q, best):
        lines = ['This is covered in **%s**' % (best.get('post_title') or best['url']),
                 best['url'], '',
                 'Related note from that post: **%s**' % best['question'], '',
                 best['answer']]
        others = [h for h, _ in hits[1:3]]
        if others:
            lines += ['', 'Also answered on this topic:']
            for o in others:
                title = o.get('post_title')
                lines.append('- %s%s  %s'
                             % (o['question'], ' (in: %s)' % title if title else '', o['url']))
        return '\n'.join(lines)

    # Name the article the answer came from, above the answer itself.
    #
    # Many of these questions are only meaningful inside their own post. "How long before
    # the window should Phase 0 run?" has no referent until you know it concerns the
    # standalone migration runbook, and "Days, not hours" quoted bare reads as a general
    # rule about SQL Server rather than one step of one runbook. The post title was always
    # in the record and simply was not rendered, so an agent had no way to qualify what it
    # was repeating. Front it, because a caller that truncates keeps the top.
    lines = ['**%s**' % best['question'], '',
             'Answered in: %s' % (best.get('post_title') or best['url']), '',
             best['answer'], '',
             'Full post: %s' % best['url']]

    others = [h for h, _ in hits[1:3]]
    if others:
        # Same reasoning: a bare related question is an invitation to quote it out of
        # context, and these are the ones the reader has NOT seen the answer to.
        lines += ['', 'Related questions answered:']
        for o in others:
            title = o.get('post_title')
            lines.append('- %s%s  %s'
                         % (o['question'], ' (in: %s)' % title if title else '', o['url']))
    return '\n'.join(lines)
