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

### Fixed (CI self-check hardening)

- **[HIGH]** `ADA002` (blanket exception handler) matched `case ... when others =>` — an ordinary
  Ada default-case branch — as if it were a real `exception ... when others =>` catch-all, firing
  4 false positives in ada-FuSa's own source. It now requires a bare `EXCEPTION` keyword within a
  short backward lookback before classifying a match as a genuine handler.
- **[MEDIUM]** The starter lint rules (`Scan_Substring`) had no string-literal awareness, so
  ada-FuSa's own fixtures and rule needle-strings (which necessarily contain each rule's trigger
  text) tripped their own rules; they now use the same quote-parity heuristic already used by the
  annotation scanner.
- **[LOW]** `-- fusa:unsafe` suppression comments only matched when placed *after* the flagged
  line; a comment placed before it (the natural Ada convention) was ignored. Suppression lookback
  is now bidirectional.

### Changed (CI)

- `check` and `trace --req-coverage 100` are now real, enforced gates in CI (previously
  `continue-on-error: true`) — a regression in either ada-FuSa's own lint cleanliness or its
  requirement traceability now fails the build.

### Added (spec-parity backlog)

- `projectRoot` in `check`/`trace`/`report` JSON output is now resolved to an absolute path
  (spec §3.2, SHOULD) instead of echoing `--dir` verbatim; `--dir` itself keeps accepting relative
  paths for file I/O unchanged (#35).
- SARIF output (`check`/`report --format sarif`) now carries a `properties` object on each result
  with `category`, and `standard`/`clause` when non-blank, so format-invariant identifiers stay
  consistent between the `json` and `sarif` formats (spec §2.9, SHOULD) (#36).
- `ADA005` (line length), `ADA006` (tab character), and `ADA008` (compiler diagnostic suppression)
  now report category `style` instead of the blanket `ADA` → `safety` prefix mapping, so filtering
  findings by category no longer bundles style nits in with genuinely safety-relevant findings like
  `ADA001`/`ADA003`/`ADA004`. Rule ids are unchanged (#37).
- `trace --func-coverage N` (spec §1.4.1, SHOULD/phased): gates on the percentage of a project's
  public `.ads` function/procedure declarations carrying a directly-preceding `fusa:req` tag,
  mirroring `--req-coverage`/`--sec-tested` but not implied by `--strict`. Backed by a new
  `Fusa.Func_Scan` module; JSON `coverage` gains `totalFunctions`/`taggedFunctions`, text output
  gains a `functions:N tagged:N` line. See README "Function-level tagging" for the documented
  counting rule (per-overload, excludes `tests/`, excludes generic formal parameters) (#23).
- ada-FuSa's own function-level tag coverage raised from ~10% (measured precisely — the ~31%
  figure in #23 was file-level, which spec §1.4.1 warns overstates real coverage) to 100%: 46 new
  requirements (REQ-024–REQ-069) added, one `fusa:req` tag placed directly above every one of the
  71 public function/procedure declarations across `src/*.ads`. `trace --func-coverage 100` is now
  a CI gate alongside `--req-coverage 100`.
- Finding disposition/waiver support (spec §4.1, SHOULD): `check`/`report` now read
  `.fusa-dispositions.json`, if present, and apply each entry's `status` (`accepted`/`deferred`/
  `rejected`) to matching findings — `fingerprint` primary match key, `ruleId`+`file`+`line` or
  rule-level `ruleId`-only fallback. An `accepted`/`deferred` entry matching no finding surfaces a
  `DISP001` WARNING (category `config`); an orphaned `rejected` entry is silent. See README
  "Dispositions / waivers" (#30).
- **[Fixed as part of #30]** `Has_Gate_Failure` previously excluded *any* non-`Open` disposition
  from gating, which meant a `rejected` finding (a denied waiver — still fully open per spec §4.1)
  would have incorrectly stopped gating too, once dispositions became reachable. Only
  `accepted`/`deferred` now suppress the gate.
- `html` output format for `check`/`report` (a self-contained HTML page with a findings table) and
  `md` (GitHub-Flavored Markdown) for `report`; `trace` gains both `html` and `md` rendering a
  requirements/coverage table. `capabilities` updated to accurately report the new per-command
  formats. 2 new requirements (REQ-073/REQ-074) (#31).
- Three MAY-level spec provisions (#38):
  - `qualify` emits a `hash` field: `sha256:` + hex(SHA-256(canonical)), where canonical is the
    document (results sorted by name, `hash` field absent, `generatedAt` blanked) serialised per
    RFC 8785 JCS — verified reproducible: byte-identical across independent runs, and cross-checked
    against an independent Python re-implementation of the same canonicalization.
  - `release --spdx-version [2.2|2.3]` emits `<name>-<version>.spdx.json` alongside `sbom.json`;
    defaults to `2.3` when the flag's mere presence opts in. `--spdx-version 3.0.1` is explicitly
    rejected as not yet implemented (its JSON-LD graph model is a different document shape) rather
    than silently mislabeling a 2.x-shaped document.
  - `init --migrate` performs a one-shot rename of legacy `.adafusa.json`/`.adafusa-reqs.json` to
    their canonical names, distinct from the automatic legacy-fallback-with-warning `Load`/
    `Load_Requirements` already perform transparently on every command.
  - 3 new requirements (REQ-075/REQ-076/REQ-077). The fourth MAY item in #38 (`init` `.github`/
    git-hook scaffolding) remains deferred per the issue's own low-priority guidance.
- Starter rule pack expanded from 8 to 16 rules (#25):
  - `SEC001`–`SEC004` (CWE-mapped security, new `Scan_Credential_Literal` matcher in
    `fusa-rules_style.adb`): possible hardcoded password/secret/API-key (CWE-798, requires the
    identifier, `:=`, and a string literal all on the same line — a plain needle match on `"PASSWORD
    :="` almost never fires on real Ada, since a typed declaration reads `Password : constant String
    := ...`, with the type name between the identifier and `:=`), `GNAT.MD5` reference (CWE-327),
    `GNAT.OS_Lib.Spawn` reference (CWE-78). All four honour `-- fusa:unsafe`.
  - `FUSA001`–`FUSA004` (new `Fusa.Rules_Project` package): project-structure presence checks
    (`.gpr`, `LICENSE`, `README`, `.github/workflows`), mirroring java-FuSa's `FUSA` rule category —
    a genuinely different rule shape (existence checks against the project root, not content
    scanning) from every other rule so far.
  - `qualify` gained known-answer cases for all 8 new rules (13 total, up from 8), keeping its
    "tests every registered rule" claim honest.
  - 2 new requirements (REQ-078/REQ-079). Ada-specific static-analysis/concurrency rules (the
    scope items #25 called out as a genuine Ada-vs-sibling-language value-add opportunity, not just
    parity) remain unimplemented — tracked in #25 for a future round.
- **`comp` command** (§9.2 SHOULD, DO-178C §6.3.4, consumed by FuSaOps v1.70.0+) (#32, partial —
  `coverage --mcdc` deferred to a follow-up per the issue's own recommendation to split into two):
  McCabe cyclomatic complexity V(G) per subprogram body, gated by `--threshold`/`--dal`
  (A<=4/B<=10 default/C<=15/D<=20), writing `comp-report.json`. New `Fusa.Comp` module — pure
  text-based decision-point counting (if/elsif/when/for/while/exit-when/and-then/or-else), no full
  Ada parser. Verified against hand-computed expected V(G) values for several fixtures (including a
  nested-subprogram case and an unconditional-loop-with-exit-when case) before wiring into the CLI.
  2 new requirements (REQ-080/REQ-081).
- **Risk analysis commands** (§9.2/§13, tool-defined schemas using the spec's own recorded
  "canonical direction") (#28):
  - `hara`/`tara`: input-file validators for `.fusa-hara.json` (ISO 26262-3 hazard analysis) and
    `.fusa-tara.json` (ISO 21434 ch.9 threat analysis) — hazard/threat identification requires
    human domain judgement a tool cannot generate, so both scaffold an empty template when absent
    and otherwise validate/re-emit whatever a human has filled in (missing `id` is an ERROR and
    excludes the entry; missing other required fields is a WARNING but the entry is still
    returned). New `Fusa.Config` sections (`Load_Hara`/`Scaffold_Hara`, `Load_Tara`/`Scaffold_Tara`)
    following the same pattern as `.fusa-reqs.json`'s `Load_Requirements`.
  - `vuln`: emits a §4 finding-list `vuln.json` (the spec's own recorded canonical direction).
    Honest about what it can't do: no vulnerability database is integrated, so it always reports a
    clean scan — an informational finding when `alire.toml` is present (documenting the
    limitation), nothing otherwise. Wired into `release --full`, replacing the prior
    always-skipped stub.
  - 5 new requirements (REQ-082–REQ-086).
- **Requirement/PR management commands** (#29) — six small, independent CLI verbs:
  - `req list`/`req add <id> <title>`: manage `.fusa-reqs.json` from the CLI instead of
    hand-editing it, rejecting a duplicate id.
  - `disposition list`/`disposition add <fingerprint-or-ruleId> <status> [rationale]`: manage
    `.fusa-dispositions.json` waivers, distinguishing a fingerprint from a bare rule id by the
    `sha256:` prefix a fingerprint always carries.
  - `pr init`/`list`/`add`/`close`: a DO-178C §11.17 problem-report log (new `.fusa-pr.json`,
    `Fusa.Config` section mirroring `Load_Requirements`/`Save_Requirements`).
  - `metrics [record]`: an append-only safety-metrics history (`.fusa-metrics.json`) — `record`
    captures requirement count, check severity counts, and `comp` violations from a live run.
  - `sign sign|verify <file> --key <key>`: HMAC-SHA256 evidence-file integrity signing. New
    `Fusa.Hmac` module (RFC 2104, built on the existing `Fusa.Sha256`) — verified against RFC 4231
    test vectors 1 and 6 before wiring into the CLI. Caught and fixed a real bug during manual
    testing: `verify` compared the freshly-computed HMAC against a stored signature still carrying
    its trailing `ASCII.LF` (`Ada.Strings.Fixed.Trim`'s default blank set is space-only, not
    LF/CR), which made every verification spuriously fail even with the correct key.
  - `hooks install|remove`: git pre-commit hook scaffolding, running `check --strict`. Refuses to
    clobber a hook it didn't install itself (a marker comment) or to run outside a git repository.
    Sets the executable bit via a direct `chmod()` C import (mirroring the existing `isatty()`
    import already used for TTY detection) — Ada has no portable file-permission API.
  - 9 new requirements (REQ-087–REQ-095).
- **Standards gap-report commands** (§9.2/§9.3, #27) — `do178`, `iso26262`, `iso21434`, `iec61508`,
  `iec62443`, `unece`, `slsa`:
  - Same input-file-driven pattern as `hara`/`tara`, extended to a generic `Cmd_Gap_Report` helper
    shared across all seven: load/validate `.fusa-<standard-id>-objectives.json` (canonical ids
    `do178c`/`iso26262`/`iso21434`/`iec61508`/`iec62443-4-1`/`unece-r155`/`slsa`, new `Fusa.Config`
    `Gap_Objective` type and `Load_Gap_Objectives`/`Scaffold_Gap_Objectives`), scaffolding a template
    on first run. A missing `id` is an ERROR (excludes the entry and gates); an unrecognised
    `status` is a WARNING (entry still returned). Deliberately does **not** gate on the mere
    presence of `gap`-status objectives — that's the expected steady state of in-progress compliance
    work, not a failure.
  - ada-FuSa has no way to determine whether a project actually satisfies a standard's objectives —
    that's a human assessor's call backed by real evidence — so these commands only validate
    structure and render whatever assessment a human recorded, never fabricate a compliance verdict.
  - `do178`'s starter template ships a small, explicitly non-authoritative checklist using
    ada-FuSa's own id scheme (`DO178-PLAN-1`, `DO178-REQ-1`, …) rather than claiming to reproduce
    RTCA's official Annex A objective numbering, which this tool has not verified against the
    official text. The other six standards scaffold an empty template.
  - `capabilities`'s `standards` array (previously always empty) now lists all seven canonical
    standard ids, per the spec's requirement that capabilities be accurate.
  - `sas`/`sci` (a differently-shaped follow-up per the issue's own phasing) deferred.
  - 2 new requirements (REQ-096/REQ-097).

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
