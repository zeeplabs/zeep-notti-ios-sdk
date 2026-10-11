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

### L-006 - Guard a manifest with an allowlist of permitted keys/shapes, not a denylist of known-bad fields; platform-scoped attributes and nested specs bypass field-by-field checks.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `architecture` · harmful: 0
- features: package-foundation
- evidence: scripts/check-package-graph.sh:55-95 (PKG-06) (architecture)
- last seen: 2026-10-10T13:57:47Z

### L-007 - Every declared manifest value an AC names (platform, tools version) needs its own assertion; builds passing does not prove a minimum-version constraint.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `ci` · harmful: 0
- features: package-foundation
- evidence: Package.swift:6 (PKG-01) (ci)
- last seen: 2026-10-10T19:14:45Z

### L-008 - Persistence identifiers used only by production wiring (e.g. the UserDefaults suite name of a shared singleton) need their own golden assertion; per-test isolated stores never exercise them.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `storage` · harmful: 0
- features: core-port
- evidence: Sources/NottiSDK/Runtime/NottiRuntime.swift:21 (CORE-09, mutant R1) (storage)
- last seen: 2026-10-10T21:36:49Z

### L-009 - A no-PII-in-logs sentinel test must drive every log site that has a PII value in scope, including failure paths (e.g. registration failure), not one representative flow.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `logging` · harmful: 0
- features: core-port
- evidence: Sources/NottiSDK/Core/NottiCore.swift:725 (CORE-12, mutant L4) (logging)
- last seen: 2026-10-10T21:36:49Z

### L-010 - Assert a global's effective initial value (read without setting it), not only the default constant that tests copy into it before asserting.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `logging` · harmful: 0
- features: core-port
- evidence: Sources/NottiShared/NottiLogger.swift:41 (CORE-13, mutant G2) (logging)
- last seen: 2026-10-10T21:36:49Z

### L-011 - Give every conjunct of a multi-condition guard (e.g. both ids non-empty) its own negative test; one 'empty id' case covers only one of them.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `events` · harmful: 0
- features: core-port
- evidence: Sources/NottiSDK/Events/NottiNotificationHandler.swift:92 (SDKCTR-04, mutant H8) (events)
- last seen: 2026-10-10T22:15:59Z

### L-012 - A pre-initialize test must make each method the FIRST call on a fresh runtime, because an earlier call creates the core and hides a dropped ensureCore().
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `facade` · harmful: 0
- features: public-api
- evidence: NottiFacade.swift:132-140 (API-07, mutants U15-U17) (facade)
- last seen: 2026-10-11T14:43:17Z

### L-013 - A shell-level 'reaches the facade' test must emit one event type at a time with a distinct payload per event, never every event with one payload.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `events` · harmful: 0
- features: public-api
- evidence: Notti.swift:154 (API-10, mutant S06) (events)
- last seen: 2026-10-11T14:43:17Z

### L-014 - An attribute the spec requires on a public symbol needs a guard that reads the attribute itself, not only the declaration line.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `scripts` · harmful: 0
- features: public-api
- evidence: Notti.swift:16 (API-15 AC2, mutant E1) (scripts)
- last seen: 2026-10-11T14:43:17Z

### L-015 - Forwarding tests must assert the delivery count, not just the first value, or a listener that fires twice survives.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `tests` · harmful: 0
- features: public-api
- evidence: B33 NottiObjCBridgeTests.swift:157 (tests)
- last seen: 2026-10-11T15:10:58Z

### L-016 - A bare 'core exists' assertion is a weak oracle; assert the effect (sent, persisted or dropped) of the call.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `tests` · harmful: 0
- features: public-api
- evidence: N15 pre-initialize test (tests)
- last seen: 2026-10-11T15:10:58Z

### L-017 - Mutate a textual guard with Swift grammar variants (indirect, lone public, trailing comment, non-type declarations), not only with the obvious omission.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `scripts` · harmful: 0
- features: public-api
- evidence: check-public-surface.sh r2 N9-N13 (scripts)
- last seen: 2026-10-11T15:10:58Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
