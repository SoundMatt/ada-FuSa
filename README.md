# ada-FuSa — Ada/SPARK Functional Safety Toolkit

[![CI](https://github.com/SoundMatt/ada-FuSa/actions/workflows/ci.yml/badge.svg)](https://github.com/SoundMatt/ada-FuSa/actions/workflows/ci.yml)
[![x-FuSa spec](https://img.shields.io/badge/x--FuSa%20spec-v1.11-blue)](https://github.com/SoundMatt/FuSaOps)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-green)](LICENSE)

**adafusa** is the Ada implementation of the [x-FuSa specification](https://github.com/SoundMatt/FuSaOps) — a
tool-qualification-grade functional safety CLI, implemented independently for seven languages
(go-FuSa, c-FuSa, cpp-FuSa, rust-FuSa, py-FuSa, java-FuSa, and now ada-FuSa) so that
[FuSaOps](https://github.com/SoundMatt/FuSaOps) can orchestrate all of them without tool-specific code.

Ada/SPARK is the reference language for DO-178C Level A avionics software and for formal
verification — a gap none of the other six x-FuSa tools natively cover. ada-FuSa's flagship
differentiator, SPARK proof-coverage via `gnatprove`, is **deferred to a later release** (see
[Known limitations](#known-limitations-v010) below); this first release lands a complete,
spec-conformant CLI contract for that to build on.

## Features

- **41 commands** spanning the full x-FuSa spec surface (see the [Commands](#commands) table
  below): `version`, `capabilities`, `init`, `check`, `trace`, `qualify`, `release`, `audit-pack`,
  `report` are the §9.1 MUST set; the rest are §9.2 SHOULD/§9.3 MAY evidence, risk-analysis, and
  hygiene commands.
- **Zero runtime dependencies** — pure Ada 2022 standard library. JSON, SHA-256, CRC-32, and ZIP
  are all hand-rolled, since none of them are part of the Ada standard library. GNAT is a build/dev
  dependency only.
- **Self-qualifying** — `adafusa qualify` runs a known-answer test against every registered rule
  and writes `qualify-report.json` with a reproducible `sha256:` integrity `hash` (RFC 8785 JCS
  canonicalization).
- **16 starter rules**: `ADA001`–`ADA008` (Ada Quality and Style Guide rather than a ported
  MISRA-style list, see [SoundMatt/FuSaOps#78](https://github.com/SoundMatt/FuSaOps/issues/78)),
  `SEC001`–`SEC004` (CWE-mapped security), `FUSA001`–`FUSA004` (project-structure).
- **Evidence artifacts**: `sbom.json` (x-FuSa SBOM v1), `qualify-report.json`, SARIF 2.1.0,
  `audit-pack.zip`.

## Quick Start

```bash
# Build (requires GNAT + gprbuild)
gprbuild -p -P adafusa.gpr

# Initialise a project
bin/adafusa init --name my-project --standard iso26262 --asil ASIL-B

# Run all rules
bin/adafusa check

# Tool qualification (required for safety case)
bin/adafusa qualify

# Full evidence pipeline
bin/adafusa release --full
```

Or via Docker:

```bash
docker build -t adafusa .
docker run --rm -v $(pwd):/project adafusa check
```

## Installation

```bash
git clone https://github.com/SoundMatt/ada-FuSa.git
cd ada-FuSa
gprbuild -p -P adafusa.gpr

# Install to PATH
cp bin/adafusa ~/bin/
```

Requires GNAT 12+ and gprbuild. On Debian/Ubuntu: `apt install gnat gprbuild`. On macOS, the
[Alire](https://alire.ada.dev) package manager (`alr toolchain --select gnat_native gprbuild`) is
the simplest route, since GNAT is not distributed via Homebrew.

## Commands

| Command | Description | Formats |
|---------|-------------|---------|
| `adafusa version [--format text\|json]` | Print tool + spec version | text, json |
| `adafusa capabilities [--format json]` | Machine-readable command/format inventory | json |
| `adafusa init [name] [--name] [--standard] [--asil\|--sil\|--dal] [--force] [--migrate]` | Create `.fusa.json` + `.fusa-reqs.json` (or rename legacy files to canonical names) | text |
| `adafusa check [--dir] [--strict]` | Run all rules and report findings | text, json, sarif, html |
| `adafusa trace [--dir] [--gaps] [--req-coverage N] [--sec-tested N] [--func-coverage N]` | Requirement ↔ code traceability matrix | text, json, html, md |
| `adafusa qualify [--dir]` | Run the tool-qualification known-answer suite | text, json |
| `adafusa release [--dir] [--output-dir] [--spdx-version 2.2\|2.3] [--full]` | Generate `sbom.json` (+ optional SPDX, + full evidence pipeline) | json |
| `adafusa audit-pack [--dir] [--output]` | Bundle all evidence artifacts into a ZIP | json |
| `adafusa report [--dir]` | Re-run analysis; always exits 0 | text, json, sarif, html, md |
| `adafusa comp [--dir] [--threshold N] [--dal DAL-A\|B\|C\|D]` | McCabe cyclomatic complexity per function (DO-178C §6.3.4) | text, json |
| `adafusa hara [--dir] [--init]` | Load/validate `.fusa-hara.json` hazard analysis (ISO 26262-3, section 1.2.5 canonical shape); `--init` scaffolds an empty template if absent, otherwise a missing file is a runtime error | text, json |
| `adafusa tara [--dir] [--init] [--min-coverage N]` | Load/validate `.fusa-tara.json` threat analysis (ISO 21434 ch.15, section 9.2 canonical shape); `--init` scaffolds an empty template if absent, otherwise a missing file is a runtime error | text, json |
| `adafusa vuln [--dir]` | Dependency vulnerability scan (no CVE database integrated yet — see limitations) | text, json |
| `adafusa req list\|add <id> <title>` | Manage `.fusa-reqs.json` from the CLI | text, json |
| `adafusa disposition list\|add <fp-or-ruleId> <status> [rationale]` | Manage `.fusa-dispositions.json` waivers from the CLI | text, json |
| `adafusa pr init\|list\|add\|close` | Problem-report log (DO-178C §11.17) | text, json |
| `adafusa metrics [record]` | Append-only safety-metrics history (`.fusa-metrics.json`) | text, json |
| `adafusa sign sign\|verify <file> --key <key>` | HMAC-SHA256 evidence-file signing | text |
| `adafusa hooks install\|remove` | Git pre-commit hook running `check --strict` | text |
| `adafusa do178\|iso26262\|iso21434\|iec61508\|iec62443\|unece\|slsa [--dir]` | Standards gap-report: load/validate `.fusa-<standard>-objectives.json`; scaffolds a template if absent | text, json |
| `adafusa verify [--dir]` | Load/validate `.fusa-verify.json` test-suite results; scaffolds a template if absent | text, json |
| `adafusa diff --baseline <file> [--dir] [--strict]` | Compare a live `check` run against a prior `check --format json` baseline, by finding fingerprint | text, json |
| `adafusa badge [--dir] [--label] [--message] [--color]` | SVG status badge (red/yellow/green from `check`, or a custom `--message`/`--color`); always exits 0 | svg |
| `adafusa boundary [--dir] [--format dot\|mermaid]` | Package/unit dependency graph from `with`-clause scanning; always exits 0 | dot, mermaid |
| `adafusa impact <file...> [--dir]` | Which project units are (transitively) affected by changing the given files; always exits 0 | text, json |
| `adafusa coupling [--dir]` | Structural fan-in/fan-out coupling metric per unit; always exits 0 | text, json |
| `adafusa fmea [--dir] [--min-coverage N]` | Load/validate `.fusa-fmea.json` design FMEA (IEC 60812 / AIAG-VDA, section 9.2 canonical shape); scaffolds a template if absent | text, json, csv |
| `adafusa safety-case [--dir]` | Load/validate/render `.fusa-safety-case.json` GSN safety case; scaffolds a template if absent | text, json, md, mermaid |
| `adafusa cyber [--dir] [--strict]` | `check`'s findings narrowed to `security` category, as a dedicated `cyber-report` | text, json |
| `adafusa sci [--dir]` | Software Configuration Index: every source file + evidence artifact, SHA-256 + size; always exits 0 | text, json |
| `adafusa analyze [--dir] [--strict]` | Deeper own-pass static analysis (unused with-clauses, long parameter lists), separate from `check` | text, json |
| `adafusa lint [--dir] [--strict]` | General-correctness/formatting hygiene (trailing whitespace, blank-line runs, trailing newline) | text, json |
| `adafusa sas [--dir] [--output-dir]` | Software Accomplishment Summary (DO-178C section 11.20): a `checklist[]` of the section 11 data items, `present` set only from real artifacts this tool can see on disk; always writes both `sas.json` and `sas.md`; always exits 0 | json, md |
| `adafusa template list\|apply <name> [--dir] [--project-name] [--force]` | Scaffold a source-tree/build/CI skeleton (`.gpr`, `src/`, `tests/`, README, CI workflow) complementary to `init`; never writes a LICENSE | text, json |
| `adafusa fix [--dir] [--apply]` | Whitespace/formatting-only auto-fix (tabs, trailing whitespace, blank-line runs, trailing newline); dry-run by default, gate-fails if any file would change | text, json |

**Shared flags:** `--dir <path>` (project root, default `.`), `--output <file>` (write instead of
stdout), `--no-color` (accepted; ada-FuSa does not currently emit ANSI colour), `--format <fmt>`.

## Configuration

`.fusa.json` (created by `adafusa init`):

```json
{
  "configVersion": "1.0",
  "project": {
    "name": "my-project",
    "version": "0.1.0"
  },
  "standard": "iso26262",
  "asil": "ASIL-B",
  "sourceDirs": ["src"],
  "excludePatterns": ["*.gen.adb"]
}
```

`.fusa-reqs.json`:

```json
{
  "requirements": [
    { "id": "REQ-001", "title": "Checksum must be validated", "level": "SW" }
  ]
}
```

## Annotation Syntax

Ada's only comment form is `--`, so annotations are plain trailing comments:

```ada
package Checksum is

   --  fusa:req REQ-001
   function Compute (Data : String) return Natural;

end Checksum;
```

```ada
with Checksum;
procedure Checksum_Test is
   --  fusa:test REQ-001
   R : constant Natural := Checksum.Compute ("abc");
begin
   null;
end Checksum_Test;
```

One requirement id per `fusa:req` / `fusa:test` / `fusa:sec-test` line; trailing free-text
description after the id is fine, but a second id on the same line is reported as a malformed
annotation (WARNING).

### Function-level tagging and `--func-coverage` (spec §1.4.1, SHOULD/phased)

`trace --func-coverage N` gates on the percentage of a project's **public** function/procedure
declarations that carry a `fusa:req` tag directly above them (or anywhere in the contiguous
comment block immediately above, i.e. a multi-line doc comment). The counting rule:

- Only declarations in a `.ads` file's visible (public) part count — anything after a bare
  `private` line, and anything in a `.adb` body that isn't also declared in the matching `.ads`,
  is excluded (a `.adb`-only helper isn't part of the package's public API).
- `.ads` files under a `tests/`/`test/` directory are excluded — §1.4.1 targets a tool's own
  safety-relevant implementation, not test scaffolding, even though the same directory is
  otherwise in-scope for `fusa:req`/`fusa:test` annotation scanning.
- Generic formal subprogram parameters (`with function`/`with procedure`) are not counted.
- Each overload is counted separately — three overloads of the same name need three tags (which
  may reference the same requirement id; nothing requires distinct ids for closely-related
  overloads).
- `--func-coverage` is **not** implied by `--strict` (unlike `--req-coverage`/`--sec-tested`) — it
  is a distinct axis that must be requested explicitly, since it is still a phased/SHOULD provision.

### Dispositions / waivers (spec §4.1, SHOULD)

`check` and `report` read a `.fusa-dispositions.json` at the project root, if present, and apply
each entry's `status` to matching findings before gating:

```jsonc
{
  "dispositions": [
    { "fingerprint": "sha256:…",  "status": "accepted", "note": "reviewed in SC-42" },
    { "ruleId": "ADA002", "file": "src/x.adb", "line": 42, "status": "deferred" },
    { "ruleId": "ADA005", "status": "rejected" }
  ]
}
```

- **Matching** — `fingerprint` (primary; matches when both the finding and the entry carry one) →
  `ruleId` + `file` + `line` (fallback) → `ruleId` only (rule-level fallback, suppresses every
  finding for that rule project-wide).
- **`accepted`/`deferred`** are waivers: the finding stays in the output (marked via its
  `disposition` field) but does not by itself cause `check` to exit `1`.
- **`rejected`** is *not* a waiver — it records that a proposed waiver was denied, so the finding
  remains fully open and still gates.
- An `accepted`/`deferred` entry that matches no finding in the current run (e.g. stale after a
  refactor) surfaces a `DISP001` WARNING (category `config`); an orphaned `rejected` entry is
  silent, since a denied waiver with no matching finding just means the issue was fixed.
- Manage this file from the CLI with `adafusa disposition list|add <fp-or-ruleId> <status> [rationale]`,
  or edit it directly.

## Rule Reference

### ADA — Ada Quality and Style Guide

| Rule | Severity | Description |
|------|----------|--------------|
| ADA001 | ERROR | `pragma Suppress` without a `-- fusa:unsafe` justification |
| ADA002 | WARNING | blanket `when others =>` exception handler without `-- fusa:unsafe` |
| ADA003 | ERROR | `Unchecked_Conversion` without a `-- fusa:unsafe` justification |
| ADA004 | WARNING | `Unchecked_Deallocation` without a `-- fusa:unsafe` justification |
| ADA005 | WARNING | line exceeds 79 characters |
| ADA006 | WARNING | line contains a tab character |
| ADA007 | INFO | `TODO` comment marks incomplete work |
| ADA008 | WARNING | `pragma Warnings (Off, ...)` without a `-- fusa:unsafe` justification |

### SEC — CWE-mapped security rules

| Rule | Severity | CWE | Description |
|------|----------|-----|--------------|
| SEC001 | ERROR | CWE-798 | identifier ending in `password` directly assigned a string literal |
| SEC002 | ERROR | CWE-798 | identifier ending in `secret`/`api_key` directly assigned a string literal |
| SEC003 | WARNING | CWE-327 | `GNAT.MD5` referenced (a cryptographically broken hash) |
| SEC004 | WARNING | CWE-78 | `GNAT.OS_Lib.Spawn` referenced (command injection risk if any argument is untrusted) |

All four honour a trailing `-- fusa:unsafe <reason>` justification comment. SEC001/SEC002 are
line-level heuristics, not real dataflow analysis: they cannot distinguish a directly-assigned
literal from one that merely *appears* as an argument on the same line (e.g. a literal env-var
*name* passed to a runtime lookup function) — `-- fusa:unsafe` is the escape hatch for that case.

### FUSA — project-structure rules

| Rule | Severity | Description |
|------|----------|--------------|
| FUSA001 | WARNING | no `.gpr` project file found at the project root |
| FUSA002 | WARNING | no `LICENSE`/`LICENSE.md`/`LICENSE.txt` found at the project root |
| FUSA003 | WARNING | no `README.md`/`README`/`README.txt`/`README.rst` found at the project root |
| FUSA004 | WARNING | no `.github/workflows` CI configuration found at the project root |

Unlike the rules above, these check for file/directory *presence* at the project root rather than
scanning source content — each fires at most once per `check` run, regardless of `--dir`'s file count.

### ANAL — deeper own-pass static analysis (`analyze` command, not `check`)

| Rule | Severity | Description |
|------|----------|--------------|
| ANAL001 | INFO | a with-clause whose last dotted component never appears again in the file |
| ANAL002 | WARNING | a subprogram with more than 6 formal parameters |

`analyze` is a separate command from `check` — these findings never appear in `check`'s output and
never affect its gate. ANAL001 is a **documented heuristic with a real false-positive mode**: a
package used only via a bare name brought into scope by a `use` clause (e.g. `use Ada.Text_IO;`
followed only by `Put_Line (...)`, never writing `Text_IO` again) looks unused to this check even
though it isn't — hence INFO severity, which never gates even under `--strict`.

### LINT — general-correctness / formatting hygiene (`lint` command, not `check`)

| Rule | Severity | Description |
|------|----------|--------------|
| LINT001 | WARNING | trailing whitespace at the end of a line |
| LINT002 | WARNING | a second (or later) consecutive blank line |
| LINT003 | WARNING | file doesn't end with exactly one trailing newline (missing, or more than one) |

## Cyclomatic Complexity (`comp`)

`comp` computes McCabe cyclomatic complexity V(G) per subprogram body in `.adb` files via
text-based decision-point counting — there is no full Ada parser or control-flow graph. V(G) = 1
plus one per: `if`/`elsif`, `case`/exception-handler `when` (including `when others`), `for`/`while`
loop headers, `exit when`, and `and then`/`or else`. An unconditional `loop ... end loop;` with no
`exit when` contributes no decision on its own.

**Documented limitation**: a nested subprogram's decision points are attributed to its innermost
enclosing subprogram rather than reported as a separate result — Ada style guides for
safety-critical code generally discourage deep local nesting, so this is a reasonable
approximation, but it means a nested subprogram's own complexity is never shown standalone.

## Standards Gap Reports

`do178`, `iso26262`, `iso21434`, `iec61508`, `iec62443`, `unece`, and `slsa` each load/validate a
`.fusa-<standard-id>-objectives.json` file at the project root (canonical standard ids:
`do178c`, `iso26262`, `iso21434`, `iec61508`, `iec62443-4-1`, `unece-r155`, `slsa`), scaffolding a
starter template on first run:

```jsonc
{
  "objectives": [
    { "id": "DO178-REQ-1", "title": "…", "clause": "…", "status": "gap",
      "evidence": [], "findings": [] }
  ]
}
```

**ada-FuSa cannot determine whether your project actually satisfies a standard's objectives** —
that is a human assessor's judgement call backed by real evidence, so these commands never fabricate
a compliance determination. They follow the same input-file-driven pattern as `hara`/`tara`: a human
records each objective's `status` (`satisfied`/`partial`/`gap`) and supporting `evidence`/`findings`,
and the tool validates structure (a missing `id` is an ERROR that gates; an unrecognised `status` is
a WARNING) and renders an `objectiveSummary` count. **The mere presence of `gap`-status objectives
never gates** — that is the normal, expected state of in-progress compliance work.

`do178`'s starter template ships a small, explicitly non-authoritative checklist (ids like
`DO178-PLAN-1`, `DO178-REQ-1`, …) covering the well-known DO-178C process areas (planning,
requirements, design, code, verification, testing, structural coverage, configuration management,
quality assurance) — it is **not** a transcription of RTCA's official Annex A objective table, and
uses ada-FuSa's own id scheme rather than claiming to replicate DO-178C's exact numbering. Treat it
strictly as a starting checklist; replace/extend it with your project's actual PSAC/SOI-derived
objectives. The other six standards' commands scaffold an empty template and rely entirely on your
own objective list.

## Auto-fix (`fix`)

`fix` is the **only** ada-FuSa command that writes to a project's actual source files, rather than
a `.fusa-*.json` sidecar or a generated report — a meaningfully more consequential action than
anything else this tool does, so its scope is deliberately narrow:

- It fixes **only** whitespace/formatting issues that are 100% mechanical and carry zero semantic
  risk — the exact set `ADA006` (tabs) and `LINT001`-`LINT003` (trailing whitespace, blank-line
  runs, trailing-newline hygiene) already flag. `Fusa.Fix.Fix_Content` is a pure `String -> String`
  function, verified idempotent (`Fix_Content (Fix_Content (S)) = Fix_Content (S)`) before being
  wired into the CLI.
- It **never** touches anything requiring a judgement call — an unjustified `pragma Suppress`, a
  line-length violation that would need re-wrapping, any `SEC`-category security finding, an
  `ANAL001` possibly-unused `with` (which has a documented real false-positive mode). "Safe to
  auto-apply" and "safe to auto-decide" are different claims, and `fix` only ever makes the first.
- It **defaults to a dry run**: without `--apply`, nothing is ever written to disk, and the command
  gate-fails (exit `1`) if any file would change — the same `gofmt -l`/`prettier --check` pattern,
  so a project can fail CI on unformatted code without `fix` ever touching a file unless a human
  explicitly runs it with `--apply` (typically locally, not in CI).

## Evidence & Verification Utilities

- **`verify`** loads/validates `.fusa-verify.json` — a test-suite results file (`{ suites: [{
  name, tests: [{name, result}] }] }`, `result` one of `PASS`/`FAIL`/`SKIP`/`ERROR`) — following the
  same input-file-driven pattern as `hara`/`tara`: ada-FuSa cannot itself determine whether your
  project's verification activities passed, so a human or a CI pipeline records each test's outcome
  and `verify` only aggregates (`passed`/`failed` are always *computed* from the individual tests,
  never trusted from redundant input) and validates structure. Gate-fails on a missing suite/test
  name, or when any test's `result` is `FAIL`.
- **`diff --baseline <file>`** compares a **live** `check` run against a prior `check --format json`
  snapshot, by finding `fingerprint` (§4.2) — like `report`, the "current" side is always freshly
  analysed, never read from a second file. Gate-fails if any *added* finding is `ERROR` severity, or
  (with `--strict`) if anything was added at all; a finding that was *removed* never gates — fixing
  something is never a failure. Useful in CI to fail a PR that introduces new findings against a
  saved baseline.
- **`badge`** renders a self-contained shields.io-style SVG status badge (new `Fusa.Badge` module,
  zero external dependencies — no real font metrics, so text width is estimated from character
  count). By default it runs the same rule + disposition pipeline as `check` and picks
  red/`N errors`, yellow/`N warnings`, or green/`passing`; `--message`/`--color` bypass that entirely
  to render an arbitrary custom badge (e.g. a version badge) without analysing the project at all.
  Always exits `0` — a badge's job is to *display* a failing status, not to fail itself.
- **`boundary`**/**`impact`** share a new `Fusa.Deps` module: a text-based `with`-clause scanner
  (like `comp`, no full Ada parser) that builds a directed graph of intra-project unit dependencies.
  A unit's `.ads`/`.adb` merge into one graph node; only context-clause `with`/`private with` are
  counted — an Ada 2012+ aspect-specification `with` (e.g. `... with Convention => C;`), which can
  only appear *after* a unit's own declaration has started, is correctly excluded; dependencies
  outside the project (e.g. `Ada.Text_IO`) are filtered out. `boundary` renders the whole graph as
  Graphviz DOT or Mermaid. `impact <file...>` resolves each given file to its unit and reports every
  other unit that (directly or transitively) depends on it — **this is deliberately conservative**:
  since most files `with` the project's own root package, a change to almost anything can show a
  broad transitive impact set through that shared root, the same way a real Ada compiler would
  reconsider all of those units' dependencies. Both always exit `0` (purely descriptive; a file that
  isn't a recognised project unit is reported as such, not treated as an error).
- **`coupling`** reuses the same `Fusa.Deps` graph, emitted as `--format json`'s `{ modules:
  [{name, fanIn, fanOut}], edges: [{from, to, weight}], metrics: {...} }` — the spec's documented
  canonical direction for this command (a graph, not a flat finding-list-shaped array; an earlier
  revision of this command used the latter, which the spec explicitly warns against deepening
  investment in). `--format text` lists units sorted by total coupling, most-coupled first. This is
  an honest **structural proxy** via the `with`-clause graph — it is explicitly *not* a full
  DO-178C §6.4.4.3 data/control coupling analysis, which requires source-level parameter and
  global-data flow analysis this tool does not perform. Treat high-coupling units as a starting
  point for manual review, not a certification artifact on its own. Always exits `0`.
- **`fmea`**/**`safety-case`** are, like `hara`/`tara`, input-file-driven validators — a Design
  FMEA's failure modes and severity/occurrence/detection ratings, and a GSN safety-case argument's
  soundness, are a human safety/certification engineer's judgement calls that ada-FuSa has no way to
  generate or verify. `fmea` loads/validates `.fusa-fmea.json`; entries carry a `mitigations[]`
  array (not a single string); the one thing this command *does* compute is RPN = severity ×
  occurrence × detection when not explicitly given, flagging (never silently overwriting) an
  explicit `rpn` that disagrees. `safety-case` loads/validates `.fusa-safety-case.json` (GSN
  goal/strategy/context/solution/assumption/justification nodes, with `supportedBy`/`inContextOf`
  relationships given per-node in the *input* file), checking only *structural* well-formedness —
  every id unique, every reference resolving to a real node, and (WARNING, `GSN004`) a solution
  node's `evidence` naming a file that actually exists in the project — and renders the argument
  as a text/Markdown outline, a Mermaid diagram, or (in `--format json`) the spec's canonical
  `{ nodes: [{id,type,text,evidence?}], edges: [{from,to,type}], completeness:
  {totalGoals,goalsWithEvidence,undeveloped} }` shape, with `supportedBy`/`inContextOf` promoted to
  a top-level `edges[]` array rather than embedded per-node. `completeness` is computed by tracing
  each goal's `supportedBy` chain for a solution node with non-blank evidence; a goal with no
  `supportedBy` chain at all counts toward `undeveloped` rather than being silently omitted. It
  never claims the argument itself is valid or complete. Both scaffold an empty template on first
  run and gate only on structural errors (missing id; for `safety-case`, also a dangling
  reference — a false evidence claim is a WARNING, not a gate failure).

## Evidence Artifacts

| File | Generated by | Description |
|------|---------------|--------------|
| `qualify-report.json` | `adafusa qualify` | Tool qualification report |
| `sbom.json` | `adafusa release` | x-FuSa SBOM v1 (zero runtime deps ⇒ empty `components`) |
| `provenance.json`, `artifact-manifest.json` | `adafusa release --full` | Minimal provenance/manifest documents |
| `<name>-<version>.spdx.json` | `adafusa release --spdx-version` | SPDX 2.2/2.3 software bill of materials (opt-in) |
| `audit-pack.zip` | `adafusa audit-pack` | All existing evidence artifacts, bundled |
| `comp-report.json` | `adafusa comp --format json --output comp-report.json` | Per-function cyclomatic complexity (consumed by FuSaOps v1.70.0+) |
| `vuln.json` | `adafusa vuln --format json` / `release --full` | Dependency vulnerability finding-list (always clean — see limitations) |
| `badge.svg` | `adafusa badge --output badge.svg` | Status badge for READMEs/dashboards |
| `boundary.dot`/`boundary.mermaid` | `adafusa boundary --output` | Package/unit dependency graph |
| `fmea.json`/`fmea.csv` | `adafusa fmea --output` | Design FMEA |
| `safety-case.json`/`safety-case.md`/`safety-case.mermaid` | `adafusa safety-case --output` | GSN safety case |
| `sas.json`/`sas.md` | `adafusa sas` | Software Accomplishment Summary |

## Docker

```bash
docker build -t adafusa .
docker run --rm -v $(pwd):/project adafusa check
```

The image is built natively on Alpine (musl) using `gcc-gnat` + `libgnat-static`, producing a
fully static binary — this satisfies FuSaOps's "alpine/musl-compatible (or static)" bundling
requirement for images composed into the multi-language FuSaOps container.

## Known limitations (v0.1.0)

This release lands the §9.1 MUST command set end-to-end, not full rule-pack or platform parity
with the other six x-FuSa tools:

- **SPARK proof-coverage** (`adafusa coverage --proof ...`, per
  [FuSaOps#78](https://github.com/SoundMatt/FuSaOps/issues/78) §B) is not implemented yet — it's
  meant to land once the proof-coverage schema has shipped and proven itself against `gnatprove`'s
  sibling `cbmc`-based tools first.
- **MC/DC coverage** (`adafusa coverage --mcdc ...`, the direct sibling of proof-coverage above,
  sourced from `gnatcov`'s output rather than `gnatprove`'s) is not implemented yet
  ([#32](https://github.com/SoundMatt/ada-FuSa/issues/32) tracks it as a follow-up to `comp`, which
  *is* implemented).
- Only 16 starter rules ship, versus 40+ in the more mature sibling tools ([#25](https://github.com/SoundMatt/ada-FuSa/issues/25) tracks further expansion — Ada-specific static-analysis/concurrency rules remain unimplemented).
- **`vuln` has no vulnerability database integrated** — it always reports a clean scan (an
  informational finding when `alire.toml` is present, noting the limitation; nothing otherwise). It
  does not parse `alire.toml`/`alire.lock` to enumerate actual dependencies or check them against a
  real CVE feed yet ([#28](https://github.com/SoundMatt/ada-FuSa/issues/28) tracks this as a
  follow-up). `hara`/`tara` are input-file validators, not automated analyses — hazard/threat
  identification requires human domain judgement a tool cannot generate; they scaffold a template
  and validate/re-emit whatever a human fills in.
- `init`'s interactive TTY prompting only asks for name/standard; ASIL/SIL/DAL must be passed as
  flags even when run interactively.
- CI runs a Linux + macOS matrix (macOS bootstraps GNAT via [Alire](https://alire.ada.dev), since
  GNAT is not distributed via Homebrew). **Windows** GNAT/Alire toolchain viability in GitHub
  Actions' `windows-latest` runner is still unverified and tracked as an open gap
  ([#33](https://github.com/SoundMatt/ada-FuSa/issues/33)).
- JSON string handling assumes ASCII or already-UTF-8-encoded byte content; Unicode NFC
  normalisation ahead of fingerprint computation (spec §4.2, only relevant to non-ASCII messages)
  is not implemented.

## Contributing

Feature branch → PR → CI green → merge → tag → release. Every commit carries a
`Signed-off-by` trailer (enforced by CI's DCO check).

## License

Mozilla Public License 2.0 — see [LICENSE](LICENSE).

## Related Projects

- [go-FuSa](https://github.com/SoundMatt/go-FuSa) — Go implementation (spec reference)
- [java-FuSa](https://github.com/SoundMatt/java-FuSa) — Java implementation
- [FuSaOps](https://github.com/SoundMatt/FuSaOps) — Orchestrator + specification
