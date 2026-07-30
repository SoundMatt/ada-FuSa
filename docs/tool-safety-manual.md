# ada-FuSa Tool Safety Manual

**Version:** 0.1.7
**x-FuSa spec version:** 1.15.2
**Repository:** `github.com/SoundMatt/ada-FuSa`
**License:** Mozilla Public License 2.0
**Standards addressed:** ISO 26262, IEC 61508, ISO 21434, DO-178C

---

## 1. Purpose

This document is the Tool Safety Manual for ada-FuSa. It is intended for:

- Engineering teams qualifying ada-FuSa for use in safety-critical Ada/SPARK projects
- Auditors assessing compliance with ISO 26262-8 (software tools), IEC 61508-3, or an
  equivalent tool-confidence framework
- CI architects integrating ada-FuSa into a regulated software development lifecycle

ada-FuSa is one of seven independent, per-language implementations of the
[x-FuSa specification](https://github.com/SoundMatt/FuSaOps/blob/main/docs/x-fusa-spec.md)
(go-FuSa, c-FuSa, cpp-FuSa, rust-FuSa, py-FuSa, java-FuSa, ada-FuSa). Ada/SPARK is the
reference language for DO-178C Level A avionics software and for formal verification, which
is why ada-FuSa's flagship command is SPARK proof-coverage (`coverage --proof`, sourced from
`gnatprove` output) — a capability none of the sibling tools natively provide.
[FuSaOps](https://github.com/SoundMatt/FuSaOps) discovers and orchestrates all seven tools'
machine-readable output without any tool-specific code, so this manual documents ada-FuSa
standalone as well as in that orchestrated context.

## 2. Tool Overview

ada-FuSa is a **software development support tool**. It analyzes Ada/SPARK source and project
metadata and produces machine-readable evidence; it never modifies, compiles, or links the
target project's own source.

| Capability | Rules | Command |
|---|---|---|
| Project structure checks | FUSA001–004 | `adafusa check` |
| Ada Quality & Style Guide checks | ADA001–008 | `adafusa check` |
| CWE-mapped security checks | SEC001–004 | `adafusa check` / `adafusa cyber` |
| Ravenscar/tasking hazard check | CONC001 | `adafusa check` |
| Hygiene/formatting checks | LINT001–003 | `adafusa lint` |
| Deeper static analysis (unused with-clauses, long parameter lists) | — | `adafusa analyze` |
| Requirement traceability and coverage | — | `adafusa trace` |
| Cyclomatic complexity (DO-178C §6.3.4) | — | `adafusa comp` |
| SPARK proof-coverage (via `gnatprove`) | — | `adafusa coverage --proof` |
| Test evidence collection | — | `adafusa verify` |
| Tool qualification suite (known-answer tests) | — | `adafusa qualify` |
| Release artifacts (SBOM SPDX 2.2/2.3, provenance, signing) | — | `adafusa release` |
| Evidence bundle for auditors | — | `adafusa audit-pack` |
| Hazard Analysis and Risk Assessment (ISO 26262-3) | HARA002–004 | `adafusa hara` |
| Threat Analysis and Risk Assessment (ISO 21434) | — | `adafusa tara` |
| Design FMEA (IEC 60812 / AIAG-VDA) | — | `adafusa fmea` |
| Safety case assembly (GSN) | — | `adafusa safety-case` |
| Dependency vulnerability scan | — | `adafusa vuln` |
| Standards gap reports (ISO 26262 / IEC 61508 / ISO 21434 / IEC 62443 / UN R.155 / SLSA / DO-178C) | — | `adafusa iso26262` / `iec61508` / `iso21434` / `iec62443` / `unece` / `slsa` / `do178` |
| Software Accomplishment Summary (DO-178C §11.20) | — | `adafusa sas` |
| Software Configuration Index (DO-178C §11.16) | — | `adafusa sci` |
| Problem report log (DO-178C §11.17) | — | `adafusa pr` |
| Finding disposition log (accept/defer/waive) | DISP001 | `adafusa disposition` |
| Package/unit dependency graph | — | `adafusa boundary` |
| Change impact analysis | — | `adafusa impact` |
| Structural coupling metric | — | `adafusa coupling` |
| Safety metrics history | — | `adafusa metrics` |
| Whitespace/formatting auto-fix | — | `adafusa fix` |
| Diff against a prior `check` baseline | — | `adafusa diff` |
| Status badge (SVG) | — | `adafusa badge` |

The full 42-command surface (§9.1 MUST set plus §9.2 SHOULD / §9.3 MAY evidence,
risk-analysis, and hygiene commands) is enumerated in the [README Commands
table](../README.md#commands), which this manual does not duplicate verbatim.

## 3. Tool Classification

### ISO 26262-8 / IEC 61508-3 Assessment

| Criterion | Assessment |
|---|---|
| Tool output directly incorporated into the safety-critical binary? | No |
| Tool failure could cause an undetected error in the target software? | Possible (false negative) |
| Recommended TCL (ISO 26262-8 Table 4) | **TCL2** |

ada-FuSa's own Table 4 classification logic (`src/fusa-config.adb`, the ASIL→TCL/ASIL-decomposition
mapping used when *analyzing a target project's* declared ASIL) has been independently verified
against all 36 (S × E × C) combination cells and found correct; see `tests/test_engine.adb`.

### TCL Guidance

| TCL | When applicable | Required evidence |
|---|---|---|
| TCL1 | Informational use only; every finding reviewed by a qualified engineer | Usage record |
| TCL2 | Recommended for most regulated projects | This manual + `qualify-report.json` |
| TCL3 | Mandated only if the project safety plan requires it | Full validation package (§12) |

## 4. Installation

### Prerequisites

- GNAT 12+ and `gprbuild` (Debian/Ubuntu: `apt install gnat gprbuild`; macOS/Windows: the
  [Alire](https://alire.ada.dev) package manager, `alr toolchain --select gnat_native gprbuild`,
  since GNAT is not distributed via Homebrew)
- No external runtime dependencies — the built binary links only against the Ada runtime

### Build from source

```
gprbuild -p -P adafusa.gpr
```

### Verify

```
bin/adafusa version
```

### Docker (zero-install)

ada-FuSa's own multi-stage `Dockerfile` builds the binary on Alpine (musl) via
`gprbuild -P adafusa.gpr` (the same project file CI validates), producing a fully static
binary suitable for [FuSaOps](https://github.com/SoundMatt/FuSaOps)'s all-in-one image.

```
docker run --rm -v "$(pwd)":/project ghcr.io/soundmatt/ada-fusa:latest check
```

The published image's `SPEC_VERSION` label always tracks `Fusa.Spec_Version`
(`src/fusa.ads`) — verify with `docker inspect --format '{{json .Config.Labels}}'`.

## 5. Configuration Reference

ada-FuSa is configured by a `.fusa.json` file in the project root, created by `adafusa init`.

| Field | Type | Default | Description |
|---|---|---|---|
| `configVersion` | string | `"1.0"` | Schema version |
| `project.name` | string | — (required) | Project display name |
| `project.version` | string | `"0.1.0"` | Project version string |
| `standard` | string | `"iso26262"` | Safety standard id — one of spec §2.4.1's closed enum: `iso26262`, `iec61508`, `do178c`, `iso21434`, `iec62443-4-1`, `iec62443-4-2`, `misra-c`, `misra-cpp`, `autosar-cpp14`, `cert-c`, `cert-cpp`, `unece-r155`, `unece-r156`, `slsa` |
| `asil` / `sil` / `dal` | string | `""` | At most one of ASIL (`ASIL-A`..`ASIL-D`), SIL (`SIL-1`..`SIL-4`), or DAL (`DAL-A`..`DAL-E`) |
| `sourceDirs` | []string | `["src"]` | Directories scanned for Ada source |
| `excludePatterns` | []string | `[]` | Glob patterns excluded from scanning |
| `strict` | bool | `false` | Gate-fail on WARNING-severity findings, not just ERROR |

`adafusa init --standard <id>` (and the interactive prompt it falls back to without one)
validates the given value against the closed enum above and exits 2 (usage error) on an
unrecognised value, rather than silently writing a non-conformant config.

### Example

```json
{
  "configVersion": "1.0",
  "project": { "name": "my-project", "version": "0.1.0" },
  "standard": "iso26262",
  "asil": "ASIL-B",
  "sourceDirs": ["src"],
  "excludePatterns": ["*.gen.adb"]
}
```

## 6. CI Pipeline Integration

Recommended GitHub Actions integration (mirrors this repository's own `.github/workflows/ci.yml`):

```yaml
- run: gprbuild -p -P adafusa.gpr
- run: bin/adafusa check --format json --output fusa-report.json
- run: bin/adafusa trace --req-coverage 100 --func-coverage 100
- run: bin/adafusa qualify
- run: bin/adafusa release --full
```

Recommended pipeline order:

1. `adafusa check` — fail fast on structural, style, and security findings
2. `adafusa trace` — verify requirement and function-tag coverage
3. `adafusa qualify` — run the built-in known-answer suite
4. `adafusa release --full` — generate SBOM, provenance, and the full evidence bundle
5. `adafusa audit-pack` — archive everything for an auditor

ada-FuSa's own CI currently runs a Linux + macOS matrix (macOS bootstraps GNAT via Alire,
since GNAT is not distributed via Homebrew). A Windows leg is tracked separately
([#33](https://github.com/SoundMatt/ada-FuSa/issues/33)) — see §10.

## 7. Rule Exclusions and Dispositions

Individual findings (identified by their §4.2 fingerprint, or by rule id) are suppressed via
`.fusa-dispositions.json`, managed with `adafusa disposition list|add`:

```
bin/adafusa disposition add ADA005 accepted "long lines pre-date the style guide; tracked in #40"
```

**Safety plan obligation:** every accepted/deferred disposition must be justified in the
project safety plan before the release is accepted. `DISP001` (WARNING) fires on any
disposition entry that no longer matches a current finding, so stale waivers are always
visible rather than silently accumulating.

## 8. Known Limitations

1. Only 16 starter rules ship (`ADA001`–`008`, `SEC001`–`004`, `FUSA001`–`004`, `CONC001`,
   `LINT001`–`003`, `HARA002`–`004`, `DISP001`), versus 40+ in the more mature sibling tools
   ([#25](https://github.com/SoundMatt/ada-FuSa/issues/25) tracks further expansion).
2. `adafusa coverage --mcdc` (the `gnatcov`-sourced sibling of `--proof`) is not implemented
   yet ([#32](https://github.com/SoundMatt/ada-FuSa/issues/32)); only `--proof` is currently
   accepted.
3. `vuln` has no CVE database integrated — it always reports a clean scan
   ([#28](https://github.com/SoundMatt/ada-FuSa/issues/28) tracks this).
4. `hara`/`tara`/`fmea`/`safety-case` derive real, source-traced content when their input
   file's array is empty, but this is a heuristic fallback — it does not replace human hazard
   or threat identification, which requires domain judgement a tool cannot generate.
5. CI runs a Linux + macOS matrix only; Windows GNAT/Alire toolchain viability in GitHub
   Actions has not yet been validated end-to-end (tracked as
   [#33](https://github.com/SoundMatt/ada-FuSa/issues/33)).
6. Evidence files carry SHA-256 integrity hashes but are not cryptographically signed by
   default — use `adafusa sign` (HMAC-SHA256) or an external signer such as `cosign` for a
   tamper-evident chain of custody in regulated environments.
7. ada-FuSa performs static and structural analysis, plus `gnatprove`-sourced proof-coverage.
   It does not replace dynamic testing, a full formal-verification campaign, or manual code
   review by a qualified safety engineer.

## 9. Assumptions of Use

| # | Assumption |
|---|---|
| AoU-1 | The tool is applied to the **complete** Ada/SPARK source tree named by `sourceDirs`. Selective analysis of a subset may produce incomplete findings. |
| AoU-2 | Findings are reviewed by a **qualified safety engineer** before use in a safety case; ada-FuSa automates detection, it does not replace engineering judgement. |
| AoU-3 | The tool is built from a verified source (a pinned commit/tag) or a pinned, digest-referenced container image, and its version is recorded in the project safety plan. |
| AoU-4 | `qualify-report.json` is **regenerated** whenever the tool version changes; a report generated by a prior version is not evidence for the current version. |
| AoU-5 | Entries in `.fusa-dispositions.json` are reviewed and justified in the safety plan **before each release**. |
| AoU-6 | `adafusa verify` is run against the same test suite exercised during integration testing, not a subset. |

## 10. Tool Qualification Evidence Summary

| Evidence Item | Location | Generated By |
|---|---|---|
| Rule specification | `src/fusa-rules_*.adb`, rule registry | Source code |
| Test specification | `tests/test_*.adb` (891+ checks) | Source code |
| Qualification report | `qualify-report.json` | `adafusa qualify` |
| Test results | `.fusa-verify.json` | `adafusa verify` |
| SBOM (SPDX 2.3 / native) | `sbom.json` | `adafusa release` |
| Build provenance | `provenance.json` | `adafusa release --full` |
| Traceability matrix | stdout / `--format json` of `adafusa trace` | `adafusa trace` |
| Full evidence bundle | `audit-pack.zip` | `adafusa audit-pack` |
| This document | `docs/tool-safety-manual.md` | Manual |

### Assembling a qualification package

1. Run `adafusa qualify` — verify all known-answer cases pass
2. Run `bin/run_tests` (or `gprbuild -P tests/tests.gpr && bin/run_tests`) — verify the full
   regression suite passes
3. Run `adafusa release --full` — generate SBOM, provenance, artifact manifest, and derived
   fmea/tara/safety-case evidence
4. Run `adafusa audit-pack` — bundle everything into one hashed-manifest ZIP
5. Archive: this document, `qualify-report.json`, `sbom.json`, `provenance.json`,
   `audit-pack.zip`
6. Record the tool version (`adafusa version`) and the SHA-256 hash of the `adafusa` binary
   in the project safety plan

---

*ada-FuSa is open source under the Mozilla Public License 2.0. The MPL 2.0 permits use in
commercial and regulated products. See `LICENSE` for terms.*
