# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

A deep post-release audit (four independent code-review passes, each finding verified by direct
execution before being filed) turned up 19 bugs, all fixed here. See issues #2–#20 for full
repro steps and rationale on each.

### Fixed

- **[CRITICAL]** `trace --req-coverage`/`--sec-tested` crashed with an unhandled exception on a
  non-numeric value and exited 1 (colliding with the gate-fail exit code) instead of 2 (#2).
- **[HIGH]** The JSON parser crashed (`CONSTRAINT_ERROR`/`STORAGE_ERROR`) on a malformed exponent
  or deeply-nested input instead of raising `Json_Error`; recursion depth is now bounded and
  RFC 8259 number validation is stricter (leading zeros, bare trailing decimals) (#3, #15).
- **[HIGH]** `\u` surrogate pairs were never combined, producing invalid UTF-8 for non-BMP
  characters; they're now combined per the standard formula, and lone unpaired surrogates are
  rejected (#4).
- **[HIGH]** The annotation scanner false-positived on any line containing the marker substring
  anywhere (doc comments, string literals) instead of only real annotations (#5).
- **[HIGH]** The starter lint rules matched case-sensitively (Ada is case-insensitive), only
  honoured `-- fusa:unsafe` on the exact same line, and were whitespace-brittle for multi-word
  needles like `"when others =>"` (#6).
- **[HIGH]** `qualify`'s text-format output printed to stdout even when `--output` was given,
  unlike every other command (#7).
- **[MEDIUM-HIGH]** An interrupted `qualify` run's leftover `.fusa-qualify-tmp/` directory was
  scanned as real project source by later commands (#8).
- **[MEDIUM-HIGH]** A missing/empty/non-string requirement `id` was silently dropped with no
  diagnostic, unlike a duplicate id (#9).
- **[MEDIUM]** Boolean flags (`--strict`, `--force`, `--gaps`, `--full`) didn't support the
  `--flag=value` form that other flags already did (#10).
- **[MEDIUM]** The JSON writer had no protocol validation: mismatched `Key`/`Value` calls or
  unbalanced `Object_End`/`Array_End` produced invalid JSON or a raw `CONSTRAINT_ERROR`; these now
  raise a documented `Writer_Error` (#11).
- **[MEDIUM]** `trace --strict` combined with only one of `--req-coverage`/`--sec-tested` silently
  dropped the implicit 100% default for the other axis (#12).
- **[LOW-MEDIUM]** `Fusa.Files.Relative_To` had no path-boundary check, so a directory that is a
  string-prefix of an unrelated sibling produced a wrong relative path (#13).
- **[LOW-MEDIUM]** A `sourceDirs` entry like `"./src"` leaked a literal `./` into every relative
  path built from it; `Join` now normalises `.` path segments (#14).
- **[LOW]** The JSON parser kept both values for a duplicate object key (first-wins via
  `Get_Member`) instead of last-wins, the common JSON-tooling convention (#16).
- **[LOW]** `Flag_Value` didn't recognise the empty-value equals form `--flag=` (#17).
- **[LOW]** `Emit_Runtime_Error`'s text-format branch never honoured `--output` (#18).
- **[LOW]** The ZIP writer never set the UTF-8 filename flag (bit 11) for non-ASCII entry names
  (#19).
- **[LOW]** A `.fusa.json` `project` field of the wrong JSON type produced a misleading "missing"
  error message instead of distinguishing wrong-type from absent (#20).

### Added

- 20 formal requirements for ada-FuSa's own implementation (`.fusa-reqs.json`), traced end to end
  via `-- fusa:req`/`-- fusa:test` annotations across `src/` and `tests/` — `adafusa trace` against
  this repo now reports 100% traced and 100% tested.
- 88 additional unit tests (132 → 220), each a regression test for one of the fixes above.

### Changed

- Line coverage: 85.1% → 88.3%.

## v0.1.0 — 2026-07-27

Initial release. Implements the x-FuSa spec v1.11 §9.1 MUST command set end to end.

### Added

- CLI commands: `version`, `capabilities`, `init`, `check`, `trace`, `qualify`, `release`,
  `audit-pack`, `report`.
- §3.1/§3.2 common JSON header and report-document envelope.
- §2.3 exit codes (0/1/2/3), §2.4 severity enum, §4.2 fingerprint algorithm (SHA-256).
- `.fusa.json` / `.fusa-reqs.json` load and save, including legacy filename fallback and
  duplicate-requirement-id detection (§1.2).
- `-- fusa:req` / `-- fusa:test` / `-- fusa:sec-test` annotation scanning (§1.4), with malformed
  (missing- or multi-id) lines surfaced as findings rather than silently dropped.
- 8 starter rules (`ADA001`–`ADA008`) drawn from the Ada Quality and Style Guide, registered
  through a small rule-engine framework, using the `ADA-<n>` prefix convention from
  [FuSaOps#78](https://github.com/SoundMatt/FuSaOps/issues/78) rather than a ported MISRA list.
- Hand-rolled, zero-dependency JSON parser/writer, SHA-256, CRC-32, and ZIP (stored/uncompressed)
  writer — none of these are part of the Ada standard library.
- `check`/`report` support `text`, `json`, and `sarif` (2.1.0) output formats.
- GitHub Actions CI (Linux): DCO check, build, unit tests, coverage gate (≥80% line coverage),
  qualify, evidence-artifact upload.
- Dockerfile built natively on Alpine (musl) with `gcc-gnat` + `libgnat-static`, producing a fully
  static binary; `docker-publish.yml` publishing `ghcr.io/soundmatt/ada-fusa` on tag push.

### Known limitations

See README ["Known limitations"](README.md#known-limitations-v010) — most notably, SPARK
proof-coverage (`gnatprove` integration) is intentionally deferred to a later release.
