# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Fixed (deep-audit PR8/11 -- rule-engine correctness)

Continuing the multi-agent audit fix series. Six issues in the ADA00x/SEC00x/ANAL00x rule packs:

- **False positives on prose in comments**: `Scan_Substring` (used by six of the twelve style rules)
  never stripped comments before matching, so a comment merely mentioning a flagged construct by
  name (e.g. `-- see ADA001: pragma Suppress disables a check`) triggered the same finding as
  actually using it. Fixed with a new `Code_Portion` helper (quote-aware, so an embedded `"a -- b"`
  in a string literal isn't mistaken for a comment marker) applied to `Scan_Substring`,
  `Scan_Exception_Handler` (ADA002), and `Scan_Credential_Literal` (SEC001/SEC002) -- with an
  explicit opt-out for ADA007, whose whole purpose is to scan comment text for `TODO` markers.
- **ADA002's fixed lookback window**: searched only 6 lines above a `when others =>` for a bare
  `exception` keyword to distinguish a real handler from a `case` statement's default branch, so a
  handler with more than 6 preceding `when`-branches (one per distinct predefined exception, a
  common pattern) was misclassified as a case statement and missed entirely. Fixed with an
  unbounded backward scan that stops at whichever of a bare `exception` or a `case ... is` appears
  first.
- **SEC004 missed unqualified `Spawn` calls**: the needle `"OS_LIB.SPAWN"` never matched a call
  reachable via a preceding `use GNAT.OS_Lib;`. Fixed by detecting the `use` clause first and, when
  present, also matching a standalone `SPAWN` identifier (word-boundary checked, so `Respawn_Count`
  doesn't false-positive).
- **ADA008 missed the GNATprove-scoped form**: `pragma Warnings (GNATprove, Off, ...)` -- the
  variant SPARK code commonly uses to silence gnatprove-specific warnings only -- was invisible to
  the plain `"pragma Warnings (Off"` needle. Fixed by scanning for both forms.
- **ANAL002's parameter counter inflated by string-literal contents**: `Count_Params` split a
  parameter profile's interior text on every literal `;`/`:` with no awareness of string-literal
  quoting, so a single parameter with a default value like `"a;b:c"` was misparsed into phantom
  extra parameters. Fixed with a `Mask_String_Literals` helper that blanks quoted content before
  delimiter scanning.

10 new regression tests, including one that incidentally surfaced a pre-existing, separate bug
(ADA007's `"TODO"` needle also matches the substring inside an identifier like `Todo` -- not one
of the 41 confirmed findings, so left alone rather than scope-creeping into a new fix); 634/634
checks passing (was 626).

### Changed (deep-audit PR7/11 + issue #69 -- hara/tara schema conformance)

Continuing the multi-agent audit fix series, and starting on issue #69's broader schema-conformance
work (x-FuSa spec v1.13.0/v1.14.0). This PR is a breaking rewrite of `.fusa-hara.json`/
`.fusa-tara.json` and the `hara`/`tara` commands' JSON output, not a small fix like PR1-6 -- both
findings it addresses require a genuinely different data model, not a field rename.

- **Silent success on missing input**: `hara`/`tara` used to unconditionally scaffold a template
  and exit 0 on a missing input file, including under `--format json` (where the response wasn't
  even JSON -- just a stray "created ..." text line). Section 1.2.5 MUST: "A `hara` command run
  with `--format json` on an absent file (with no `--init`/scaffold flag) MUST exit non-zero
  rather than silently report zero hazards as if the analysis were complete." Fixed by adding a
  documented `--init` flag to both commands; without it, a missing input file is now a runtime
  error (exit 3) with a real JSON `error` object under `--format json`.
- **Schema divergence**: `.fusa-hara.json` is now three cross-referenced collections
  (`operationalSituations[]`/`hazards[]`/`safetyGoals[]`, per section 1.2.5) instead of a flat
  hazard list; `risk.asil` is derived from severity x exposure x controllability via the published
  ISO 26262-3:2018 Table 4 (`Fusa.Config.Determine_Asil`) rather than accepted verbatim, and
  `safetyGoals[].fssrRefs` (MUST, >=1 entry) is checked for referential integrity into
  `.fusa-reqs.json`. `.fusa-tara.json`'s `impact` is now an SFOP object
  (safety/financial/operational/privacy, per section 9.2) instead of one generic string, and
  `risk` is derived from `attackFeasibility` x the highest SFOP impact level
  (`Fusa.Config.Determine_Tara_Risk`, a documented heuristic since ISO 21434 doesn't publish a
  single numeric formula the way ISO 26262-3 does for ASIL). `tara`'s JSON output also gained the
  canonical `summary` block (`assetsAnalyzed`/`assetsInProject`/`coveragePct`) and a new
  `--min-coverage N` gate mirroring `trace --func-coverage`; `hara`'s gained a draft
  `completeness` block. Both commands' generic errors/warnings/infos validation tally moved to
  `findingsSummary` for `tara` (the canonical `summary` key is reserved for the coverage block --
  same collision gap-report had, fixed the same way in PR3); `hara` has no such collision since its
  canonical shape has no `summary` key at all.

18 new/updated regression tests, including direct unit tests for `Determine_Asil` (covering every
corner of the published Table 4, not just one cell) and `Determine_Tara_Risk`; 626/626 checks
passing (was 604). This addresses hara/tara from issue #69's larger scope (fmea/safety-case/sas/sci
schema conformance, the cross-cutting hash-field audit, and the FUSA-STUB content-quality baseline
are tracked separately and not yet done -- `Schema_Version` stays at 1.11 until that's complete).

### Fixed (deep-audit PR6/11 -- report-extension fields, init's required standard)

Continuing the multi-agent audit fix series.

- **`trace`/`qualify --format json` omitted the §3.2 report-extension fields entirely**: `check`
  and `report` already wrote `projectRoot` (MUST) and `project`/`standard`/`asil`/`sil`/`dal`
  (SHOULD/MAY), but `trace` and `qualify` never called `Write_Report_Extension` at all. Fixed by
  adding the call to both. `qualify` doesn't require a `.fusa.json` to run at all (it tests the
  tool's own rule engine, not a project's compliance), so its `project`/`standard`/`asil`/`sil`/
  `dal` fields are filled in on a best-effort basis and simply omitted when no config is present.
- **`init` silently defaulted a missing `--standard` to `"generic"` non-interactively**: the spec
  is explicit that `standard` is just as required a value as `project.name`, and "if a required
  value is missing and stdin is not a TTY (CI), `init` MUST exit 2 rather than prompt or write a
  placeholder config" -- but only the `name` path actually did this; the `standard` path silently
  wrote a `.fusa.json` with a standard the caller never chose. Fixed to mirror `name`'s existing
  error handling exactly.

6 new/updated regression tests, plus updates to 5 existing tests that called `init` non-interactively
without `--standard` and expected the old silent-default behaviour; 604/604 checks passing (was 599).

### Fixed (deep-audit PR5/11 -- release --full and audit-pack evidence completeness)

Continuing the multi-agent audit fix series.

- **`release --full` falsely claimed fmea/boundary were unimplemented**: it unconditionally
  printed `"skipping fmea (not yet implemented)"` / `"skipping boundary (not yet implemented)"`
  and never called either -- but both are fully shipped commands (`Cmd_Fmea`, `Cmd_Boundary`).
  Fixed by actually wiring them into the evidence pipeline (`fmea.json`, `boundary.dot`), matching
  the already-established best-effort, non-gating pattern `vuln` uses (a failure in one evidence
  step doesn't abort the rest of the pipeline).
- **`audit-pack`'s hardcoded 7-file allowlist**: despite `audit-pack`'s own documented purpose --
  "all existing evidence artifacts, bundled" -- it only ever looked for 7 fixed filenames, missing
  `comp-report.json`, `vuln.json`, `badge.svg`, `boundary.dot`/`.mermaid`, `fmea.json`/`.csv`,
  `safety-case.*`, `sas.json`/`.md`, and the SPDX document. Fixed by expanding the allowlist to
  every evidence artifact filename documented in README's Evidence Artifacts table (a missing file
  is already a no-op, not an error, so this only adds coverage) plus best-effort SPDX bundling
  (its filename is `<name>-<version>.spdx.json`, so it needs `.fusa.json` loaded first; skipped
  silently if that fails, matching every other entry's graceful-absence behaviour).

4 new regression tests, including one proving `audit-pack` now bundles `boundary.dot` (never one
of the original 7 filenames) and one resolving a test-fixture ordering conflict the fmea wiring
introduced (release --full's first run now scaffolds `.fusa-fmea.json` as a side effect, same as
fmea's own documented first-run behaviour); 599/599 checks passing (was 596).

### Fixed (deep-audit PR4/11 -- qualify's self-test independence)

Continuing the multi-agent audit fix series.

- **FUSA00x known-answer case coupled to the qualified project's own state**: the case that
  proves FUSA001-004 (missing LICENSE/README/`*.gpr`/`.github/workflows`) work ran those rules
  against `--dir` -- the real project being qualified -- and reported PASS only when none of them
  fired. That makes the "known answer" whatever markers the target project happens to have, not a
  controlled fixture: a project missing any one of those four markers (completely normal, e.g.
  right after `adafusa init`) would report qualify as FAILED even though FUSA00x is working
  exactly as designed. This is exactly why `test_cli.adb`'s shared fixture had to be seeded with
  a LICENSE, README, `*.gpr`, and `.github/workflows` at setup, purely to make the self-test
  pass. Fixed by running FUSA001-004 against qualify's own scratch directory (already used for
  the other rules' fixtures, guaranteed to hold none of the four markers) instead of `--dir` --
  the self-test is now a real, project-independent known answer.
- **No positive-detection coverage**: the same case only ever asserted "none of FUSA001-004
  fired" as one combined bucket; it never proved each rule actually *fires* when its marker is
  missing. Split into four individual `rule-FUSA00x-known-answer` cases (matching every other
  rule's one-case-per-rule convention), each now asserting the rule does fire against the
  marker-free scratch directory.
- **Inconsistent `--format` error message**: `qualify`'s unsupported-format error was the only
  one of ~20 commands missing the `(supported: ...)` suffix.

3 new regression tests, including one against a project deliberately built with none of the four
FUSA00x markers (proving qualify now passes regardless); 596/596 checks passing (was 594).

### Fixed (deep-audit PR3/11 -- gap-report/hara/tara schema conformance)

Continuing the multi-agent audit fix series. Two of these are genuinely my own bugs from
implementing these commands earlier in the project: I personally re-verified both against the
FuSaOps spec text before trusting the audit's report.

- **gap-report `kind` field**: emitted `"<standard>-gap-report"` (e.g. `"do178c-gap-report"`)
  instead of the spec's closed `kind` enum literal, which is `"gap-report"` for every standard
  (§3.1) -- py-FuSa shipped this exact mistake previously and had to fix it, per the spec's own
  change history.
- **hara/tara `kind` fields**: emitted the bare command name (`"hara"`, `"tara"`) instead of the
  report-document form (`"hara-report"`, `"tara-report"`) that §1.2.5/§9.2 require.
- **gap-report `summary`/`objectiveSummary` collision**: the canonical §9.3 schema reserves
  `"summary"` for the objectives tally (`total`/`satisfied`/`partial`/`gaps`), but the command
  wrote that tally under `"objectiveSummary"` while a *different*, generic errors/warnings/infos
  tally of the objectives-file's own config-validation findings (GAP001/GAP002) was written under
  `"summary"` via the shared `Write_Summary` helper -- backwards, and if simply renamed
  `objectiveSummary` to `summary` without touching the other call, the two would have collided
  under the same key. Fixed by giving `Write_Summary` an optional `Key` parameter (defaulting to
  `"summary"` for every other caller) and having gap-report use the canonical `"summary"` for the
  objectives tally and `"findingsSummary"` for the config-validation tally.
- **gap-report invariant violation**: the spec requires `satisfied + partial + gaps = total` and
  says "a consumer MUST map any unrecognised status to gap (fail-safe)" -- but `Load_Gap_Objectives`
  only *warned* (GAP002) about an objective with an unrecognised status string, leaving `O.Status`
  set to the raw invalid text, which then matched none of the three tally branches, breaking the
  invariant for any malformed-but-loadable objectives file. Fixed by actually normalising the
  status to `"gap"` when it doesn't match `satisfied`/`partial`/`gap`.

6 new regression tests (including one exercising all four fixes together against a single
objectives file with a satisfied, an unrecognised-status, and an id-less objective); 594/594
checks passing (was 588).

### Fixed (deep-audit PR2/11 -- JSON parser hardening)

Continuing the multi-agent audit fix series. `Fusa.Json` is the parser behind every config and
evidence file this tool reads (`.fusa.json`, `.fusa-reqs.json`, `.fusa-dispositions.json`,
`.fusa-metrics.json`, `.fusa-fmea.json`, ...), so a bug here can affect every command. Three
issues found:

- **Silent overflow to Infinity**: `Parse_Number` already validated the RFC 8259 grammar (leading
  zeros, bare exponents, etc. were rejected), but a syntactically valid number that overflows
  `Long_Float`'s range -- e.g. `1e400` -- was still handed to `Long_Float'Value`, which GNAT
  converts to IEEE +/-Infinity rather than raising. Verified directly: `Long_Float'Value("1e400")`
  returns `+Inf` with no exception. That non-finite value then propagated silently into every
  downstream consumer (RPN scores, coverage percentages, metrics) with no error at the point of
  parsing. Fixed by comparing the parsed value against `Long_Float'Last`/`-Long_Float'Last` and
  raising `Json_Error` if it's out of range.
- **Unescaped control characters accepted**: RFC 8259 section 7 requires control characters
  (U+0000-U+001F) inside a string literal to be escaped (e.g. as `\n`); `Parse_String_Literal`
  copied any character that wasn't `"` or `\` straight into the result with no check, silently
  accepting invalid JSON. Fixed by rejecting any literal character below `16#20#`.
- **O(n^2) duplicate-key scan**: `Parse_Object` rescanned every previously-parsed member on each
  new key to detect duplicates (needed for the documented last-value-wins behavior), an O(n^2)
  cost on an object with n keys -- a CPU-exhaustion risk on adversarial input. Fixed by tracking
  each key's index in a hashed map alongside the existing order-preserving `Members` vector, so a
  duplicate is found in O(1) without changing iteration order or the public API.

9 new regression tests; 588/588 checks passing (was 579).

### Fixed (deep-audit PR1/11 -- critical security)

A full multi-agent audit (8 independent dimensions, every finding adversarially verified by 3
skeptic reviewers before being trusted) found 41 confirmed issues. Fixing them in grouped PRs,
starting with the two critical security bugs:

- **Path traversal via `sourceDirs`** (CRITICAL): `Fusa.Files.Normalize_Dot_Segments` stripped bare
  `"."` segments but never resolved `".."`, so `Join(Project_Root, "../secret")` produced the
  literal string `"Project_Root/../secret"` — which `Relative_To`'s purely-lexical prefix check then
  WRONGLY treated as "inside" `Project_Root` (the string genuinely does start with
  `"Project_Root/"`), silently letting a crafted `.fusa.json`'s `sourceDirs` entry escape the
  project root for reads, and — via `fix --apply` — **writes**, since `fix` resolves its write
  target the same way. Fixed at the source: `Normalize_Dot_Segments` now properly resolves `".."`
  by popping the preceding real segment (verified against a dozen cases including multi-level and
  non-absolute paths via a standalone debug harness before wiring in), and a new
  `Fusa.Files.Is_Within` predicate makes `Find_Source_Files` reject (silently skip, like a
  non-existent directory already was) any `sourceDirs` entry that still resolves outside the
  project root — defense in depth, not reliant on the string-level fix alone. Verified end-to-end
  with a reproduction harness: the write target for the crafted `fix --apply` scenario is now
  provably inside the project root, and the scan now returns zero files for an escaping entry.
- **Disposition file-scope bypass** (CRITICAL): `Apply_Dispositions`'s `Matches` function had
  `return E.Line = 0 or else (E.File = F.Loc.File and then E.Line = F.Loc.Line);` — when a
  disposition entry named a `file` but omitted `line` (a legitimate, documented file-scoped
  waiver), `E.Line = 0` short-circuited to `True` for *any* finding of that rule, without ever
  consulting `E.File`. A waiver meant for one file silently suppressed the same rule
  project-wide, defeating `check --strict`'s gate everywhere else. Fixed to check `E.File` in both
  branches.

1 new requirement (REQ-117, for `Is_Within`); 579 checks passing (was 566). 10 more PRs to follow
covering the remaining 39 confirmed findings.

### Added (fix -- command-catalog completeness, part 4 of 4 -- full §9 catalog)

The final spec §9.3 command, completing ada-FuSa's implementation of every applicable MUST/SHOULD/
MAY command in the FuSaOps command catalog (§9.1/§9.2/§9.3; `misra` is the sole deliberate
exception -- it maps only to `misra-c`/`misra-cpp`, and there is no MISRA-Ada standard to
gap-report against).

- **`fix`** (§9.3 MAY): the only command that writes to a project's actual source files rather
  than a `.fusa-*.json` sidecar or a generated report. New `Fusa.Fix.Fix_Content` (pure
  `String -> String`, verified idempotent via a standalone debug harness before wiring in) applies
  exactly the transforms `ADA006`/`LINT001`-`LINT003` already flag: tabs to single spaces, trailing
  whitespace stripped, 2+ consecutive blank lines collapsed to one, file normalised to exactly one
  trailing newline. Nothing requiring a judgement call is ever touched -- not an unjustified
  `pragma Suppress`, not a line-length violation, not any security finding. Defaults to a dry run
  (`--apply` required to write anything); without `--apply`, gate-fails if any file would change,
  the `gofmt -l`/`prettier --check` CI pattern.
- Caught a real self-check regression while building this: `fusa-fix.ads`'s own doc comment
  mentioned `` `pragma Suppress` `` (backtick-quoted) as an example of what `fix` does *not* touch --
  the `ADA001` rule's `Is_Quoted` heuristic only recognises *double*-quoted text as "this is an
  example, not real code" (an existing, documented convention elsewhere in this file), so the
  backtick-quoted mention false-triggered `ADA001` on ada-FuSa's own source. Fixed by using double
  quotes, matching the established convention.
- 1 new requirement (REQ-116); 566 checks passing (was 548).

### Added (template -- command-catalog completeness, part 3 of 4)

- **`template list`/`template apply <name>`** (§9.3 MAY): scaffolds a source-tree/build/CI
  skeleton (`.gpr`, `src/`, `tests/`, `README.md`, `.github/workflows/ci.yml`) complementary to
  `init` (which only ever writes `.fusa.json`/`.fusa-reqs.json`). Only one template, `default`,
  exists rather than several with only cosmetic differences between them. Deliberately never
  writes a LICENSE file -- choosing a license is a legal/business decision this tool must never
  make on a user's behalf; the scaffolded README explicitly tells the user to add one. Each file
  is created only if absent, or unconditionally with `--force`, mirroring `init`'s existing
  per-file behaviour. 1 new requirement (REQ-115); 548 checks passing (was 534).

`fix` remains -- it needs more care since it would be the first command to modify a user's actual
source files.

### Added (sas -- command-catalog completeness, part 2 of 4)

- **`sas`** (§9.3 MAY, Software Accomplishment Summary): always writes both `sas.json` (envelope +
  tool-defined body, per the spec's own note on this command's shape) and `sas.md`. Every figure
  is mechanically aggregated from data ada-FuSa already computes elsewhere -- requirement
  traced/tested/secTested counts (via `Fusa.Annotations.Scan`, the same source `trace` uses),
  `check`'s own finding counts, `comp` violations, disposition status, problem-report open/closed
  counts. Asserting the software life cycle is complete is a human sign-off this tool cannot make;
  `sas` only reports the current, honest state of that evidence, whatever it is. Always exits 0,
  like `report`. 1 new requirement (REQ-114); 534 checks passing (was 528).

`template`/`fix` remain -- `fix` in particular needs more care since it would be the first command
to modify a user's actual source files.

### Added (cyber, sci, analyze, lint -- command-catalog completeness, part 1 of 4)

Four of the seven remaining spec §9.2/§9.3 commands (`sas`/`template`/`fix` follow separately --
each needed more design work or, for `fix`, more care since it would be the first command to
modify a user's actual source files):

- **`cyber`** (§9.2 SHOULD): runs the same rule+disposition pipeline as `check`, narrowed to
  `Category = Security` and re-emitted as its own `cyber-report` kind/gate. Not a second detection
  pass -- SEC001-004 already are CWE-mapped cybersecurity findings; this is a dedicated view onto
  them.
- **`sci`** (§9.3 MAY, Software Configuration Index): every source file plus known evidence
  artifacts, each with a SHA-256 digest and byte size. Purely mechanical/derivable (unlike `sas`),
  always exits 0.
- **`analyze`** (§9.3 MAY): new `Fusa.Analyze` module, deliberately *not* registered with
  `Fusa.Engine` -- `check`'s finding set and gate are unaffected. Two new rules: `ANAL001` (a
  with-clause whose last dotted component never appears again in the file -- INFO severity, since
  a package used only via a bare `use`-clause name is a documented, verified-real false positive)
  and `ANAL002` (more than 6 formal parameters; correctly handles a parameter list whose opening
  `(` is on the line *after* the `procedure`/`function` keyword, a common Ada style that an earlier
  same-line-only version of this rule missed entirely during manual testing).
- **`lint`** (§9.3 MAY): new `Fusa.Rules_Lint` module (named `Rules_Lint`, not `Lint`, to avoid
  colliding with the existing `Fusa.Category_Kind` enum literal `Fusa.Lint`), also not
  `Fusa.Engine`-registered. `LINT001` (trailing whitespace), `LINT002` (a second+ consecutive
  blank line, flagged once per run), `LINT003` (missing or excess trailing newline).

6 new requirements (REQ-108-REQ-113); 528 checks passing (was 503).

### Added (line/function coverage)

Real `lcov` numbers (not just unit-check counts) were 85.0% lines / 94.0% functions across `src/`
going into this pass. Two targeted fixes closed most of the gap:

- Every rule's `Description` method (part of the `Rule_Interface` abstract contract, alongside
  `Id`/`Run`) was never called by any command — no `check --list-rules` or similar consumes it —
  so it was 0%-covered across all 16 rules. A direct test now asserts every registered rule's
  `Description` is non-empty. This alone took function coverage from 94.0% to **100%** (306/306)
  and `fusa-rules_style.adb`/`fusa-rules_project.adb`'s line coverage from ~87% to 96–97.5%.
- `fusa-cli.adb` (2739 lines, the largest file by far) was at 78.1% lines — `version --format
  json`, `check --format sarif`, and `Emit_Runtime_Error`'s JSON-format branch (shared by every
  command's no-config/invalid-config error path) were never exercised by any test. Added.

Overall: **86.2% lines / 100% functions** (was 85.0%/94.0%). `fusa-cli.adb` specifically improved
to 79.1% — still the weakest file, mostly interactive TTY-prompt code paths (`init`'s
stdin-driven fallback) and per-command rare-error branches that would need substantially more
effort per percentage point than the fixes above; left as a known area for future incremental
improvement rather than chased to a number for its own sake. 503 checks passing (was 496).

### Added (test-tag traceability completeness)

`trace`'s `testedRequirements` metric (distinct from `tracedRequirements`, which `--req-coverage`
gates on) sat at 60/107 (56%) — 47 requirements carried only an `impl` tag, no `-- fusa:test`
linking them back to the test that actually exercises them. All 47 are tagged here, several
alongside genuinely new tests for paths that turned out to have no test at all rather than just a
missing annotation:

- `Fusa.Json.Writer`'s `Null_Value` and the `Integer`/`Boolean` overloads of `Value`, and
  `Field_If_Non_Blank`'s omit-when-blank behaviour, were never exercised by any test (nor, for
  `Null_Value`, by any production code — no command ever emits a bare JSON `null`). Direct tests
  added.
- `Fusa.Config.Requirements_Exist` was dead code — declared, implemented, never called from tests
  *or* production code. A direct test added.
- `Fusa.Files.Exists`/`Is_Directory`/`Read_File`/`Write_File`/`Split_Lines` were exercised
  constantly as test-fixture-setup infrastructure but never asserted on directly. Direct
  round-trip tests added.
- The remaining ~40 (rule engine, JSON accessors, config persistence, report envelope
  composition, category/fingerprint derivation, glob matching, …) already had real test coverage;
  only the linking annotation was missing.
- `SEC001`-`SEC004`'s existing test also picked up a `-- fusa:sec-test` tag (previously
  `secTestedRequirements` was 0/107 — no requirement in the whole project was marked
  security-tested, even though the security rule pack demonstrably is).

`testedRequirements` is now 107/107 (100%); `secTestedRequirements` 1/107 (only the one
requirement that's genuinely a dedicated security-rule test — not padded to look better than it
is). 496 checks passing (was 480).

### Changed (BREAKING — §13 schema realignment)

Per spec §16 step 8 ("Evidence (SHOULD): the §9.2/§9.3 commands, following the §13 canonical
directions so the new tool doesn't recreate the existing divergences"), a self-audit found five
already-shipped commands had drifted from the spec's documented canonical direction. All five are
corrected here — a breaking change to each command's JSON shape (and, for `diff`, its CLI flags):

- **`verify`** was an auto-generated evidence-artifact-presence manifest; the spec's canonical
  shape is a test-suite-results structure. Redesigned as an input-file-driven validator (like
  `hara`/`tara`) for `.fusa-verify.json` (`{suites:[{name,tests:[{name,result}]}]}`,
  `result` one of `PASS`/`FAIL`/`SKIP`/`ERROR`, per spec §6's enum). `passed`/`failed` are always
  computed from the individual tests, never trusted from redundant input. Gates on a missing
  suite/test name or any `FAIL`.
- **`diff`** took two positional report-file paths; the canonical interface is `--baseline <file>`
  against a **live** `check` run (the "current" side is never a second saved file, mirroring how
  `report` always re-analyses rather than reading a cached file). Output narrowed from full finding
  objects to the canonical `{added:[fingerprint], removed:[fingerprint], unchanged:N}` — bare
  fingerprint strings. Severity is still used internally to decide the exit code; it's just no
  longer repeated in the output.
- **`fmea`** entries carried a single `mitigation` string; the canonical field is `mitigations[]`
  (an array).
- **`coupling`** emitted a flat array of `{name,fanIn,fanOut,total}` (finding-list-shaped, which
  the spec explicitly warns against deepening investment in); now emits the canonical graph
  `{modules:[{name,fanIn,fanOut}], edges:[{from,to,weight}], metrics:{...}}`.
- **`safety-case`** embedded `supportedBy`/`inContextOf` directly on each node in `--format json`
  output; the canonical shape promotes them to a top-level `edges:[{from,to,type}]` array
  (`.fusa-safety-case.json`'s *input* shape is unaffected — it still records them per-node, since
  that's the more natural authoring format; only the rendered JSON output moved).

No change to `hara`/`tara`/the standards gap-report commands, which were already conformant.

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
- **Evidence & verification utilities** (#26, partial — `verify`/`diff`/`badge` per the issue's own
  recommended starter scope; `safety-case`/`fmea`/`coupling` deferred to follow-ups since they need
  real design work, e.g. what Ada-specific evidence a GSN safety-case argument node should point to):
  - `verify`: an evidence manifest listing every known artifact filename's presence, SHA-256 digest,
    and byte size. Always exits 0 — it documents current evidence state rather than gating on it.
  - `diff <a> <b>`: compares two report documents by finding fingerprint (§4.2), reporting
    added/removed/unchanged. Gates on any added ERROR finding (or, with `--strict`, any addition at
    all); a removed finding never gates.
  - `badge`: a self-contained SVG status badge (new `Fusa.Badge` module, hand-rolled shields.io-flat
    style — no real font metrics without an external dependency, so text width is a per-character
    estimate) driven by the same rule+disposition pipeline as `check`, or an explicit
    `--message`/`--color` override that skips analysis entirely. Always exits 0.
  - 4 new requirements (REQ-098–REQ-101).
- **`boundary`/`impact` commands** (#26, continued): new `Fusa.Deps` module, a text-based
  `with`-clause scanner (like `Fusa.Comp`, no full Ada parser) that builds an intra-project unit
  dependency graph — a unit's `.ads`/`.adb` merge into one node; only context-clause `with`/`private
  with` count (an Ada 2012+ aspect-specification `with`, which can only appear after the unit's own
  declaration starts, is correctly excluded by stopping the scan there); dependencies outside the
  project are filtered out. `boundary` renders the graph as Graphviz DOT or Mermaid. `impact
  <file...>` resolves each file to its unit and reverse-BFS's the graph for every unit that
  (directly or transitively) depends on it — deliberately conservative, since most files transitively
  reach the shared root package. Both always exit 0. 3 new requirements (REQ-102–REQ-104).
- **`coupling`/`fmea`/`safety-case` commands** (#26, complete): the final three commands from the
  issue's evidence-and-verification family.
  - `coupling`: reuses `Fusa.Deps`'s graph to report each unit's fan-in/fan-out/total, sorted
    most-coupled-first. Explicitly documented as a structural proxy metric, **not** a full DO-178C
    §6.4.4.3 data/control coupling analysis (which needs source-level parameter/global-data flow
    analysis this tool doesn't perform). Always exits 0.
  - `fmea`: input-file-driven validator for `.fusa-fmea.json` (new `Fusa.Config` `Fmea_Entry`
    type), same rationale as `hara`/`tara` — failure-mode identification and
    severity/occurrence/detection ratings are a human safety engineer's judgement this tool cannot
    generate. Computes RPN = severity × occurrence × detection when not given; flags (never
    silently overwrites) an explicit `rpn` that disagrees. Supports text/json/csv. Gates only on a
    missing id.
  - `safety-case`: input-file-driven validator/renderer for `.fusa-safety-case.json` (new
    `Fusa.Config` `Gsn_Node` type) — a GSN goal/strategy/context/solution/assumption/justification
    graph with `supportedBy`/`inContextOf` edges. Validates only *structural* well-formedness
    (unique non-empty ids; every edge resolves to a real node — a dangling reference is an ERROR,
    since it's a genuinely broken argument, not just an incomplete field) and renders a
    cycle-safe text/Markdown outline or a Mermaid diagram (goal/strategy/context/solution get
    distinct GSN-ish node shapes); never claims the argument itself is sound or complete. Gates on
    a missing id or a dangling reference.
  - 3 new requirements (REQ-105–REQ-107); 472 checks passing (was 436). **Closes #26.**

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
