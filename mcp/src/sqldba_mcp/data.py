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
def posts() -> list[dict]:
    """One record per published post: title, lead, URL. The reachability floor."""
    return _load('posts')


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
    # 'am' only. "what version am I on" left the tokens ['version', 'am'], so half the
    # query was vocabulary the corpus had never seen, the off-domain guard fired, and the
    # question was refused outright. A wider sweep of function words was tried and reverted:
    # adding 'all', 'out', 'over', 'now' and friends cost the FAQ suite 0.5pp, because in
    # DBA prose they are content - "out of space", "over 80% full", "all user databases".
    'am',
    # 'need' and 'were' likewise carry nothing in DBA prose, unlike the 'all'/'out'/'over'
    # sweep above. "i need to check when my databases were last backed up" spent 2 of its
    # 7 tokens on them, which pushed the coverage floor out of reach for Get-BackupAge and
    # left the question answered by the LSN-continuity script instead.
    'need', 'were',
}


# Split CamelCase, including the ACRONYMWord boundary, so `Get-VlfCount` gives up `Vlf`
# and `Count` while `PAGEIOLATCH_SH` stays whole (no lower-case letter follows a capital).
_CAMEL = re.compile(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])')
_WORD = re.compile(r'[A-Za-z0-9_]+')


def tokens(s: str) -> list[str]:
    """Lowercase word tokens, stopwords dropped, SQL identifiers kept whole.

    Script names are CamelCase, and lowercasing before splitting made the highest-weighted
    field in the index useless for natural language: `Get-BlockingChains` became the single
    token `blockingchains`, which the word "blocking" does not match. A DBA asking "what is
    blocking right now" could only reach that script through its purpose line, at a third
    of the weight, and often did not reach it at all.

    So an identifier contributes three things: itself, its parts, and its adjacent pairs.
    The pairs matter as much as the parts - `Get-TempDbConfiguration` splits to
    `temp`+`db`+`configuration`, and nobody types "temp db". They type "tempdb", which is
    the pair. Prose is unaffected: a word with no internal capital has no parts and no
    pairs, so this costs nothing on the FAQ and error corpora.
    """
    out = []
    for raw in _WORD.findall(s or ''):
        low = raw.lower()
        if low not in _STOP and len(low) > 1:
            out.append(low)
        parts = [p for p in _CAMEL.split(raw) if p]
        if len(parts) < 2:
            continue
        for p in parts:
            pl = p.lower()
            if pl not in _STOP and len(pl) > 1:
                out.append(pl)
        for a, b in zip(parts, parts[1:]):
            out.append((a + b).lower())
    return out


# --- how a DBA actually types ------------------------------------------------------------
#
# "sysadmin members" worked and "show me who has sysadmin" returned nothing. Same intent,
# opposite outcomes, because the index rewarded the query that already looked like a script
# name - exactly backwards from how anyone asks. Every filler token was being scored, so
# adding natural language made the answer worse.

# The ask, as opposed to the thing being asked for. Stripped before anything is scored.
_ASK_FRAME = re.compile(
    r"""(?ix)
    \b(?:
        (?:can|could|would)\s+you(?:\s+please)?
      | (?:please)
      | (?:i\s+(?:need|want|would\s+like))
      | (?:is\s+there)
      | (?:do\s+you\s+have)
      | (?:give|show|find|fetch|send|list)\s+(?:me|us)?
      | (?:what|which)\s+(?:script|scripts|query|queries)
      | (?:how\s+do\s+i\s+(?:see|check|find|get|run))
      | (?:anything|something)\s+(?:useful\s+)?(?:for|to)
      | (?:that\s+(?:are\s+)?(?:useful\s+)?(?:for|to))
      | (?:a\s+)?list\s+of
    )\b
    """)

# Nouns and verbs that carry no signal when the thing being searched IS a script library.
# `check` is deliberately absent: "check integrity" means something, and Get-DatabaseIntegrityChecks
# contains the word.
_ASK_NOISE = {'script', 'scripts', 'query', 'queries', 'show', 'showing', 'shows', 'give',
              'need', 'want', 'find', 'see', 'run', 'please', 'me', 'us', 'useful',
              'anything', 'something', 'thing', 'stuff', 'help'}

# A request for a curated SET, not a match. The package carries no popularity signal, so
# "the top 10 scripts" cannot be ranked honestly - and returning whatever scored highest is
# how "give me a list of top 10 scripts" came back with Get-TopCpuQueries, matched on "top".
_BROWSE_WORDS = {'top', 'best', 'all', 'everything', 'every', 'most', 'popular', 'good',
                 'favourite', 'favorite', 'recommended', 'useful', 'list'}

# Recency is the difference between Get-LastDatabaseBackupTimes and Get-BackupChainIntegrity,
# and it was being spent on nothing. Expanded on the DOCUMENT side, not the query side, so a
# query stays exactly as long as the user typed it and the coverage floor is unaffected.
SYNONYMS = {
    'last': ('recent', 'latest', 'current', 'newest'),
    'recent': ('last', 'latest', 'current', 'newest'),
    'latest': ('last', 'recent', 'current', 'newest'),
    'current': ('last', 'recent', 'latest', 'active'),
    'active': ('current', 'running'),
    'failure': ('failed', 'failing', 'failures'),
    'failed': ('failure', 'failures', 'failing'),
    'size': ('sizes', 'space'),
    'space': ('size', 'sizes', 'free'),
    'permission': ('permissions', 'rights', 'access'),
    'permissions': ('permission', 'rights', 'access'),
}


def _other_number(term: str) -> str | None:
    """The other of singular/plural for a plain word, or None.

    Deliberately not a stemmer: it handles the one inflection that actually separated a
    DBA's question from the script that answers it, and nothing else.
    """
    if len(term) < 4 or '_' in term or term.isdigit():
        return None
    if term.endswith('ies') and len(term) > 4:
        return term[:-3] + 'y'
    if term.endswith(('ss', 'us', 'is')):
        return None
    if term.endswith('es') and term[-3:-2] in ('x', 's', 'h', 'z'):
        return term[:-2]
    if term.endswith('s'):
        return term[:-1]
    return term + 's'


def normalise_script_query(query: str) -> tuple[str, bool]:
    """Strip the ask, keep the intent. Returns (query, is_a_browse_request).

    A browse request is detected by what is LEFT once the frame and the noise are gone: if
    nothing remains but quantifiers, the user asked for a curated set rather than a match,
    and the honest answer is the catalogue rather than whatever scored highest.
    """
    cleaned = _ASK_FRAME.sub(' ', query or '')
    kept = [t for t in tokens(cleaned) if t not in _ASK_NOISE]
    if not kept or all(t in _BROWSE_WORDS or t.isdigit() for t in kept):
        return ' '.join(kept), True
    return ' '.join(kept), False


def _idf(corpus_tokens: list[list[str]]) -> dict[str, float]:
    """Inverse document frequency, so 'sql' counts for far less than 'filegroup'."""
    import math
    n = len(corpus_tokens) or 1
    df: dict[str, int] = {}
    for toks in corpus_tokens:
        for t in set(toks):
            df[t] = df.get(t, 0) + 1
    return {t: math.log(1 + n / (1 + c)) for t, c in df.items()}


# See Index._recognises: how far a prefix match may stretch before it is a different
# word rather than a word ending. "corrupt"/"corruption" = 3 (allowed);
# "post"/"postgres" = 4 (blocked).
# Query-side vocabulary. Same class of fix as the plural fold: the corpus is written in
# one register and typed in another, and a word the index has never seen scores nothing.
#
# Earned by "i need to check when my databases were last backed up", which returned a
# single script - the LSN-continuity one, whose own description says "coverage scripts
# only check recency, not continuity". The corpus contains "backup" 27 times and
# "backed up" zero times, so the most important word in that question was worth nothing
# and generic words decided the ranking.
#
# EXPANSION, not replacement. "last" has to keep matching Get-LastDatabaseBackupTimes
# while also reaching Get-BackupAge, which says "most recent". Replacing would just move
# the blind spot. Kept small and DBA-specific on purpose - this is a vocabulary bridge,
# not a thesaurus, and every entry below is a word form a DBA types that the library
# happens not to use.
_SYNONYMS = {
    'backed':    ('backup',),
    'backups':   ('backup',),
    'last':      ('recent', 'latest'),
    'latest':    ('recent', 'last'),
    'recent':    ('last', 'latest'),
    'when':      ('age', 'date'),
    'restored':  ('restore',),
    'shrunk':    ('shrink',),
    'shrinking': ('shrink',),
    'growing':   ('growth', 'grow'),
    'grew':      ('growth',),
    'failing':   ('failure', 'failed'),
    'failed':    ('failure',),
    'running':   ('active', 'running'),
    'eating':    ('usage', 'consuming'),
    'usage':     ('used',),
}


_STEM_SLACK = 3


class Index:
    """A small BM25-style ranker.

    Deliberately dependency-free: adding a vector database to answer 434 questions would
    be more moving parts than the whole server. Fields are weighted because a term in a
    title means much more than the same term buried in a body.
    """

    def __init__(self, records: list[dict], fields: dict[str, float],
                 guard_fields: tuple[str, ...] | None = None,
                 expand: bool = False,
                 decline_when_vague: bool = False):
        self.records = records
        self.fields = fields
        # Which fields decide whether a question is even ON TOPIC, as opposed to which
        # fields decide ranking. Indexing script header comments lifted recall sharply and
        # simultaneously taught the corpus ordinary English - "write", "list", "sort" - so
        # "write me a python script to sort a list" stopped being off-domain and came back
        # with eight scripts. Topicality is judged from the curated fields only; incidental
        # prose can win a ranking but must never make a foreign question look familiar.
        self._guard_fields = guard_fields or tuple(fields)
        self._doc_tokens = []
        self._weighted = []
        for r in records:
            per_field = {}
            flat = []
            for f, w in fields.items():
                toks = tokens(str(r.get(f) or ''))
                if expand:
                    # Singular and plural, on the document. `Get-LastDatabaseBackupTimes`
                    # carries `backup` and a DBA types "most recent backups"; without this
                    # the two never meet. Underscored identifiers are left alone so wait
                    # types and column names are not mangled.
                    toks = toks + [_other_number(t) for t in set(toks) if _other_number(t)]
                    # Synonyms go on the DOCUMENT, never the query: a query stays exactly
                    # as long as the user typed it, so the coverage floor still means what
                    # it meant. `Get-LastDatabaseBackupTimes` answers to "most recent
                    # backups" because the record learned `recent`, not because the query
                    # grew three words it did not contain.
                    toks = toks + [alt for t in set(toks) for alt in SYNONYMS.get(t, ())]
                per_field[f] = toks
                flat.extend(toks)
            self._doc_tokens.append(flat)
            self._weighted.append(per_field)
        self._idf = _idf(self._doc_tokens)
        # What IDF would give a word appearing in ZERO records: log(1 + n/1). Not an
        # invented constant and not the maximum observed - the same formula, evaluated at
        # df=0. It has to be strictly above every real term, because "python" and "oracle"
        # are more telling than the rarest word the corpus does hold, and the max observed
        # (df=1) sat only fractionally above ordinary English like "write" and "list".
        # At that spacing a foreign word could not outweigh three incidental matches.
        import math as _math
        self._unseen_idf = _math.log(1 + (len(records) or 1))
        self._avg_len = (sum(len(d) for d in self._doc_tokens) / len(records)) if records else 1
        self._guard_vocab = {t for per_field in self._weighted
                             for f in self._guard_fields
                             for t in per_field.get(f, ())}

        # Terms so common in this corpus that matching one says nothing. "sql" and
        # "server" are in most script names; a query made only of those is not a search,
        # it is a shrug - and answering it anyway is how "is my sql server ok" returned
        # `uninstall-sql`. Consumed by search().
        n = max(len(records), 1)
        df = {}
        for doc in self._doc_tokens:
            for t in set(doc):
                df[t] = df.get(t, 0) + 1
        self._ubiquitous = {t for t, c in df.items() if c / n > 0.25}

        # Only the script index declines a vague question. The pathology is specific to
        # it - "is my sql server ok" ranked `uninstall-sql` to the top - and so is the
        # consequence, because find_script is the one tool whose answer a DBA then RUNS.
        # Switched on globally it costs the error suite a real hit: "cannot database" is
        # a degraded but legitimate query, and in a 47-record corpus both of its words
        # are already "ubiquitous", so the question would be refused. Scope the rule to
        # the evidence.
        self._decline_when_vague = decline_when_vague

    def _query_terms(self, query: str) -> list[str]:
        """Tokens as this index will score them, singulars folded in.

        A trailing "s" used to be fatal. The tokeniser keeps words whole, so "vlfs" never
        reached `vlf` and "how big are my tables" never reached `table` - both returned
        NOTHING from a library holding Get-VlfCount and Get-TableSizes. Only applied when
        the typed word is absent from the corpus and its singular is present, so no term
        that already matched can change. Used by the off-domain guard as well as by
        search, because folding after the guard let "tables" be counted as foreign
        vocabulary and refuse the question before scoring ever ran.
        """
        return [t[:-1] if (t.endswith('s') and t not in self._idf and t[:-1] in self._idf)
                else t for t in tokens(query)]

    def off_domain(self, query: str, max_unknown: float = 0.4) -> bool:
        """True when too much of the query is vocabulary this corpus has never seen.

        Without this, "how do I configure an nginx reverse proxy" confidently returns a
        SQL Agent *proxy* answer, because `proxy` really is a SQL Server term and BM25
        has no notion of a question being about something else entirely. Refusing to
        answer is the whole promise of this server, so the refusal needs a mechanism and
        not just good intentions.
        """
        q = self._query_terms(query)
        if not q:
            return True
        unknown = sum(1 for t in q if not self._recognises(t))
        return (unknown / len(q)) > max_unknown

    def _recognises(self, term: str) -> bool:
        """Whether the corpus knows this word, allowing for the obvious word endings.

        There is no stemmer here on purpose, but the guard cannot afford to be literal
        about it. "corruption" is in the script corpus and "corrupt" is not, so asking
        "is my database corrupt" put half the query in the unknown bucket, tripped this
        guard, and got a flat refusal from a library that holds `Get-SuspectPages` and
        `Get-LastDbccCheckdb`. Refusing to answer a corruption question is the single
        worst false negative this library can produce.

        A prefix match either way is enough to say "this vocabulary is not foreign",
        which is all this guard decides. Ranking is untouched: nothing here changes
        which record wins, only whether the question is answered at all.

        HOW FAR APART a prefix match may be before it stops being a word ending and
        starts being a different word. "corrupt"/"corruption" differ by 3 and must
        match. "post"/"postgres" differ by 4 and must NOT: that leniency was letting
        every off-domain question whose first syllable happened to be a corpus word
        straight through the guard, which is how "how do I install postgres" got
        answered with a SQL Server pre-install FAQ, and "best way to move a database to
        Azure" got answered with "What replaced Azure Data Studio?".

        The 4-character floor also went to 3, because it was excluding the corpus side
        of real short identifiers: "vlfs" could not reach "vlf", so `find_script("vlfs")`
        refused a library that holds Get-VlfCount.

        Measured, not guessed - see MCP-SELF-TEST-2026-08-19.md.
        """
        if term in self._guard_vocab:
            return True
        # A word the corpus knows under another name is not foreign vocabulary. Without
        # this the guard counted "eating" as off-domain and refused "whats eating my cpu"
        # outright, from a library holding Get-TopCpuQueries - while the synonym table
        # right below could already have matched it.
        if any(alt in self._guard_vocab for alt in _SYNONYMS.get(term, ())):
            return True
        if len(term) < 3:
            return False
        return any((known.startswith(term) or term.startswith(known))
                   and abs(len(known) - len(term)) <= _STEM_SLACK
                   for known in self._guard_vocab if len(known) >= 3)

    def _coverage_weights(self, q, groups):
        """How much each query term is worth when judging coverage.

        Plain `matched / len(q)` treats every word as equally telling, and that is the
        whole of this defect. Measured 2026-08-20 against eight off-domain questions the
        tuning set had never seen, four were answered confidently, and every one of them
        matched on a single ordinary word:

            is oracle BETTER than sql server      -> "Can I get the BETTER message ...?"
            what certifications are WORTH doing   -> "Should I be verifying backups ...
                                                      it is WORTH doing"
            who should I report a SECURITY breach -> "Is xp_cmdshell always a SECURITY
                                                      risk?"

        `better` is not ubiquitous, so it counted as a full informative match, exactly as
        `PAGEIOLATCH` would. Weighting by IDF makes a common word worth little and a rare
        one worth a lot, so a match has to be on something that actually distinguishes.

        Three kinds of term, and the middle one is the reason this is not a one-liner:

        indexed     a form of it is in the corpus -> its own IDF.
        recognised  the corpus knows it under another name but holds no literal token
                    ("corrupt" via "corruption"). EXCLUDED from both sides: it is neither
                    evidence for a record nor against it, and counting it against would
                    refuse "is my database corrupt", which test_red_team calls the worst
                    false negative this library can produce.
        foreign     the corpus has never seen it in any form ("oracle", "salary",
                    "laptop") -> the IDF of a df=0 term, strictly above every real one,
                    and unmatchable by definition, so it drags coverage down. The point.
        """
        weights = {}
        for t in q:
            indexed = [self._idf[f] for f in groups[t] if f in self._idf]
            if indexed:
                weights[t] = max(indexed)
            elif self._recognises(t):
                continue                      # familiar but unindexed: not evidence either way
            else:
                weights[t] = self._unseen_idf  # never seen: unmatched, and it should hurt
        return weights

    def search(self, query: str, limit: int = 8,
               min_coverage: float = 0.0) -> list[tuple[dict, float]]:
        """Ranked hits.

        `min_coverage` is the fraction of the query's content tokens a record must
        actually contain. BM25 alone will happily rank a record top on a single shared
        term; coverage is what separates "this is the answer" from "this is the least
        bad row in the table".
        """
        q = self._query_terms(query)
        if not q:
            return []
        if min_coverage and self.off_domain(query):
            return []

        # TWO different notions of "informative", and conflating them refuses the one
        # question this library must never refuse.
        #
        # `asked` is what the QUESTION carries: a word the corpus recognises that is not
        # already in most records. If a question has none of those it is not a search -
        # "is my sql server ok" is sql + server + ok, and ranking it returned
        # `uninstall-sql`. Decline instead of guessing.
        #
        # `indexed` is the subset that can actually be scored. "is my database corrupt"
        # carries `corrupt`, which the guard recognises through `corruption` but which no
        # record contains literally - so it is `asked` but not `indexed`, and the
        # question is ranked normally rather than declined. Requiring a match on a term
        # that is not in the index would refuse it, which test_red_team calls the single
        # worst false negative this library can produce. It is right.
        # Build the match groups FIRST, because a term that only reaches the corpus through
        # a synonym is still a real term. "backed" is not in the index and is not a prefix
        # of "backup", so it counted as neither asked nor informative - which meant
        # Get-BackupAge, matching the question only on "backed"->backup and
        # "last"->recent, failed the informative gate and vanished from a backup question.
        groups = {}
        for t in q:
            forms = {t}
            for alt in _SYNONYMS.get(t, ()):
                if alt in self._idf:
                    forms.add(alt)
            groups[t] = forms

        def _scoreable(t):
            return any(f in self._idf and f not in self._ubiquitous for f in groups[t])

        informative = {t for t in q if _scoreable(t)}
        asked = {t for t in q
                 if t in informative or (t not in self._ubiquitous and self._recognises(t))}
        if min_coverage and self._decline_when_vague and not asked:
            return []

        cov_weights = self._coverage_weights(q, groups) if min_coverage else {}
        cov_total = sum(cov_weights.values())

        k1, b = 1.5, 0.75
        scored = []
        for i, record in enumerate(self.records):
            per_field = self._weighted[i]
            length = len(self._doc_tokens[i]) or 1
            score = 0.0
            matched = 0
            matched_terms = set()
            for term in q:
                tf = 0.0
                idf = 0.0
                for form in groups[term]:
                    f_idf = self._idf.get(form)
                    if not f_idf:
                        continue
                    f_tf = 0.0
                    for f, w in self.fields.items():
                        f_tf += w * per_field[f].count(form)
                    if f_tf > tf:
                        tf, idf = f_tf, f_idf
                if not tf or not idf:
                    continue
                matched += 1
                matched_terms.add(term)
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * length / self._avg_len))
            if score <= 0:
                continue
            # Tolerance, because this floor is a ratio compared against a decimal:
            # min_coverage=0.34 was written to mean "at least one word in three" and
            # 1/3 is 0.3333, so a three-word question whose one real term matched was
            # rejected by 0.0067. "is replication falling behind" returned nothing.
            if min_coverage and (matched / len(q)) < min_coverage - 1e-6:
                continue
            # ...and the same floor again, weighted by IDF. BOTH must hold, deliberately:
            # this is an EXTRA filter, never a replacement. The unweighted floors were
            # calibrated against a count ("at least one word in three"), so letting the
            # weighted figure stand alone silently re-tunes every caller. It did: weighting
            # lifted `chain` in "find blocking chains" from 0.333 to 0.373 and handed a
            # find_script question to lookup_error, via the certificate-chain error.
            # Requiring both can only ever remove a match, so nothing that was declined
            # before can start being answered because of this.
            if min_coverage and cov_total > 0:
                covered = sum(w for t, w in cov_weights.items() if t in matched_terms)
                if (covered / cov_total) < min_coverage - 1e-6:
                    continue
            if min_coverage and informative and not (informative & matched_terms):
                continue
            scored.append((record, score))
        scored.sort(key=lambda t: -t[1])
        return scored[:limit]


@lru_cache(maxsize=1)
def faq_index() -> Index:
    return Index(faqs(), {'question': 3.0, 'post_title': 1.5, 'answer': 1.0})


@lru_cache(maxsize=1)
def post_index() -> Index:
    """Every published post, searchable by what it is ABOUT.

    The title carries almost all the weight on purpose. A title is the one place a post
    states its own subject in the words a reader would use, and that is exactly what the
    FAQ corpus cannot do: an accordion answers a post's leftover questions, so "how do I
    update SSMS" reached "Do I need administrator rights?" and never the post called
    Install and Update SSMS. The lead is scored far lower - it disambiguates between two
    posts whose titles are close, and should not let a passing mention outrank a title.
    """
    return Index(posts(), {'title': 4.0, 'lead': 0.75})


@lru_cache(maxsize=1)
def script_index() -> Index:
    """Ranked search over the script library.

    Indexing each script's HEADER COMMENT BLOCK as a fifth field was measured and is not
    enabled. It lifts recall@8 over 43 natural questions from 65.1% to 72.1%, and it lets
    three more off-domain questions through - "write me a python script to sort a list",
    "write a bash script to tail a log file", "compress a folder into a zip file" - because
    header prose teaches the corpus ordinary English that its curated fields do not carry.
    Trading a published refusal promise for recall is Peter's call, not this file's.
    """
    return Index(scripts(), {'name': 3.0, 'purpose': 2.0, 'category': 1.2, 'path': 1.0},
                 guard_fields=('name', 'purpose', 'category'), expand=True,
                 decline_when_vague=True)


@lru_cache(maxsize=1)
def error_index() -> Index:
    """Ranked search over the error corpus.

    This used to be a raw substring test, which meant `search_errors` was the only search
    in the package not going through this class - and it failed on the way people actually
    type. "incorrect syntax" missed "Incorrect syntax near" because of one trailing word;
    "failed login" missed "Login failed for user" purely on word order. The eval did not
    catch it because it searched with each error's verbatim title, which a substring test
    can never fail.
    """
    return Index(errors(), {'title': 3.0, 'message': 1.5, 'meaning': 1.0, 'category': 0.8})


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


# `Msg 18456, Level 14, State 1, Line 1` is what SQL Server itself prints and therefore what
# a DBA pastes. Anchor on the Msg/error keyword so the Level and State numbers that follow
# cannot be mistaken for the error number.
_ERR_NUM = re.compile(r'\b(?:msg|errors?)\b\s*[:#]?\s*(\d{1,5})\b', re.I)


def parse_error_number(term: str) -> int | None:
    """Pull an error number out of the forms people actually paste, or None.

    '18456' / 'Msg 18456, Level 14, State 1' / 'SQL Server error 9002' -> the number.
    'login failed' -> None, so the caller falls through to a phrase search.
    """
    t = (term or '').strip()
    if not t:
        return None
    bare = t.replace(' ', '').replace(',', '')
    if bare.isdigit():
        return int(bare)
    m = _ERR_NUM.search(t)
    if m:
        return int(m.group(1))

    # No keyword in front of it. "what does 18456 mean" and "is 823 something I need to
    # panic about" are how the question actually gets typed, and both used to return
    # "not in the library" for errors covered since day one. A bare number is only
    # accepted when the library actually holds it, so this can invent nothing: a year in
    # "we are on sql 2016" matches no error and still falls through to the phrase search.
    # Dotted numbers are skipped so a build like 16.0.4165.4 is never read as an error.
    for candidate in re.findall(r'(?<![\d.])(\d{3,5})(?![\d.])', t):
        if int(candidate) in errors_by_number():
            return int(candidate)
    return None


def normalise_wait(name: str) -> str:
    """Accept the sloppy forms a DBA actually pastes: lowercase, spaces, trailing colons."""
    return re.sub(r'[^A-Z0-9_]', '', (name or '').strip().upper().replace(' ', '_'))


def search_errors(term: str, limit: int = 8) -> list[dict]:
    """Ranked free-text search over title, message, meaning and category.

    The coverage floor is lower than the FAQ's because an error title is a handful of
    words, not a sentence: requiring half of "incorrect syntax" to match leaves nothing
    to be strict about. The off-domain guard still applies, so an unrelated question
    gets nothing rather than the least-bad row.
    """
    if not (term or '').strip():
        return []
    return [e for e, _score in error_index().search(term, limit=limit, min_coverage=0.34)]


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


def version_for_name(text: str) -> dict | None:
    """Resolve "2017", "sql 2016", "13.0" or a pasted @@VERSION banner to a version record.

    A DBA asking "what is the latest version for 2017" does not have a four-part build -
    that build IS what they are asking for, so demanding it first is circular. The
    lifecycle and latest-update data to answer them is already in builds.json and was
    being withheld for want of a parser.

    Deliberately conservative. A bare number resolves only when it matches a version this
    library actually ships, so an error number like 17806 and a port like 1433 resolve to
    nothing and the caller still refuses rather than inventing a product.
    """
    t = (text or '').strip()
    if not t:
        return None
    # A bare year is only a SQL Server version if the question is about SQL Server.
    # "windows server 2019" resolved to SQL Server 2019 and reported its CU level, which
    # is a confidently wrong answer about a product this library does not cover - exactly
    # the failure the refusal promise exists to prevent. Caught by tests/real_questions.py
    # on its first run, against a fix made the same evening.
    sql_context = re.search(r'\b(sql|mssql|sqlserver|@@version)\b', t, re.I)
    bare = re.fullmatch(r'[\d.\sx]+', t, re.I)
    if sql_context or bare:
        for v in builds()['versions']:                  # "SQL Server 2019", "sql 2016", "2017"
            year = (v.get('name') or '').split()[-1]
            if year.isdigit() and re.search(r'(?<!\d)' + year + r'(?!\d)', t):
                return v
    m = re.search(r'(?<![\d.])(\d{2})\s*\.\s*(?:0|x)(?![\d.])', t, re.I)
    if m:                                               # "13.0", "13.x"
        return version_for_engine(int(m.group(1)))
    return None


# --- the servicing ladder -----------------------------------------------------------------
# Each version carries `updates`: every CU, GDR, SP and RTM build Microsoft has published
# for it, newest first. The latest_* summaries answer "am I current"; this answers "what am
# I actually running", which is the question a DBA looking at an unfamiliar build has. An
# unidentified build is where a model starts filling in from memory, and a confidently
# wrong CU number is worse than "not in the library".

def ladder(version: dict) -> list[dict]:
    return version.get('updates') or []


def identify_build(version: dict, build: tuple[int, ...]) -> dict | None:
    """The exact ladder entry for this build, or None if Microsoft never shipped it."""
    for u in ladder(version):
        if parse_build(u.get('build') or '') == build:
            return u
    return None


def bracket_build(version: dict, build: tuple[int, ...]) -> tuple[dict | None, dict | None]:
    """The published builds immediately below and above an unrecognised one.

    A build that matches nothing is usually a hotfix or an on-demand fix between two
    public updates, not a typo, so saying "it sits between CU11 and CU12" is far more
    useful than "not found" - and it is still a statement about published data rather
    than a guess about what the build is.
    """
    below = above = None
    for u in ladder(version):
        p = parse_build(u.get('build') or '')
        if not p:
            continue
        if p < build and (below is None or p > parse_build(below['build'])):
            below = u
        if p > build and (above is None or p < parse_build(above['build'])):
            above = u
    return below, above


def newer_on_train(version: dict, build: tuple[int, ...], train: str | None) -> list[dict]:
    """Published updates on the same train that are higher than this build, newest first."""
    out = []
    for u in ladder(version):
        if train and u.get('train') != train:
            continue
        p = parse_build(u.get('build') or '')
        if p and p > build:
            out.append(u)
    return out
