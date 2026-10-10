# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Specify/Design)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - Prove a CI log-grep against a real log from the current toolchain (e.g. Xcode 26+ logs retries as 'started (Iteration 2 of 2)'), never against strings copied from an older pipeline.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `ci` · harmful: 0
- features: package-foundation
- evidence: .github/workflows/ci.yml:82 (PKG-09) (ci)
- last seen: 2026-10-10T01:59:45Z

### L-002 - Guard scripts must fail on missing inputs and distinguish grep exit 1 (no match) from exit 2 (error), and be tested on the CI's own OS (GNU vs BSD).
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `scripts` · harmful: 0
- features: package-foundation
- evidence: scripts/check-extension-safety.sh:15 (PKG-03) (scripts)
- last seen: 2026-10-10T01:59:45Z

### L-003 - When a spec says 'warnings as errors in CI', name the job that enforces it and pass the treat-warnings-as-errors flags there explicitly.
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `ci` · harmful: 0
- features: package-foundation
- evidence: spec.md PKG-04 (ci)
- last seen: 2026-10-10T01:59:45Z

### L-004 - An architectural invariant (e.g. 'extension never depends on app code') needs a CI check that fails on the forbidden edge; build success and inspection do not detect it.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `architecture` · harmful: 0
- features: package-foundation
- evidence: Package.swift:24 / NottiSDK.podspec:40 (PKG-02, PKG-06) (architecture)
- last seen: 2026-10-10T02:12:50Z

### L-005 - When guarding a packaging invariant, also assert file globs/patterns (source_files, resources), not only dependency edges.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `architecture` · harmful: 0
- features: package-foundation
- evidence: scripts/check-package-graph.sh:53-62 (PKG-06, PKG-07) (architecture)
- last seen: 2026-10-10T02:24:29Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
