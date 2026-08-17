# Changelog

All notable changes to the sqldba MCP server. Follows [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/).

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
