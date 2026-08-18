# Changelog

All notable changes to the sqldba MCP server. Follows [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/).

## [0.2.1] - 2026-08-18

A quality pass, not new surface. The headline item is a false negative in the tool most
likely to be called first, and a published accuracy number that could not have failed.

### Fixed

- **`check_build` told 2017/2019/2014 servers they were patched when they were years
  behind on security.** The servicing-train logic was written against SQL 2022, where the
  CU build (16.0.4265.3) is higher than the CU+GDR build (16.0.4262.2). That shape inverts
  once a version reaches its **final CU**: Microsoft stops shipping CUs and puts later
  security fixes out as GDR on top of the last one, so CU+GDR keeps climbing while CU
  stands still. On 2019 the final CU is `15.0.4430.1` from **2025-02-27** and CU32+GDR is
  `15.0.4480.2` from **2026-07-14**; on 2017 the gap is closer to four years.

  Preferring the CU train within a series therefore measured those servers against a build
  frozen years ago and returned **UP TO DATE** - on exactly the versions still in the field
  on extended support, where patch level is the entire conversation. It is the one answer
  the README says this server exists to prevent, given by the server itself.

  Identifying which train a build sits on and judging whether it is current are now
  separate questions. The train is still named and still assumed out loud; the verdict is
  measured against the highest build on the same series, and when something higher exists
  it is named with its release date and KB. `UP TO DATE` as a bare headline now appears
  only when the build really is the highest on its series - an agent summarising the answer
  used to carry that phrase and drop the qualifier under it.

- **`lookup_error` missed the form errors actually arrive in.** `Msg 18456, Level 14,
  State 1, Line 1` is what SQL Server prints and therefore what gets pasted, and it came
  back *"not in the sqldba.blog library yet"* for an error covered since day one. The
  number was only read when the input was nothing but digits. It is now extracted from
  `Msg N`, `error N` and `Error: N`, anchored on the keyword so the Level and State
  numbers that follow cannot be mistaken for it. A number that genuinely misses still
  falls through to the phrase search instead of stopping.

  This was the worst class of bug this server can have. Its whole promise is that *"not
  in the library"* can be trusted, so a false negative does not just fail to answer - it
  actively tells the agent to stop looking.

- **Error search was a substring test, the only search here not using the ranked index.**
  `incorrect syntax` missed *Incorrect syntax near* on one trailing word; `failed login`
  missed *Login failed for user* purely on word order. It now runs through the same BM25
  index as the FAQ and script corpora, with a coverage floor tuned for titles (which are
  a handful of words, not a sentence) and the off-domain guard still applied, so an
  unrelated question gets nothing rather than the least-bad row.

- **The eval row for it could not fail.** `err-phrase` published **100%** while querying
  with each error's verbatim title against that substring match - every record contained
  its own query by construction - and accepted an answer as correct if the error number
  appeared anywhere in it, including buried in a list of eight candidates. Two independent
  ways to be unfalsifiable, in the same file that warns about exactly this two suites
  further down. It is now scored like the headline FAQ row: same deterministic rewording,
  and the record has to come back top.

  Honestly measured, the old search scored **29.8%**; the new one scores **95.7% top-1 /
  100% top-3**. The 100% was never real, so the README's scorecard has been corrected
  rather than quietly improved.

- **A mistyped flag started a silent stdio server.** `sqldba-mcp --selftst` sat waiting on
  a handshake a terminal never sends, looking hung, and exited 0. Unrecognised options now
  print usage to stderr and exit 2, `--help` exists, and `python -m sqldba_mcp` exits with
  the same code as the console script - the parity that `--selftest` already had to be
  fixed for once.

### Added

- **Tool annotations.** All six tools declare `readOnlyHint`, `idempotentHint`,
  non-destructive and `openWorldHint: false` over the protocol. "It never touches your SQL
  Server" was a README promise a client cannot read; it is now one a client can act on, so
  a reference lookup is auto-approvable instead of prompting a DBA six times.
- **`tests/test_protocol.py`** - the first test that speaks the actual protocol. It spawns
  `python -m sqldba_mcp` as a real subprocess, completes the stdio handshake, and exercises
  a tool call, a resource read and the prompt. Everything else here imports `tools` and
  calls functions, so the entire transport layer was untested: if the SDK changed shape,
  every other test would still pass while `claude mcp add sqldba` was broken for everyone.
- **`tests/test_red_team.py`** - the refuse-rather-than-guess promise, asserted in both
  directions. Off-domain questions (nginx, postgres, Kubernetes, "the capital of France"),
  plausible-but-absent input (`error 31337`, `FAKE_WAIT`, `99.0.1000.0`), cross-tool
  contamination, citation coverage, and a junk battery (empty, 5000 chars, SQL injection
  shapes, path traversal) that asserts no tool raises. A false negative is the worst answer
  this server can give and it did not have a suite of its own.
- Tests for every fix above, plus a guard that `__version__` and the packaged version
  cannot drift apart (**91 tests**, up from 55).

### Changed

- README: the corrected scorecard with the reason it changed, and a new section on the
  **22 of 47 errors that carry no write-up URL** - a content gap, stated the same way the
  38 script header gaps already were, and a fair reading order for the Error Library.
- `test_every_record_has_a_source_url` renamed to `test_source_urls_point_at_the_blog`,
  which is what it checks. The old name asserted something that is not true.

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
- `scripts-missing-post-url.txt`: the 38 SQL scripts whose `Author :` header carries the bare
  domain rather than a post URL, so `find_script` ships `url: null` for them. Named for what it
  measures - a header gap, not a content gap. Most of the 38 have a published write-up already.

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
