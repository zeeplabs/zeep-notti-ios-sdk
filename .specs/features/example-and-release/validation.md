# Validation: example-and-release - FAIL ❌ (round 3 conditional; fixes applied, round 4 pending)

**Status**: the feature is not marked done. Three independent Verifier rounds ran on 2026-10-21; round 3 was a conditional FAIL and its findings are fixed in the commit that adds this file, but no round 4 ran. CI has never run for any of this work (GitHub Actions billing), and the device checklist has not been run, so no EXR is proven beyond "Local" (see `traceability.md`).

Method: each round ran in an isolated worktree, did not trust the author's notes, re-derived claims from `Sources/`, `Example/` and the scripts, and mutation-tested the guards.

## Round 1 (FAIL)

- **B1 Blocker.** Scheme `NottiExample-NoAdaptor` still compiled `USE_ADAPTOR` (target `$(inherited)` pulled it from base settings). Fixed in `56257df`: the flag is per configuration; CI asserts it.
- **M1** checklist steps unreachable (example never initializes at launch). **M2** D07 proves the 20 s deadline, not the OS expiry. **M3** EXR-18 overclaim. **M4** coverage guard blind spots. **M5** README and CHANGELOG network contract and retry rule. Fixed in `56257df` and `c50986b`.
- Minors: manifest purposes, secret-scan reach, `--built` path check, tag `v` prefix, CI timeout and bookkeeping fixed; the secret-scan reach, the date range check (`2026-13-45`), the XcodeGen brew pin and the `iPhone 17` grep stay open as minors.

## Round 2 (FAIL)

- **N1** D09 and D11 misdescribed the SwiftUI-without-adaptor path (the SDK returns early for SwiftUI's internal delegate). **N2** README and CHANGELOG lacked that limitation, which `delegate-integration/spec.md` requires. N3 to N5 minors. Fixed in `4a7146e`.

## Round 3 (conditional FAIL)

- N2, N3, N4 closed; N5 mostly closed; N1 partial.
- **M1** D09's pass criterion (the console warning) is unreachable: the warning is `.warn`, emitted once at launch, and the log level defaults to `error` and is only settable after launch. Fixed: the warning is no longer a criterion; a STATE todo records the missing launch-time log level.
- **M2** D11 exercised the early install path, not the late one in the STATE todo. Fixed: D11 is reworded, says a Pass does not tick that todo, and needs another host app.
- m1 (D11 prerequisite: neither fetch method), m2 (D12 and D13 no longer repeat D11), m3 (README and CHANGELOG say the warning is invisible at the default level; D01 names its scheme), m4 (release text: run `39647738829` only documents the billing block; D11 "Not run" is carried into the changelog step). Fixed.

## Confirmed by the Verifiers (own runs)

- All `scripts/check-*.sh` pass locally and under ubuntu:24.04 with mawk for the text guards.
- Hosted tests: 34 per leg on SPM, pods static, libs and dynamic; the NoAdaptor scheme passes; strict device builds pass.
- Guard mutations are killed (snippets, version, config, coverage).
- README fields, endpoints, retry rule, manifest declarations and the 31 `notti_*` keys match the code.
- No PII, real ids or keys, and no AI co-author lines; every commit is authored by Julio Sousa.

## Not proven

- Everything in CI (the `example` job, the new guards, the NoAdaptor step): billing blocks Actions.
- Every `DEVICE_CHECKLIST.md` item, and the Objective-C README block.
- To finish: fix billing and read a green CI run, run the checklist, run a round 4 Verifier on the final state, then mark the feature DONE.
