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


@lru_cache(maxsize=1)
def faqs() -> list[dict]:
    return _load('faqs')


@lru_cache(maxsize=1)
def scripts() -> list[dict]:
    return _load('scripts')


@lru_cache(maxsize=1)
def docs() -> list[dict]:
    return _load('docs')


@lru_cache(maxsize=1)
def prompts() -> list[dict]:
    return _load('prompts')


# --- freshness ----------------------------------------------------------------------------

STALE_AFTER_DAYS = 90


def data_age_days() -> int | None:
    """Days since the datasets were generated, or None if the stamp is unreadable."""
    import datetime
    stamp = meta().get('generated')
    if not stamp:
        return None
    try:
        gen = datetime.date.fromisoformat(stamp)
    except ValueError:
        return None
    return (datetime.date.today() - gen).days


def freshness_warning() -> str:
    """A sentence the server volunteers when its data is old enough to mislead.

    Build and lifecycle data is the part that ages badly: a confidently stated but stale
    patch level is the exact failure this server exists to prevent, so it must admit the
    problem unprompted rather than waiting to be asked.
    """
    age = data_age_days()
    if age is None or age <= STALE_AFTER_DAYS:
        return ''
    return ('\n\n**Freshness warning:** this data was generated %d days ago (%s). '
            'CU and support dates move; verify against Microsoft before acting on it.'
            % (age, meta().get('generated')))


# --- text search --------------------------------------------------------------------------

_TOKEN = re.compile(r'[a-z0-9_]+')
_STOP = {
    'the', 'a', 'an', 'is', 'it', 'to', 'of', 'and', 'or', 'in', 'on', 'for', 'my', 'i',
    'do', 'does', 'did', 'how', 'what', 'why', 'when', 'should', 'can', 'be', 'this',
    'that', 'with', 'from', 'are', 'was', 'if', 'so', 'me', 'you', 'your', 'not', 'at',
    'get', 'have', 'has', 'but', 'as', 'by', 'there', 'they', 'them',
}


def tokens(s: str) -> list[str]:
    """Lowercase word tokens, stopwords dropped, SQL identifiers kept whole."""
    return [t for t in _TOKEN.findall((s or '').lower()) if t not in _STOP and len(t) > 1]


def _idf(corpus_tokens: list[list[str]]) -> dict[str, float]:
    """Inverse document frequency, so 'sql' counts for far less than 'filegroup'."""
    import math
    n = len(corpus_tokens) or 1
    df: dict[str, int] = {}
    for toks in corpus_tokens:
        for t in set(toks):
            df[t] = df.get(t, 0) + 1
    return {t: math.log(1 + n / (1 + c)) for t, c in df.items()}


class Index:
    """A small BM25-style ranker.

    Deliberately dependency-free: adding a vector database to answer 434 questions would
    be more moving parts than the whole server. Fields are weighted because a term in a
    title means much more than the same term buried in a body.
    """

    def __init__(self, records: list[dict], fields: dict[str, float]):
        self.records = records
        self.fields = fields
        self._doc_tokens = []
        self._weighted = []
        for r in records:
            per_field = {}
            flat = []
            for f, w in fields.items():
                toks = tokens(str(r.get(f) or ''))
                per_field[f] = toks
                flat.extend(toks)
            self._doc_tokens.append(flat)
            self._weighted.append(per_field)
        self._idf = _idf(self._doc_tokens)
        self._avg_len = (sum(len(d) for d in self._doc_tokens) / len(records)) if records else 1

    def off_domain(self, query: str, max_unknown: float = 0.4) -> bool:
        """True when too much of the query is vocabulary this corpus has never seen.

        Without this, "how do I configure an nginx reverse proxy" confidently returns a
        SQL Agent *proxy* answer, because `proxy` really is a SQL Server term and BM25
        has no notion of a question being about something else entirely. Refusing to
        answer is the whole promise of this server, so the refusal needs a mechanism and
        not just good intentions.
        """
        q = tokens(query)
        if not q:
            return True
        unknown = sum(1 for t in q if t not in self._idf)
        return (unknown / len(q)) > max_unknown

    def search(self, query: str, limit: int = 8,
               min_coverage: float = 0.0) -> list[tuple[dict, float]]:
        """Ranked hits.

        `min_coverage` is the fraction of the query's content tokens a record must
        actually contain. BM25 alone will happily rank a record top on a single shared
        term; coverage is what separates "this is the answer" from "this is the least
        bad row in the table".
        """
        q = tokens(query)
        if not q:
            return []
        if min_coverage and self.off_domain(query):
            return []
        k1, b = 1.5, 0.75
        scored = []
        for i, record in enumerate(self.records):
            per_field = self._weighted[i]
            length = len(self._doc_tokens[i]) or 1
            score = 0.0
            matched = 0
            for term in q:
                idf = self._idf.get(term)
                if not idf:
                    continue
                tf = 0.0
                for f, w in self.fields.items():
                    tf += w * per_field[f].count(term)
                if not tf:
                    continue
                matched += 1
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * length / self._avg_len))
            if score <= 0:
                continue
            if min_coverage and (matched / len(q)) < min_coverage:
                continue
            scored.append((record, score))
        scored.sort(key=lambda t: -t[1])
        return scored[:limit]


@lru_cache(maxsize=1)
def faq_index() -> Index:
    return Index(faqs(), {'question': 3.0, 'post_title': 1.5, 'answer': 1.0})


@lru_cache(maxsize=1)
def script_index() -> Index:
    return Index(scripts(), {'name': 3.0, 'purpose': 2.0, 'category': 1.2, 'path': 1.0})


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
