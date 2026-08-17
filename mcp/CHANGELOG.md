# Changelog

All notable changes to the sqldba MCP server. Follows [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-08-17

Widened from a lookup service to a reference for the whole library: scripts, docs and the
questions Peter has already answered in public.

### Added

- `find_script` - intent search over 230 scripts (181 SQL, 49 PowerShell orchestrators).
  Surfaces the SAFE/IMPACT safety class on every hit, which is the field that makes this
  worth more than a GitHub search.
- `get_script` - full verbatim body, header and safety annotations intact. Lists candidates
  rather than guessing when a name is ambiguous.
- `answer_question` - 434 questions answered in Peter's own words, extracted from the FAQ
  accordions on 162 published posts.
- **Resources**: 9 repo docs at stable `sqldba://docs/...` URIs. Offered, not chosen, so
  they cost nothing against tool-selection accuracy.
- **Prompt** `sql-server-health-triage`: the repo's own AI assessment rubric, reusable by
  any client. The first thing here that carries judgement rather than facts.
- **Retrieval eval** (`tests/eval_faq.py`): 793 scored questions across five suites, run in
  CI as a regression gate. Headline **95.9% top-1 / 99.5% top-3** on reworded questions.
  Read that with its caveat: the rewording drops words but cannot substitute synonyms, so
  it is an upper bound rather than a field measurement. The verbatim-question suite scores
  98.6% and is published only as a PLUMBING check - querying an index with the string that
  is already in it measures string equality, not retrieval.
- **Freshness contract** (`tests/check_freshness.py`): re-derives the script, doc and prompt
  datasets from the repo and compares byte for byte. Hand-edit one and the build fails.
  `check_build` also volunteers a warning in its own answer once the data passes 90 days.
- 29 more tests (26 -> 55), including the index/corpus boundary in both directions, tool
  routing, and negative tests for the search.

### Changed

- Tool count 3 -> 6, and capped there by a test. Past roughly six an agent starts choosing
  wrong, and a wrong pick is worse than no server.
- Search now requires a query to share enough vocabulary with a record before it counts as
  a hit. "How do I configure an nginx reverse proxy" previously returned a SQL Agent *proxy*
  answer with full confidence.
- Thin wrappers under `powershell/wrappers/` are excluded from the corpus - they are a 1:1
  shim for the web UI and would double every search result.

### Notes

- The boundary is deliberately asymmetric: script bodies ship in full because the body is
  the product and the repo is already public; post write-ups stay on sqldba.blog. Tests
  assert both directions so a refactor cannot quietly flip either.
- Multi-line `Purpose :` headers are now read to the end. Roughly a third of script purposes
  were being truncated mid-sentence in search results.

## [0.1.0] - 2026-08-17

First working version. Proof of concept, but built to the repo's production bar.

### Added

- `lookup_error` - SQL Server errors by number or message phrase (47 entries).
- `explain_wait` - wait types with a worth-investigating / usually-noise verdict (232 types
  across 224 write-ups).
- `check_build` - build number to version, patch level and support status (7 versions).
- Datasets bundled inside the package; no network, database or external filesystem access.
- 26 tests, including a leak gate over the shipped data and regression cover for
  servicing-train selection.

### Notes

- Servicing trains (CU / CU+GDR / GDR) are handled separately on purpose. A server fully
  patched on the GDR train sits at a *lower* build than one on the CU train, so a single
  "is my build lower than the latest" comparison reports patched servers as out of date.
  The tool names the train it assumed so a wrong assumption is visible rather than silent.
