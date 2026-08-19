#!/usr/bin/env python3
"""Replace en/em dashes inside script OUTPUT strings with a plain hyphen.

WHY
---
Running Get-BackupChainIntegrity against a real instance on 2026-08-19 printed:

    WARN <mojibake> FULL recovery model but no log backups since last full

The script emits 'WARN - ...' with an em-dash. SSMS is Unicode and renders it fine;
sqlcmd on a cp1252 console does not, and a DBA reading a status column sees mojibake in
the middle of a warning. It also runs against the house rule that body prose uses commas
and full stops rather than dashes.

SCOPE, deliberately narrow
--------------------------
Only characters INSIDE a quoted string literal are touched, because those are what the
script prints. Comments and header blocks are left alone: those are prose that renders in
the blog post, and rewriting them is a content decision rather than a defect fix.

Detection is quote-aware rather than line-wide. SQL and PowerShell have no syntactic use
for an en/em dash, so a blunt replace would probably be safe, but "probably safe" across
81 files in a public repo is not a standard worth adopting.

    python tools/maintenance/Fix-DashesInScriptOutput.py           # dry run
    python tools/maintenance/Fix-DashesInScriptOutput.py --apply
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APPLY = '--apply' in sys.argv
DASHES = {'—': '-', '–': '-'}


def fix_line(line: str) -> tuple[str, int]:
    """Replace dashes that sit inside a single- or double-quoted literal."""
    out, n = [], 0
    in_s = in_d = False
    for ch in line:
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        if ch in DASHES and (in_s or in_d):
            out.append(DASHES[ch])
            n += 1
        else:
            out.append(ch)
    return ''.join(out), n


def is_comment(line: str) -> bool:
    s = line.lstrip()
    return s.startswith('--') or s.startswith('#') or s.startswith('*') or s.startswith('/*')


def main():
    targets = sorted(list((ROOT / 'sql').rglob('*.sql')) +
                     list((ROOT / 'powershell').rglob('*.ps1')))
    changed, total = [], 0
    for f in targets:
        try:
            text = f.read_text(encoding='utf-8')
        except UnicodeDecodeError:
            print('  SKIP (not utf-8) %s' % f.relative_to(ROOT))
            continue
        lines, hits = text.splitlines(keepends=True), 0
        for i, line in enumerate(lines):
            if is_comment(line):
                continue
            new, n = fix_line(line)
            if n:
                lines[i] = new
                hits += n
        if hits:
            changed.append((f, hits))
            total += hits
            if APPLY:
                f.write_text(''.join(lines), encoding='utf-8')

    for f, n in changed:
        print('  %-72s %d' % (str(f.relative_to(ROOT)).replace('\\', '/'), n))
    print('\n%d dash(es) in output strings across %d file(s)%s'
          % (total, len(changed), '' if APPLY else ' - dry run, nothing written'))
    if not APPLY and changed:
        print('Re-run with --apply to fix. Comments and header blocks are untouched.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
