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
    if e.get('url'):
        lines.append('')
        lines.append('Full write-up: %s' % e['url'])
    return '\n'.join(lines)


def lookup_error(error: str) -> str:
    """Look up a SQL Server error by number ('18456') or by phrase ('login failed')."""
    term = (error or '').strip()
    if not term:
        return "Give me an error number (e.g. 18456) or a phrase from the message."

    digits = ''.join(ch for ch in term if ch.isdigit())
    if digits and digits == term.replace(' ', ''):
        hit = data.errors_by_number().get(int(digits))
        if hit:
            return _fmt_error(hit)
        return (
            "Error %s is not in the library yet.\n\n%s" % (digits, NOT_COVERED)
        )

    hits = data.search_errors(term)
    if not hits:
        return NOT_COVERED
    if len(hits) == 1:
        return _fmt_error(hits[0])

    out = ['Found %d matching errors:' % len(hits), '']
    for e in hits:
        num = e['error_number']
        out.append('- **%s** - %s   %s' % (num if num is not None else '(no number)',
                                           e['title'], e.get('url') or ''))
    out.append('')
    out.append('Ask again with a number for the full entry.')
    return '\n'.join(out)


def explain_wait(wait_type: str) -> str:
    """Explain a SQL Server wait type and say whether it is worth chasing."""
    name = data.normalise_wait(wait_type)
    if not name:
        return "Give me a wait type, e.g. PAGEIOLATCH_SH or CXPACKET."

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

    label, train = _train_for(parsed, version)
    if train:
        latest = data.parse_build(train['build'])
        lines.append('**Servicing train assumed:** %s - check this is the train you are on.'
                     % label)
        if latest and parsed >= latest:
            lines.append('**Patch level:** UP TO DATE on this train (%s, %s).'
                         % (train.get('name'), train['build']))
        elif latest:
            lines.append('**Patch level:** BEHIND. Latest on this train is **%s** (%s, released %s).'
                         % (train.get('name'), train['build'], train.get('date')))
            if train.get('kb_url'):
                lines.append('Download: %s (%s)' % (train['kb_url'], train.get('kb')))
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
    return '\n'.join(lines)
