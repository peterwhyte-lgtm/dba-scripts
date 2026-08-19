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
    if e.get('url'):
        lines.append('Full write-up: %s' % e['url'])
    else:
        # 22 of the 47 errors have no post yet. Omitting the line silently made a verified
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
        lines += ['**Is it a problem?**', hit['verdict'], '']
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


def check_build(build: str) -> str:
    """Identify a SQL Server build number and say whether it is current and still supported."""
    parsed = data.parse_build(build)
    if not parsed:
        return ("I could not find a build number in that. Paste the output of "
                "`SELECT @@VERSION` or just the number, e.g. 16.0.4265.3.")

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
    lines += ['', 'Full version and lifecycle table: %s' % version['url']]
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
                 'change', 'apply', 'install', 'patch', 'restore', 'shrink', 'enable',
                 'disable', 'add', 'remove', 'update', 'configure', 'make', 'build'}


def _prefer_reading(query: str, hits: list) -> list:
    """Break near-ties toward the script that only reads."""
    if any(t in _ACTION_WORDS for t in data.tokens(query)):
        return hits
    adjusted = [(record, score * (1.0 if record.get('read_only') is not False else 0.80))
                for record, score in hits]
    adjusted.sort(key=lambda pair: -pair[1])
    return adjusted


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

def answer_question(question: str) -> str:
    """Answer a how/why/should-I question from Peter's published FAQ answers."""
    q = (question or '').strip()
    if not q:
        return "Ask a question, e.g. 'should I add a second data file?'"

    # Coverage floor: a single shared term is not an answer. See Index.search.
    hits = data.faq_index().search(q, limit=4, min_coverage=0.5)
    if not hits:
        return ("Nothing in the published FAQ answers matches that.\n\n"
                "This covers %d questions answered across sqldba.blog. For a specific "
                "error number use `lookup_error`, for a wait type use `explain_wait`, "
                "for a build number use `check_build`, and to find a script use "
                "`find_script`." % len(data.faqs()))

    best = hits[0][0]
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
