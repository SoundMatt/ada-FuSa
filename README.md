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

- **8 commands**: `version`, `capabilities`, `init`, `check`, `trace`, `qualify`, `release`,
  `audit-pack`, `report` — the full §9.1 MUST command set of the x-FuSa spec.
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
| `adafusa hara [--dir]` | Load/validate `.fusa-hara.json` hazard analysis (ISO 26262-3); scaffolds a template if absent | text, json |
| `adafusa tara [--dir]` | Load/validate `.fusa-tara.json` threat analysis (ISO 21434 ch.9); scaffolds a template if absent | text, json |
| `adafusa vuln [--dir]` | Dependency vulnerability scan (no CVE database integrated yet — see limitations) | text, json |

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
- Managing this file via a `disposition` CLI verb (`list`/`add`) is not yet implemented — edit it
  directly for now (tracked in #29).

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

## Evidence Artifacts

| File | Generated by | Description |
|------|---------------|--------------|
| `qualify-report.json` | `adafusa qualify` | Tool qualification report |
| `sbom.json` | `adafusa release` | x-FuSa SBOM v1 (zero runtime deps ⇒ empty `components`) |
| `provenance.json`, `artifact-manifest.json` | `adafusa release --full` | Minimal provenance/manifest documents |
| `<name>-<version>.spdx.json` | `adafusa release --spdx-version` | SPDX 2.2/2.3 software bill of materials (opt-in) |
| `audit-pack.zip` | `adafusa audit-pack` | All existing evidence artifacts, bundled |
| `comp-report.json` | `adafusa comp --format json` | Per-function cyclomatic complexity (consumed by FuSaOps v1.70.0+) |
| `vuln.json` | `adafusa vuln --format json` / `release --full` | Dependency vulnerability finding-list (always clean — see limitations) |

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
