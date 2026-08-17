"""Bundled dataset loading and indexing.

The data ships with the package as plain JSON. Nothing here touches the network, a database,
or the filesystem outside the package directory, so the server works on an air-gapped box.

The datasets are generated from sqldba.blog and the dba-tools script library; each record
carries the URL of its full write-up. See data/_meta.json for provenance.
"""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent / 'datasets'


def _load(name: str):
    path = DATA_DIR / ('%s.json' % name)
    if not path.exists():
        raise FileNotFoundError(
            'Bundled dataset %s is missing (looked in %s). The package was built '
            'incorrectly; reinstall it.' % (path.name, DATA_DIR)
        )
    return json.loads(path.read_text(encoding='utf-8'))


@lru_cache(maxsize=1)
def errors() -> list[dict]:
    return _load('errors')


@lru_cache(maxsize=1)
def waits() -> list[dict]:
    return _load('waits')


@lru_cache(maxsize=1)
def builds() -> dict:
    return _load('builds')


@lru_cache(maxsize=1)
def meta() -> dict:
    return _load('_meta')


# --- indexes ------------------------------------------------------------------------------

@lru_cache(maxsize=1)
def errors_by_number() -> dict[int, dict]:
    return {e['error_number']: e for e in errors() if e['error_number'] is not None}


@lru_cache(maxsize=1)
def waits_by_type() -> dict[str, dict]:
    """One entry per wait type. A post covering several waits is indexed under each."""
    idx: dict[str, dict] = {}
    for w in waits():
        for name in w['wait_types']:
            idx[name.upper()] = w
    return idx


def normalise_wait(name: str) -> str:
    """Accept the sloppy forms a DBA actually pastes: lowercase, spaces, trailing colons."""
    return re.sub(r'[^A-Z0-9_]', '', (name or '').strip().upper().replace(' ', '_'))


def search_errors(term: str, limit: int = 8) -> list[dict]:
    """Free-text search over title, message and meaning."""
    t = (term or '').strip().lower()
    if not t:
        return []
    hits = []
    for e in errors():
        blob = ' '.join(str(e.get(k) or '') for k in ('title', 'message', 'meaning', 'category'))
        if t in blob.lower():
            hits.append(e)
    return hits[:limit]


def search_waits(term: str, limit: int = 8) -> list[dict]:
    t = normalise_wait(term)
    if not t:
        return []
    idx = waits_by_type()
    hits = [w for name, w in idx.items() if t in name]
    seen, out = set(), []
    for w in hits:
        key = w['url']
        if key not in seen:
            seen.add(key)
            out.append(w)
    return out[:limit]


# --- build numbers ------------------------------------------------------------------------

BUILD_RE = re.compile(r'(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')


def parse_build(s: str) -> tuple[int, ...] | None:
    """'16.0.4265.3' -> (16, 0, 4265, 3). Tolerates surrounding text like @@VERSION output."""
    m = BUILD_RE.search(s or '')
    if not m:
        return None
    parts = [int(g) for g in m.groups() if g is not None]
    while len(parts) < 4:
        parts.append(0)
    return tuple(parts)


def version_for_engine(engine: int) -> dict | None:
    for v in builds()['versions']:
        if v.get('engine_version') == engine:
            return v
    return None
