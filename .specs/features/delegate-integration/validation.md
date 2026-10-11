# Validation: delegate-integration - PASS ✅ (round 2)

**Date**: 2026-10-11
**Spec**: `.specs/features/delegate-integration/spec.md` (DEL-01..DEL-18; the only source for blocking)
**Diff range re-verified**: `e7e3132..de67bf3` (5 commits: `6d1291c`, `1d90267`, `940032d`, `3687f11`, `de67bf3`) plus the untracked edits to `spec.md` and `traceability.md`. `git diff --stat e7e3132..HEAD` touches **no file under `Sources/`**: only `Tests/`, `scripts/check-launch-hook-purity.sh`, `.github/workflows/ci.yml`, `AGENTS.md`, `.specs/`. No production regression is possible from the fix commits; the regression check is the full gate below.
**Verifier**: the independent Verifier of round 1 (author of none of the code, tests or docs). Every mutant was applied, run and reverted with `git checkout -- <file>`; `dirty=0` after each one. `git status --short` at the end of the report: only `?? .specs/features/delegate-integration/`.
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, SwiftLint 0.65.1 (Docker), CocoaPods local. Tests through the watchdog `run.sh`, one `xcodebuild` at a time.

**Verdict (round 2)**: PASS. G1, G2 and G3 are closed: every mutant that survived round 1 and was meant to be fixed is now killed by a test or by the new script (table below), and the three the fix deliberately left alone (F1, J5, D2) still survive as classified in round 1 (non-blocking). The gate is green (474 tests). No new blocker was found. New Minor items are listed (M6-M8); none is an AC, a gate or an AGENTS.md rule.

Blocking criteria as in round 1: only DEL-01..18, gates and repo rules (AGENTS.md). M2, M5 and the N-notes do not block.

---

## Gates (HEAD `de67bf3`, my own runs)

| Gate | Result |
| --- | --- |
| Full suite (`xcodebuild test -scheme NottiSDK-Package`, iPhone 17 Pro), run 3 times | `** TEST SUCCEEDED **` each time: **474 tests, 0 failures** (Shared 14, SDK 453, ObjC 6, Extension 1; 474 `Test Case ... passed` lines, 0 failed). Round 1 was 465: +9 new tests (SDK 444 to 453), as expected. Runs: with a stale `notti_prefs` store, and twice with it cleaned (see Test audit) |
| SwiftLint 0.65.1 `--strict` (Docker) | 0 violations, 0 serious, 74 files |
| `check-version.sh` | `version ok: 0.1.0` |
| `check-extension-safety.sh` | `extension safety ok` |
| `check-package-graph.sh` | `package graph ok` |
| `check-public-surface.sh` | `public surface ok (68 declarations)` (unchanged: no `public` symbol added) |
| `check-no-url-open.sh` | `no url open ok` |
| `check-launch-hook-purity.sh` (new) | `launch hook purity ok` |
| `check-hook-linked.sh spm` (`NOTTI_SIM="iPhone 17 Pro"`) | `NOTTI_HOOK loadCount=1 installCount=1`, `hook linked ok (spm)` |
| `check-hook-linked.sh pod` | `hook linked ok (pod)` |
| `pod lib lint NottiSDK.podspec --platforms=ios` | `NottiSDK passed validation.` |
| `pod lib lint ... --subspec=Extension` | `NottiSDK passed validation.` |
| Device build `NottiSDK` (`generic/platform=iOS`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`, CI command) | rc 0 |
| Device build `NottiSDKExtension` (same flags plus `APPLICATION_EXTENSION_API_ONLY=YES`) | rc 0 |
| `validate_spec.py delegate-integration` | 0 errors, 0 warnings |
| `validate_tasks.py tasks.md` | 0 errors, 15 warnings (same as round 1) |
| AI attribution in the 5 new commits | none (checked with the commit subjects and bodies; author Julio Sousa) |

The device builds are incremental over the existing derived data (the test-only commits did not touch `Sources/`); a clean device build was not forced (carried over from round 1, see Not proven).

---

## Mutation re-run (the round 1 survivors, exact ledger descriptions)

Definitions are the ones in the round 1 ledger (same harness). Test mutants ran the 11 delegate classes; script mutants ran `scripts/check-launch-hook-purity.sh` on the mutated tree. For test kills the watchdog stops `xcodebuild` right after the first failure, so the harness prints `UNKNOWN`; the failing `Test Case` lines are the proof of the kill.

| Id | What changed | Round 1 | Round 2 | Killed by |
| --- | --- | --- | --- | --- |
| E1 | `infoPlistKey` renamed `NottiDisableSwizzle` | survived (blocking G1) | ✅ **Killed** | `SC.test_infoPlistKeyIsTheDocumentedLiteral` and `SC.test_literalNottiDisableSwizzlingKeyTurnsSwizzlingOff` |
| F2 | production `isSwizzlingActive: { false }` | survived (blocking G2) | ✅ **Killed** | `API.test_productionFacadeIgnoresEveryManualCallWhileTheSharedSwizzlingStateIsActive` |
| F2b (new, inverse) | production `isSwizzlingActive: { true }` | n/a | ✅ Killed | `API.test_productionFacadeProcessesManualCallsWhileTheSharedSwizzlingStateIsInactive` |
| I12 | `.info` log on every enabled install | survived (blocking G3) | ✅ **Killed** | `IN.test_theEnabledValidLaunchHookPathLogsNothingAboveDebug` |
| I9 | `NottiRuntime.shared` in `install()` | survived (blocking G3) | ✅ **Killed** | script: `103:        _ = NottiRuntime.shared` |
| I11 | `UserDefaults` read in `installFirstTime` | survived (blocking G3) | ✅ **Killed** | script: `141: ... UserDefaults.standard.dictionaryRepresentation()` |
| L1 | `NSLog` in `+load` | survived (blocking G3) | ✅ **Killed** | script |
| L2 | `NSUserDefaults` read in `+load` | survived (blocking G3) | ✅ **Killed** | script |
| L3 | `dataWithContentsOfFile` in `+load` | survived (blocking G3) | ✅ **Killed** | script |
| L4 | `NSClassFromString(@"NottiRuntime")` in `+load` | survived (blocking G3) | ✅ **Killed** | script |
| C5 | token: adapter called after the host original | survived (M1) | ✅ Killed | `AD.test_theAdapterHandlesTheTokenCallbackBeforeTheHostOriginal` |
| D9 | silent only if `content-available` present | survived (M4) | ✅ Killed | `NH.test_aSilentPushWithoutContentAvailableIsReportedOnce` |
| F4 | ObjC `didRegister` calls the non-manual adapter entry | survived (M3) | ✅ Killed | `OB.test_objcManualForwardingIsIgnoredWhileSwizzlingIsActive` (new `.warn` count of 4) |
| F1 | production `installDelegates: { }` | survived (M2) | ❌ Survives | not covered; fix did not target it (not blocking, STATE todo) |
| J5 | request id and action id logged | survived (N3) | ❌ Survives | not in the AC's forbidden list (not blocking) |
| D2 | `aps` not a dictionary: not silent | survived (N4) | ❌ Survives | degenerate payload, outside the ACs (not blocking) |

**Totals this round**: 16 mutants run (the 15 of round 1, plus F2b), 13 killed, 3 survive and all 3 are non-blocking and unchanged. 0 blocking survivors.

### Purity script audit (false negatives and comment stripping)

I ran 31 edits against a scratch copy of the two scanned files (`scripts/check-launch-hook-purity.sh <root>`), all outside the repo tree.

Caught (exit 1): `NSLog`; `os_log` call after `#import <os/log.h>`; `NSUserDefaults` split across two lines; `UserDefaults`, `FileManager`, `URLSession.shared`, `NottiRuntime.shared` in Swift; code after a closed block comment on the same line and after a multi-line block comment (`/* c\n */ _ = UserDefaults...`).
No false positive: banned names only inside `//` or `/* */` comments pass, as designed. Baseline passes. An `NottiLogger.log(.info, ...)` on the enabled path passes the script (by design: the unit test I12 owns it).

Passes the script although it should not (false negatives, all outside the round 1 mutants):

| Edit | Why it passes |
| --- | --- |
| `.m`: `fprintf(stderr, ...)`, `fopen`, `[NSData dataWithContentsOfURL:]`, `[NSString stringWithContentsOfFile:]`, `[NSURLConnection class]` | pattern lists only `dataWithContentsOfFile`, `NSURLSession`, `NSLog`, `os_log`, `NSUserDefaults`, `NSFileManager` |
| `.m`: `#define LOGIT(...) fprintf(...)` | same: the alias hides a non-listed primitive. A macro over a listed name (`#define L NSLog`) is caught on the `#define` line |
| `.m`: `NSClassFromString(@"Notti" @"Runtime")` | literal concatenation |
| `.m`: `#import <os/log.h>` alone | not a violation by itself, passes (correct) |
| `.swift`: `os.Logger(...)`, `print(...)`, `NSLog(...)`, `Data(contentsOf:)` | Swift pattern lists only `UserDefaults`, `FileManager`, `URLSession`, `NottiRuntime` |
| `.swift`: `Notti\u{52}untime` type alias | contrived |
| `.m` or `.swift`: `"http://x"; <banned call>` on the same line, or `"/*"` in a string literal followed by banned code | the stripper treats `//` and `/*` inside a string literal as a comment: the rest of the line (or everything up to a `*/`) is blanked. This is the "hides real code" case you asked about; confirmed with `NSLog`, `UserDefaults` after a string containing `//`, and after a string containing `/*` |
| any banned call in `NottiMethodSwizzler`, `NottiAppDelegateSwizzler`, `NottiNotificationCenterSwizzler`, `NottiFallbackDelegateAssigner`, `NottiPushAdapter`, `NottiSwizzlingConfiguration` | the script scans only `NottiBootstrap.m` and `NottiDelegateInstaller.swift`; the installer builds and runs those at launch |

Classification: **Minor (M6)**. DEL-14's wording is about the hook, and the round 1 mutants (the ones that came from realistic edits) are all killed; the gaps need a deliberate evasion or a different primitive, and the script header says it is textual. Suggested hardening (not required for PASS): add `\bprint\(|NSLog|os\.Logger|\bLogger\(|fprintf|printf\(|fopen|contentsOf|dataWithContentsOf|stringWithContentsOf|NSURLConnection` to the patterns, scan the other launch-path Swift files for `UserDefaults|FileManager|URLSession|NottiRuntime`, and have `strip_comments` skip string literals.

### Test audit (G2, I12, store pollution)

- **G2 exercises production**: both tests call `NottiFacade.setSharedForTesting(nil)` first, so `Notti.Notifications.*` goes through `NottiFacade.shared`, which reads `NottiSwizzlingState.shared`. F2 (`{ false }`) fails the active test; F2b (`{ true }`) fails the inactive test. Both tests save `state.isActive` and restore it in `defer`. That matters: `+load` runs in the xctest process and activates the real state (see `IN.test_theLaunchHookInstalledTheRealSwizzlesInThisProcess`), so the restored value is normally `true`. Covers `didRegister`, `didFail`, `didReceiveRemoteNotification`, `didReceive` (not `willPresent`; the production wiring is a single closure, and `willPresent` is covered through the override facade by B15).
- **I12 test really fails with an `.info`**: killed by the mutant (above). It runs `performInstall(fromLaunchHook: true)` twice with a valid, enabled configuration, asserts the install ran (`state.isActive`) and asserts no log with level `error`, `warn` or `info` (`$0.0 < .debug`, by `NottiLogLevel` raw order). It would also fail on an `.error` or `.warn` on that path.
- **`notti_prefs` pollution**: reproduced the round 1 finding. The F2 and F4 mutants make the production runtime process the calls, and 3 events (`received n-s`, `opened` and `clicked n-g2`) were persisted to the simulator's real `notti_prefs` (key `notti_pending_events`) on each mutant run. The fixed code writes nothing there: after `full4` (fixed code, store emptied before) the key is absent. Why the new tests do not depend on that store: the active test compares `eventStore.all().count` before and after (delta), the inactive test only reads logs, and `onApnsToken` is a no-op while `NottiRuntime.shared.core` is nil. The suite passed with a polluted store (`full2`, `full3`) and with an empty one (`full4`), same 474. I removed the stale key with `simctl spawn ... defaults delete notti_prefs notti_pending_events` (simulator state, not repo).
- **Residual flake risk (Minor, M7)**: `NottiLogger.sink` is process-global and the I12 test reads `logs` without `logLock`; a log line from a background thread of another object during those two calls could fail it. Not observed in 3 full runs. `NottiRuntime.shared` is also touched in the active test (read-only), as the existing F1 test already does.

---

## Spec-anchored acceptance criteria (evidence-or-zero, 1 round on what changed plus regressions)

No `Sources/` change since round 1, so rows without a new proof keep their round 1 evidence (`file:line` and mutant ids in the Round 1 section below). A row is re-opened only if a fix touched it or a mutant for it moved.

| Req | Result | Evidence in round 2 |
| --- | --- | --- |
| DEL-01 | ✅ PASS | `check-hook-linked.sh spm` (`loadCount=1 installCount=1`) and `pod` rerun green; suite green. CI not run (Not proven) |
| DEL-02 | ✅ PASS (was GAP G1) | `SC.test_infoPlistKeyIsTheDocumentedLiteral` asserts `"NottiDisableSwizzling"`; `SC.test_literalNottiDisableSwizzlingKeyTurnsSwizzlingOff` builds the input with a string literal. E1 killed by both |
| DEL-03 | ✅ PASS | order now asserted for token, failure and fetch (`AD.test_theAdapterHandles...BeforeTheHostOriginal`, 3 tests); C5 killed |
| DEL-04 | ✅ PASS | unchanged, round 1 kills hold; suite green |
| DEL-05 | ✅ PASS | unchanged |
| DEL-06 | ✅ PASS | unchanged. AC text now says "at the end of launch (D1)" (spec.md line 100), closes N6 |
| DEL-07 | ✅ PASS | unchanged. F1 (production `ensureInstalled` binding) still unproven: M2, not blocking |
| DEL-08 | ✅ PASS | unchanged |
| DEL-09 | ✅ PASS (was GAP G2) | production facade and `NottiSwizzlingState.shared` tested (active and inactive); F2 and F2b killed; ObjC `didRegister` now covered (F4 killed) |
| DEL-10 | ✅ PASS | unchanged |
| DEL-11 | ✅ PASS | unchanged |
| DEL-12 | ✅ PASS | surface 68, graph, extension safety, both strict device builds, pod lint rerun green; F4 killed |
| DEL-13 | ✅ PASS | unchanged; J5 still outside the AC list (N3) |
| DEL-14 | ✅ PASS (was GAP G3) | `check-launch-hook-purity.sh` kills L1-L4, I9, I11; `IN.test_theEnabledValidLaunchHookPathLogsNothingAboveDebug` kills I12; spec.md line 119 now reads "The enabled, valid path logs nothing above `.debug`; opt-out `.info`, install failure `.error` and non-Boolean `.warn` are the only lines" (closes the N2 tension). Script has the M6 evasions; the AC is "the hook only installs" and the realistic edits are all caught |
| DEL-15 | ✅ PASS | `NH.test_aSilentPushWithoutContentAvailableIsReportedOnce` (`aps: {badge:1}` and `aps: {}`); D9 killed |
| DEL-16 | ✅ PASS | unchanged |
| DEL-17 | ✅ PASS | unchanged |
| DEL-18 | ✅ PASS | unchanged; `check-no-url-open.sh` still has the M5 aliasing gap (grep for `\.open\(|openURL|canOpenURL` over `Sources` empty, rerun) |

**Status**: 18 of 18 ACs PASS; no gap.

---

## Code Quality and repo rules

| Check | Pass? |
| --- | --- |
| No features beyond what was asked in the fix commits | ✅ tests, one script, one CI step, doc edits |
| Test counts did not drop | ✅ 465 to 474 |
| SwiftLint strict 0 | ✅ |
| AGENTS.md: logs through `NottiLogger`, no PII | ✅ unchanged `Sources/`; new tests use synthetic fixtures (`fixture.g2`, `n-g2`, `d-g2`) |
| AGENTS.md: extension safety, public surface, version | ✅ scripts green |
| AGENTS.md: no AI attribution | ✅ |
| AGENTS.md updated with the new script | ✅ (layout, command list and the hook paragraph); `ci.yml` has the `checks` step "Launch hook purity (DEL-14)" |
| `PrivacyInfo.xcprivacy` | ✅ untouched, no new API |

---

## Findings (round 2)

### Blockers

None.

### Minor (new)

| Id | Finding | Fix (optional) |
| --- | --- | --- |
| M6 | Purity script false negatives and comment-stripping quirks (table above) | extend the patterns, scan the other launch-path files, make the stripper string-aware |
| M7 | `test_theEnabledValidLaunchHookPathLogsNothingAboveDebug` reads `logs` without `logLock` and relies on a process-global sink | read through `logLock.withLock` like the other helpers |
| M8 | `traceability.md` still says "Verifier pending", the test count table says 465, and it does not list the 9 new tests (G1, G2, M1, M3, M4 and the I12 test is listed). Docs lag, no AC affected | refresh status, count (474) and rows DEL-02, DEL-03, DEL-09, DEL-12, DEL-15 |

M1, M3 and M4 from round 1 are closed (C5, F4, D9 killed). M2 (F1) and M5 (`check-no-url-open.sh` aliasing) remain open and are tracked in STATE as todos; N1, N3, N4, N5, N7, N8, N9 unchanged. N2 and N6 are closed in `spec.md`.

---

## Not proven (do not read these as PASS)

- **CI**: still not run (branch not on the remote). The new `Launch hook purity` step was run locally only; the macOS CI image (`macos-26`, Xcode 26.6, iPhone 17) differs from this machine. The script uses `perl` and `grep -E`, both on `ubuntu` images, but I did not run it there.
- **Static pods and an app target**, **real device and real callbacks** (APNs, Firebase and OneSignal chains, SwiftUI app, cold start from a real tap), **late install ordering** (N9): unchanged from round 1, not run.
- **Clean device builds**: incremental over existing derived data.
- **F1**: the production `installDelegates` binding to `ensureInstalled`.
- **Launch-path files other than the two scanned ones** are not covered by the purity script; the unit test only proves the runtime is not resolved and the isolated suite stays empty.

---

## Summary

- **Verdict**: PASS (round 2).
- **Gates**: 474 tests green (Shared 14, SDK 453, ObjC 6, Ext 1), SwiftLint 0 / 74 files, 6 guard scripts green (68 surface declarations), `check-hook-linked.sh` spm and pod green, `pod lib lint` (all and Extension) green, strict device builds (SDK and NSE) rc 0, `validate_spec` 0/0, `validate_tasks` 0 errors.
- **Sensor**: 16 mutants, 13 killed (E1, F2, F2b, I12, I9, I11, L1-L4, C5, D9, F4), 3 survive and are non-blocking (F1, J5, D2).
- **Blockers**: none. G1, G2, G3 closed.

---

# Round 1 (histórico)

The report below is the round 1 text, unchanged except for its title. HEAD was `e7e3132`.

## Round 1: FAIL ❌ (histórico, HEAD e7e3132)

**Date**: 2026-10-11
**Spec**: `.specs/features/delegate-integration/spec.md` (DEL-01..DEL-18; the only source for blocking)
**Diff range**: `main` (`8b49425`) `..e7e3132` on `feat/delegate-integration` (16 commits). The branch is not on the remote (`git ls-remote origin` lists only `main`), so CI never ran.
**Verifier**: independent sub-agent (author ≠ verifier). It wrote none of the code, tests, `traceability.md` or `tasks.md`. Read-only over the real tree: every mutant was applied, run and reverted with `git checkout -- <file>`; `dirty=0` after each one (ledger column), and `git status --porcelain` equals the baseline (clean) before this report was written.
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, SwiftLint 0.65.1 (Docker), CocoaPods (local). Tests ran through the watchdog `run.sh`, one `xcodebuild` at a time.

**Verdict (round 1)**: FAIL. The gates are green and the discrimination is strong (79 of 94 valid mutants killed), but **three acceptance criteria have mutants that no test or check kills**:

1. **G1 (DEL-02)**: the `Info.plist` key name is not asserted anywhere. Every test builds its dictionary from the constant `NottiSwizzlingConfiguration.infoPlistKey`, so renaming the string breaks the real opt-out and nothing fails (mutant E1).
2. **G2 (DEL-09, production wiring)**: `Notti.swift` passes `isSwizzlingActive: { NottiSwizzlingState.shared.isActive }` to the production facade. Replacing it with `{ false }` makes every manual call get processed twice in production while swizzling is on, and no test fails (mutant F2). Same hole for `installDelegates` (F1, Minor).
3. **G3 (DEL-14)**: "`+load` only installs" is verified only by review. Seven mutants that add logging, `UserDefaults` or file I/O, a lookup of `NottiRuntime`, or `NottiRuntime.shared` access on the launch path survive (L1-L4 in `NottiBootstrap.m`, I9, I11, I12 in the Swift installer).

All three are small and local (a test or a grep check each). No correctness, LGPD, security, AGENTS.md or gate defect was found. Everything else is a Minor or a Note.

**Blocking criteria applied (as instructed)**: only (a) a DEL-xx AC with no test that fails when the code is wrong (a surviving relevant mutant), (b) an AC violated by the code, (c) a broken gate, (d) an AGENTS.md violation (PII in logs, extension safety, surface, AI attribution). Gaps outside the ACs, style, and findings already known in STATE (override with `super` observed twice, `enqueue` without dedupe of a silent `received`, a push from another SDK without `notification_id` not emitted as `received`, SwiftUI predicate by name, `manualWillPresent` returning D2 options while swizzling is on) are Notes.

---

## Task Completion

| Task | Status | Notes |
| --- | --- | --- |
| T1 `NottiSwizzlingConfiguration` | ✅ Done | `2544afe` |
| T2 `NottiMethodSwizzler` | ✅ Done | `57409e0` |
| T3 `handleSilentPush` | ✅ Done | `ae06260` |
| T4 `NottiPushAdapter` | ✅ Done | `ce8c995` |
| T5 app delegate swizzler | ✅ Done | `e590df7` |
| T6 notification center swizzler | ✅ Done | `15ce385` |
| T7 fallback delegate | ✅ Done | `0f7f9fe` |
| T8 installer and state | ✅ Done | `2bff423` |
| T9 `NottiSDKBootstrap` and packaging | ✅ Done | `6958160` |
| T10 manual API (Swift) | ✅ Done | `6c7d4b8` |
| T11 ObjC mirror | ✅ Done | `4c2e259` |
| T12 CI proof and URL-open ban | ⚠️ Partial | `d6475f2`; the three new CI steps were never run in CI (branch not pushed); proved locally here |
| T13 deep link, cold start, PII proofs | ✅ Done | `1c997f8`, `9835d4b`, `08649ae` |
| T14 traceability and gate | ✅ Done | `e7e3132`; its claims were re-derived below, not trusted |

All 103 test names cited in `traceability.md` exist as `func` in `Tests/` (script check, 0 missing). Existing is not the same as discriminating: the matrix below says which ones kill mutants.

---

## Gates (unmodified tree, HEAD `e7e3132`, my own runs)

| Gate | Result |
| --- | --- |
| Full suite (`xcodebuild test -scheme NottiSDK-Package`, iPhone 17 Pro) | `** TEST SUCCEEDED **`: 465 tests, 0 failures (Shared 14, SDK 444, ObjC 6, Extension 1). Floor in spec is 356; before this feature the count was 356 |
| SwiftLint 0.65.1 `--strict` (Docker) | 0 violations, 0 serious, 74 files |
| `check-version.sh` | `version ok: 0.1.0` |
| `check-extension-safety.sh` | `extension safety ok` |
| `check-package-graph.sh` | `package graph ok` |
| `check-public-surface.sh` | `public surface ok (68 declarations)` |
| `check-no-url-open.sh` | `no url open ok` |
| `pod lib lint NottiSDK.podspec --platforms=ios` | `NottiSDK passed validation.` |
| `pod lib lint ... --subspec=Extension` | `NottiSDK passed validation.` |
| `scripts/check-hook-linked.sh spm` (`NOTTI_SIM="iPhone 17 Pro"`) | `NOTTI_HOOK loadCount=1 installCount=1`, `hook linked ok (spm)` |
| `scripts/check-hook-linked.sh pod` | `hook linked ok (pod)` |
| Device build `NottiSDK`, `generic/platform=iOS`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` (CI command) | exit 0, `** BUILD SUCCEEDED **` (incremental: derived data existed; sources unchanged) |
| Device build `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES` (CI command) | exit 0, `** BUILD SUCCEEDED **` (same note) |
| `validate_spec.py delegate-integration` | 0 errors, 0 warnings |
| `validate_tasks.py tasks.md` | 0 errors, 15 warnings (T14 "Tests: none" and similar; not blocking) |
| AI attribution in the 16 commits | none: grep for `co-authored`, `claude`, `anthropic`, `generated with` over subject and body finds nothing; author is Julio Sousa on all 16 |

Test integrity: count rose from 356 to 465; no deleted tests found in `git diff main --stat -- Tests` (13 files changed, 2727 insertions, 2 deletions).

---

## Spec-anchored acceptance criteria (evidence-or-zero)

Abbreviations as in `traceability.md`. Paths are under `Tests/NottiSDKTests/` unless stated. "Killed by" lists mutant ids from the ledger below.

| Req | Spec-defined outcome | `file:line` + assertion | Mutants | Result |
| --- | --- | --- | --- | --- |
| DEL-01 | `+load` hook runs, not dead-stripped (SPM and pod) | `NottiDelegateInstallerTests.swift:414` hook ran once and found the Swift installer; `:422` real swizzles installed in the process; `scripts/check-hook-linked.sh spm` (`loadCount=1 installCount=1`), `pod` (`nm` for the class) | L6 (install removed) killed by `:422`; L5 (wrong selector) killed; H1 (bootstrap dropped from `NottiSDK` deps) killed by the spm script (`loadCount=-1`); H3 (ObjC sources and header glob dropped from `Core`) killed by the pod script | ✅ PASS locally. CI not run (see Not proven) |
| DEL-02 | `NottiDisableSwizzling = YES` installs nothing, assigns no delegate, one `.info` line; missing or `NO` leaves swizzling on | `NottiSwizzlingConfigurationTests.swift:27` `test_booleanTrueTurnsSwizzlingOff`; `NottiDelegateInstallerTests.swift:200` opt-out changes no selector, assigns no delegate, one `.info` line | E2 (flipped), E3 (CF Boolean check removed), E4 (warning flag), I2 (opt-out ignored), I3 (`.info` to `.debug`), I13 (state set in opt-out) killed. **E1 (key string renamed) survives**: all tests use the `infoPlistKey` constant | ❌ **GAP G1** |
| DEL-03 | token and failure reach the runtime, then the host original with the same arguments; absent methods are added; token before core does not crash | `NottiAppDelegateSwizzlerTests.swift:188` each original once; `:208` same arguments; `:222` absent methods get the SDK implementation | C3 (original not called), C4 (wrong argument), C6 (adapter not called), J1, J3 killed. **C5 (adapter called after the original, order swapped) survives** | ✅ PASS (order is Minor M1). My throwaway test: token and failure with no core, no crash (passed) |
| DEL-04 | `willPresent` reported, host completion wins, SDK completes once with D2 options when the host has no method | `NottiNotificationCenterSwizzlerTests.swift:183` host completion reaches the OS, SDK never calls it; `:194` Notti push completes once with `[.banner,.list,.sound,.badge]`; `:205` other notification completes once with `[]`, not reported | A1 (SDK forces completion), A2 (zero completions), A3 (two completions), A4 (host and SDK both complete), A14 (adapter not called), B1 (D2 options for non-Notti), B2 (empty `notification_id` accepted), B3 (no-`aps` accepted), B4 (wrong options), B5 (no report), G2 killed | ✅ PASS |
| DEL-05 | `didReceive` reported, completion exactly once, empty `delivery_id` queues nothing | `:231` host completes once; `:242` SDK completes once when the host has no method; `NottiPushAdapterTests.swift:199` empty `delivery_id` queues nothing (F7) | A5 (no completion), A6 (double with host), A7 (double without host), A9 (wrong action id), A10 (empty userInfo), B6 (not reported), G1 killed | ✅ PASS |
| DEL-06 | fallback delegate only when the host left it nil at end of launch; later host delegate observed through the setter swizzle | `NottiNotificationCenterSwizzlerTests.swift:395` nil delegate gets the fallback after the launch notification; `:408` a delegate set earlier is left untouched; `NottiDelegateInstallerTests.swift:347` install after launch assigns at once | I6 (assign at install time), I7 (late-install flag), I8 (override a host delegate), A12 (observe after the original setter), A13 (original setter not called), A11 (fallback class swizzled), C12, C14 (same for the app setter) killed | ✅ PASS. The AC text says "at install time"; the code uses end of launch (D1, in AD-010): Note N6 |
| DEL-07 | each method swizzled at most once per class, idempotent, chains with another SDK, no growth on repeated assignment | `NottiMethodSwizzlerTests.swift:127` repeat install is a no-op; `:139` stacked swizzler calls every original once; `NottiNotificationCenterSwizzlerTests.swift:293` stacked on the real swizzler; `:351` repeated delegate swaps do not grow the chain; `NottiDelegateInstallerTests.swift:231` second install changes nothing; `NottiAppDelegateSwizzlerTests.swift:284` subclass observed once | S1 (registry check removed), S2 (key by given class), S3 (wrong implementing class returned), S4 (walk skips own class), S5 (inherited treated as absent: method added on the subclass), S6 (never recorded), I1 (decision guard removed) killed. **F1 (production `installDelegates: {}`) survives** | ✅ PASS for the registry; production binding of `ensureInstalled` unproven: Minor M2 |
| DEL-08 | manual API feeds the same entry points; `willPresent` returns D2 options; works before `initialize` | `NottiPushAdapterTests.swift:253` swizzling off, same calls; `NottiPublicApiTests.swift:367` manual `didReceive` before `initialize` buffered like the swizzled path; `NottiObjCBridgeTests.swift:223` ObjC reaches the adapter | F5, F6 (Swift entry bypasses the manual guard), B9 (guard inverted) killed | ✅ PASS |
| DEL-09 | with swizzling on, the five manual calls are ignored, one `.warn` per call, no values, no double processing | `NottiPushAdapterTests.swift:275` ignored with one warn each; `NottiPublicApiTests.swift:377` through the public API with an injected facade; `NottiObjCBridgeTests.swift:234` ObjC ignored | B9-B15 (guard inverted, removed per method, warn removed) killed. **F2 (production `isSwizzlingActive: { false }`) survives**: the public tests use an override facade, none reads `NottiSwizzlingState.shared` through `NottiFacade.shared` | ❌ **GAP G2** |
| DEL-10 | cold-start click before `initialize` is buffered, returned once then `nil`, reports queued with no core | `NottiPushAdapterTests.swift:220` buffered once, reports queued; `NottiDeepLinkTests.swift:140` returns the link once through `takeInitialClick`; `:154` queued reports stay in the store | B6, A5, D5 killed (reports dropped) | ✅ PASS |
| DEL-11 | local notification or no `aps`: not parsed, not reported, forwarded untouched | `NottiNotificationCenterSwizzlerTests.swift:218` forwarded to the host, not reported; `NottiNotificationHandlerTests.swift` payload without `aps` | B3, D7, D8 killed | ✅ PASS |
| DEL-12 | ObjC mirror with the same semantics; surface file; extension safety; the extension never reaches the hook | `NottiSDKObjCTests/NottiObjCTests.m:114` all five callable, `:133` non-Notti `willPresent` returns none; `NottiObjCBridgeTests.swift:223,234`; `check-public-surface.sh` (68), `check-package-graph.sh`, `check-extension-safety.sh`, strict device builds incl. NSE | P1-P9 (9 edits to `Package.swift` and the podspec) all failed the graph script. **F4 (ObjC `didRegister` bypasses the manual guard) survives**: the ObjC "ignored while active" test does not cover `didRegister` | ✅ PASS with Minor M3 |
| DEL-13 | no token, title, body, `data`, ids or `localizedDescription` in any log line; install failures at `.error` with no values | `NottiLoggingPrivacyTests.swift:428` `test_delegatePathsAtVerboseLogNoSentinelValue`; `NottiMethodSwizzlerTests.swift:183` failure logs one `.error` without values and leaves the class unchanged; `NottiDeepLinkTests.swift:195` link never logged | J1 (token), J2 (`data` map), J3 (`localizedDescription`), J4 (`userInfo` in `willPresent`) killed. J5 (request identifier and action id logged) survives: not in the AC's list (Note N3) | ✅ PASS |
| DEL-14 | the hook only installs: no network, no file or UserDefaults I/O, no logging above `.debug`, no `NottiRuntime` access | `NottiDelegateInstallerTests.swift:382` runtime provider never resolved and the isolated suite stays empty; `:278` the launch path does not look for existing delegates | B16 (adapter resolves the runtime at construction), I10 (UIApplication probed on the launch path) killed. **Survive: L1 `NSLog` in `+load`, L2 `NSUserDefaults` read, L3 file read, L4 `NSClassFromString(@"NottiRuntime")`, I9 `NottiRuntime.shared` in `install()`, I11 `UserDefaults` read in `installFirstTime`, I12 an `.info` log on the enabled path** | ❌ **GAP G3** |
| DEL-15 | silent push (`aps`, no `aps.alert`): `received` emitted and queued, then the host original or `.noData` | `NottiPushAdapterTests.swift:237` reports and returns `.noData`; `NottiNotificationHandlerTests.swift:343` one `received` and one queued report; `:396` same `delivery_id` reaches a listener once; `NottiAppDelegateSwizzlerTests.swift:222` completion once with `.noData` | B7, B8, C7, C8, C9, C10, C11, D1, D3, D4, D5, D6b, D7, D8, D10 killed. **D9 (silent only with `content-available`) survives**: every silent fixture has `content-available` | ✅ PASS for the code; Minor M4 (boundary test). My throwaway test: `aps` with only `badge`, and empty `aps`, are reported as one `received` each (passed) |
| DEL-16 | legacy-only host keeps its method, the fetch variant is not added | `NottiAppDelegateSwizzlerTests.swift:256` legacy-only: no fetch variant, legacy still called | C1 (guard removed), C2 (guard inverted), C13 (SwiftUI skip removed) killed | ✅ PASS |
| DEL-17 | visible push with `content-available`: `received` once, by `willPresent`, never by the silent path | `NottiAppDelegateSwizzlerTests.swift:244` fetch variant on a visible push: `.noData`, nothing reported; `NottiNotificationHandlerTests.swift:362` | D1 (condition flipped), D7 (guard removed) killed; the `aps.alert` condition is covered. My throwaway test: alert as string, as dictionary and as `loc-key`, each with `content-available`, report nothing (passed) | ✅ PASS |
| DEL-18 | the link in `data` arrives byte for byte on warm and cold start, one `opened` and one `clicked`, no URL opened, no link logged, script ban | `NottiDeepLinkTests.swift:101` warm tap exact value; `:116` one `opened`, one `clicked`; `:140` cold start; `:195` link never in a log; `check-no-url-open.sh`; `grep -rnE "\.open\(|openURL|canOpenURL" Sources` finds nothing | A9, A10, B6, J2, J4 killed. Script: catches `UIApplication.shared.open` and any `openURL`, **misses an alias** (`let a = UIApplication.shared; a.open(...)`, `app.open(url, options:...)`, a multi-line call, a string selector): Minor M5 | ✅ PASS for the behavior; AC 3 weaker than its wording (M5) |
| P2-1 (surface, extension safety) | listed public symbols, `@available` app-only, extension never reaches the hook | `check-public-surface.sh` (68), `check-extension-safety.sh`, `check-package-graph.sh`, both strict device builds | P1-P9 killed | ✅ PASS |
| P2-3 (install failure) | `.error` with no values, host unchanged | `NottiMethodSwizzlerTests.swift:183` | I4 (state not set when a hook fails) killed | ✅ PASS |

**Status**: ❌ gaps present (G1 DEL-02, G2 DEL-09, G3 DEL-14). The spec defines precise outcomes for all 18 ACs; DEL-14's "no logging above `.debug`" collides with DEL-02's `.info` line (Note N2), a spec-precision gap.

---

## Discrimination Sensor (mutation testing)

Each mutant was applied to production code, the 11 delegate test classes (153 tests: `NottiMethodSwizzler`, `AppDelegateSwizzler`, `NotificationCenterSwizzler`, `DelegateInstaller`, `PushAdapter`, `NotificationHandler`, `PublicApi`, `ObjCBridge`, `LoggingPrivacy`, `DeepLink`, `SwizzlingConfiguration`) were run, then the file was reverted. Ledger: `scratchpad/ledger.txt`.

**Totals**: 95 runs, 1 build-broken (D6, redone as D6b), 94 valid code mutants: **79 killed, 15 survived**. Plus 18 script cases (see below).

| Id | File | What changed | Result (test that killed it) | Blocking? |
| --- | --- | --- | --- | --- |
| A1 | `NottiNotificationCenterSwizzler.swift` | SDK forces the `willPresent` completion; host gets a dummy | ✅ Killed (CS:183) | - |
| A2 | same | no completion when the host has no `willPresent` | ✅ Killed (CS:194, :205, IN) | - |
| A3 | same | two completions without a host method | ✅ Killed (CS, IN) | - |
| A4 | same | SDK completes after the host original | ✅ Killed (CS) | - |
| A5 | same | `didReceive` without host: no completion | ✅ Killed (CS:242, DL) | - |
| A6 | same | `didReceive` with host: second completion | ✅ Killed (CS:231) | - |
| A7 | same | `didReceive` without host: two completions | ✅ Killed (CS:242, DL) | - |
| A9 | same | `actionIdentifier` empty | ✅ Killed (DL) | - |
| A10 | same | `userInfo` empty on `didReceive` | ✅ Killed (DL) | - |
| A11 | same | fallback class no longer skipped | ✅ Killed (CS:459) | - |
| A12 | same | `setDelegate:` hook observes after the original setter | ✅ Killed (CS) | - |
| A13 | same | `setDelegate:` hook never calls the original | ✅ Killed (CS, IN) | - |
| A14 | same | `willPresent` does not call the adapter | ✅ Killed (CS, IN) | - |
| B1 | `NottiPushAdapter.swift` | D2: non-Notti returns the Notti options | ✅ Killed (CS, API, PA) | - |
| B2 | same | `notification_id` empty accepted | ✅ Killed (PA) | - |
| B3 | same | missing `aps` accepted | ✅ Killed (CS, PA) | - |
| B4 | same | Notti push returns `[]` | ✅ Killed (IN, CS, OB, API, PA) | - |
| B5 | same | `willPresent` not reported | ✅ Killed (IN, CS) | - |
| B6 | same | `didReceive` not reported | ✅ Killed (DL) | - |
| B7 | same | silent path returns `.newData` | ✅ Killed (AD, OB, API, PA) | - |
| B8 | same | silent path does not call the handler | ✅ Killed (AD) | - |
| B9 | same | manual guard inverted | ✅ Killed (PR, OB, API) | - |
| B10 | same | ignored manual call logs nothing | ✅ Killed (PR, API, PA) | - |
| B11 | same | manual `didRegister` ignores the guard | ✅ Killed (PR, API, PA) | - |
| B12 | same | manual `didReceive` ignores the guard | ✅ Killed (PR, OB, API, PA) | - |
| B13 | same | manual `didReceiveRemoteNotification` ignores the guard | ✅ Killed (PR, API, PA) | - |
| B14 | same | manual `didFail` ignores the guard | ✅ Killed (PR, API, PA) | - |
| B15 | same | manual `willPresent` ignores the guard | ✅ Killed (PR, OB, API, PA) | - |
| B16 | same | adapter resolves the runtime at construction | ✅ Killed (IN:382) | - |
| C1 | `NottiAppDelegateSwizzler.swift` | legacy guard removed (fetch variant added over a legacy-only host) | ✅ Killed (AD:256) | - |
| C2 | same | legacy guard inverted | ✅ Killed (AD) | - |
| C3 | same | token: original not called | ✅ Killed (AD:188) | - |
| C4 | same | token: wrong argument to the original | ✅ Killed (AD:208) | - |
| C5 | same | token: adapter called after the original | ❌ **SURVIVED** | No (M1, order only) |
| C6 | same | failure: adapter not called | ✅ Killed (AD, PR) | - |
| C7 | same | fetch: adapter not called | ✅ Killed (AD) | - |
| C8 | same | fetch without host: no completion | ✅ Killed (AD) | - |
| C9 | same | fetch with host: second completion | ✅ Killed (AD) | - |
| C10 | same | fetch without host: two completions | ✅ Killed (AD) | - |
| C11 | same | fetch: adapter gets empty `userInfo` | ✅ Killed (AD) | - |
| C12 | same | app `setDelegate:` hook observes after the original | ✅ Killed (AD:346) | - |
| C13 | same | SwiftUI-internal skip removed | ✅ Killed (AD, PR) | - |
| C14 | same | app `setDelegate:` hook never calls the original | ✅ Killed (AD) | - |
| D1 | `NottiNotificationHandler.swift` | silent condition flipped (`alert != nil`) | ✅ Killed (AD) | - |
| D2 | same | `aps` that is not a dictionary: not silent | ❌ SURVIVED | No (N4, degenerate payload, outside the ACs) |
| D3 | same | `received` identifier = `notification_id` | ✅ Killed (NH) | - |
| D4 | same | `received` identifier always `nil` | ✅ Killed (NH) | - |
| D5 | same | silent push not queued | ✅ Killed (AD) | - |
| D6 / D6b | same | `.opened` (did not compile) / `.clicked` instead of `.received` | D6 build-broken; D6b ✅ Killed (NH, OB) | - |
| D7 | same | silent guard removed (visible and no-`aps` payloads reported) | ✅ Killed (AD, NH, PA) | - |
| D8 | same | missing `aps` counted as silent | ✅ Killed (NH) | - |
| D9 | same | silent only if `content-available` is present | ❌ **SURVIVED** | No (M4) |
| D10 | same | silent report queued as `clicked` | ✅ Killed (AD) | - |
| E1 | `NottiSwizzlingConfiguration.swift` | key `NottiDisableSwizzling` renamed `NottiDisableSwizzle` | ❌ **SURVIVED** (re-run after fixing my classifier: still green, 153 tests) | **Yes (G1, DEL-02)** |
| E2 | same | `isEnabled = number.boolValue` | ✅ Killed (IN, SC) | - |
| E3 | same | CF Boolean check removed | ✅ Killed (SC) | - |
| E4 | same | non-Boolean does not warn | ✅ Killed (IN, PR, SC) | - |
| F1 | `Public/Notti.swift` | production `installDelegates: { }` | ❌ **SURVIVED** | No (M2) |
| F2 | same | production `isSwizzlingActive: { false }` | ❌ **SURVIVED** | **Yes (G2, DEL-09)** |
| F3 | `NottiFacade.swift` | `initialize` does not call `installDelegates()` | ✅ Killed (IN) | - |
| F4 | `Public/ObjC/NottiObjC.swift` | ObjC `didRegister` calls the non-manual adapter entry | ❌ **SURVIVED** | No (M3) |
| F5 | `NottiNotifications+Delegate.swift` | Swift `didFail` bypasses the guard | ✅ Killed (API) | - |
| F6 | same | Swift `didReceiveRemoteNotification` bypasses the guard | ✅ Killed (API) | - |
| G1 | `NottiNotificationCenterDelegate.swift` | fallback `didReceive` never completes | ✅ Killed (CS) | - |
| G2 | same | fallback `willPresent` completes with `[]` | ✅ Killed (CS) | - |
| I1 | `NottiDelegateInstaller.swift` | install decision guard removed (installs on every call) | ✅ Killed (IN) | - |
| I2 | same | opt-out ignored (`guard isEnabled \|\| true`) | ✅ Killed (IN) | - |
| I3 | same | opt-out line at `.debug` instead of `.info` | ✅ Killed (IN) | - |
| I4 | same | state never set active | ✅ Killed (IN) | - |
| I6 | same | fallback assigned at install time | ✅ Killed (IN) | - |
| I7 | same | late-install "launch finished" flag removed | ✅ Killed (IN) | - |
| I8 | `NottiNotificationCenterDelegate.swift` | fallback assigned even when the host has a delegate | ✅ Killed (IN, CS) | - |
| I9 | `NottiDelegateInstaller.swift` | `install()` touches `NottiRuntime.shared` | ❌ **SURVIVED** | **Yes (G3, DEL-14)** |
| I10 | same | launch path probes `UIApplication` | ✅ Killed (IN:278) | - |
| I11 | same | `UserDefaults` read in `installFirstTime` | ❌ **SURVIVED** | **Yes (G3)** |
| I12 | same | `.info` log on every enabled install | ❌ **SURVIVED** | **Yes (G3)** |
| I13 | same | state set active in opt-out | ✅ Killed (IN:200) | - |
| J1 | `NottiPushAdapter.swift` | token hex logged | ✅ Killed (PR:428) | - |
| J2 | `NottiNotificationHandler.swift` | `data` map logged | ✅ Killed (DL, PR) | - |
| J3 | `NottiPushAdapter.swift` | `localizedDescription` logged | ✅ Killed (AD, PR, API, PA) | - |
| J4 | `NottiNotificationCenterSwizzler.swift` | `userInfo` logged in `willPresent` | ✅ Killed (DL, PR) | - |
| J5 | `NottiPushAdapter.swift` | request identifier and action id logged | ❌ SURVIVED | No (N3, not in the AC's list) |
| L1 | `NottiBootstrap.m` | `NSLog` in `+load` | ❌ **SURVIVED** | **Yes (G3)** |
| L2 | same | `NSUserDefaults` read in `+load` | ❌ **SURVIVED** | **Yes (G3)** |
| L3 | same | file read in `+load` | ❌ **SURVIVED** | **Yes (G3)** |
| L4 | same | `NSClassFromString(@"NottiRuntime")` in `+load` | ❌ **SURVIVED** | **Yes (G3)** |
| L5 | same | message send of a non-`@objc` selector | ✅ Killed | - |
| L6 | same | install message send removed (counter still incremented) | ✅ Killed (IN:422) | - |
| S1 | `NottiMethodSwizzler.swift` | registry check removed | ✅ Killed (AD, IN, MS) | - |
| S2 | same | registry key by the given class, not the implementing class | ✅ Killed (AD, MS, CS) | - |
| S3 | same | wrong implementing class returned (the given class) | ✅ Killed (AD, MS, CS) | - |
| S4 | same | walk skips the class's own method | ✅ Killed (AD) | - |
| S5 | same | inherited method treated as absent (method added on the subclass, previous IMP lost) | ✅ Killed (AD, MS, CS) | - |
| S6 | same | install never recorded | ✅ Killed (AD, IN, MS) | - |

**Script cases (not code mutants)**:

| Script | Edit | Result |
| --- | --- | --- |
| `check-package-graph.sh` | P1 `NottiShared` depends on bootstrap; P2 `NottiSDKExtension` depends on it; P6 bootstrap depends on `NottiShared`; P8 bootstrap added to the Extension product; P9 bootstrap exposed as a product; P3 Extension subspec gets the ObjC sources; P4 Shared subspec gets them; P5 `Core` loses `public_header_files`; P7 Extension subspec depends on `NottiSDK/Core` | ✅ 9 of 9 fail the script with a precise message |
| `check-hook-linked.sh spm` | H1 `NottiSDKBootstrap` dropped from `NottiSDK` dependencies | ✅ fails: `loadCount=-1 installCount=-1` |
| `check-hook-linked.sh pod` | H3 ObjC sources and header glob dropped from `Core` | ✅ fails: `_OBJC_CLASS_$_NottiBootstrap` missing |
| `check-no-url-open.sh` | U1 `UIApplication.shared.open(...)` | ✅ fails |
| same | U8 a comment containing `openURL` | fails (conservative false positive, harmless) |
| same | U2 alias `let application = UIApplication.shared; application.open(url, options:..., completionHandler: nil)`; U4 multi-line `UIApplication.shared\n.open(url)`; U5 `app.open(url)` with `app: UIApplication`; U6 `perform(NSSelectorFromString("open:options:completionHandler:"))` | ❌ **pass the script** (M5). The second pattern `\.open\(_:options` is selector-style text and never matches real code |
| same | U7 `NSExtensionContext.open(url)` | passes (not `UIApplication`, listed for completeness) |

**Sensor depth**: P0-style full manual run (more than 5 mutants covering all branches).
**Result**: 79 of 94 killed. Surviving and blocking: E1, F2, I9, I11, I12, L1, L2, L3, L4 (three ACs). Surviving and not blocking: C5, D2, D9, F1, F4, J5.

---

## Code Quality

| Check | Pass? |
| --- | --- |
| No features beyond what was asked | ✅ (D1 and D2 are documented deviations; AD-010) |
| No abstractions for single-use code | ✅ `NottiDelegateInstaller.Environment` exists for injection and is used by tests |
| Only touched files required | ✅ (41 files, all in the feature's surface, tests, scripts, specs, CI) |
| Matches existing patterns/style | ✅ SwiftLint strict 0 |
| Tests map to ACs and are non-shallow (spot check) | ⚠️ one tautological test (N5); three ACs have survivors |
| AGENTS.md: logs only through `NottiLogger`, no PII | ✅ J1-J4 killed; the `.m` logs nothing |
| AGENTS.md: extension safety | ✅ script, graph and NSE strict build |
| AGENTS.md: public surface | ✅ 68 declarations; the pod exposes `NottiBootstrap.h` (N7) |
| AGENTS.md: no AI attribution in commits | ✅ |
| `PrivacyInfo.xcprivacy` | ✅ unchanged; no new required-reason API or collected type (diff shows none) |

---

## Findings

### Blockers

| Id | AC | Evidence | Why it blocks | Fix |
| --- | --- | --- | --- | --- |
| **G1** | DEL-02 | `Sources/NottiSDK/Delegates/NottiSwizzlingConfiguration.swift:12`; mutant E1 survives; `grep -n "NottiDisableSwizzling" Tests -r` finds the name only through `NottiSwizzlingConfiguration.infoPlistKey` (`NottiSwizzlingConfigurationTests.swift:21-54`, `NottiDelegateInstallerTests.swift:201,218`, `NottiLoggingPrivacyTests.swift:370`) | The key is the public Info.plist contract. A typo in the constant silently disables the opt-out for every host, and no test fails | Add a test that asserts the literal `"NottiDisableSwizzling"` and one that builds `NottiSwizzlingConfiguration(infoDictionary: ["NottiDisableSwizzling": true])` with a string literal; re-run E1 and require it killed |
| **G2** | DEL-09 (also DEL-07 for F1) | `Sources/NottiSDK/Public/Notti.swift:170-174`; mutant F2 survives. The public tests inject an override facade (`NottiPublicApiTests.swift:377`); nothing goes through `NottiFacade.shared` with `NottiSwizzlingState.shared` set | In production the manual API would not be ignored while swizzling is on, so `received` and `clicked` are reported twice (the exact failure AD-004 and DEL-09 exist to prevent) | Add a test that sets `NottiSwizzlingState.shared.setActive(true)` (restore in `tearDown`), calls `Notti.Notifications.didRegisterForRemoteNotifications` / `didReceive` through the production facade and asserts one warn and no processing; and the inverse with `false`. Re-run F2 |
| **G3** | DEL-14 | `Sources/NottiSDKBootstrap/NottiBootstrap.m:14-24`, `NottiDelegateInstaller.swift:102-104,139-188`; mutants L1-L4, I9, I11, I12 survive. `traceability.md` DEL-14 row says "review for the `.m` body" | An AC with no test or check that fails when `+load` starts logging, reading `UserDefaults`, doing file I/O or resolving `NottiRuntime`. It runs before `main` in every host app | Add a grep check (new script or a section of `check-no-url-open.sh`, wired into the `checks` CI job) that fails on `NSLog\|os_log\|NSUserDefaults\|NSFileManager\|NSURLSession\|dataWithContentsOfFile\|NottiRuntime` in `Sources/NottiSDKBootstrap/NottiBootstrap.m` and on `UserDefaults\|FileManager\|URLSession\|NottiRuntime` in `NottiDelegateInstaller.swift`; add a test that `performInstall(fromLaunchHook: true)` with a valid enabled configuration logs nothing above `.debug` (kills I12). Re-run L1-L4, I9, I11, I12. Reconcile the spec text (N2) |

### Minor

| Id | Finding | Evidence |
| --- | --- | --- |
| M1 | Order "adapter first, then the host original" is asserted by no test for the token callback (and likely the others): C5 survives. DEL-03 says "SHALL then call the host's original" | `NottiAppDelegateSwizzler.swift:104-107`; ledger C5 |
| M2 | The production binding `installDelegates: { NottiDelegateInstaller.ensureInstalled() }` is untested (F1). It is the safety net if `+load` does not run | `Notti.swift:171` |
| M3 | ObjC `didRegister` is not covered by the "ignored while swizzling is active" test (F4). The other four ObjC entry points are | `NottiObjCBridgeTests.swift:234`; `NottiObjC.swift` `didRegisterForRemoteNotifications` |
| M4 | The silent-push predicate is tested only with `content-available` present (D9). The AC says "`aps` and no `aps.alert`". The code is right: my throwaway test showed `aps: {badge: 1}` and `aps: {}` are each reported once. Add those two fixtures | `NottiNotificationHandler.swift:127-135` |
| M5 | `check-no-url-open.sh` catches `UIApplication.shared.open` and `openURL`, but its second pattern `\.open\(_:options` is selector text that real code never contains: aliases, multi-line calls and `app.open(url, ...)` pass (U2, U4, U5, U6). `grep -rnE "\.open\(\|openURL\|canOpenURL" Sources` is empty today, so DEL-18 AC 2 holds. A plain `\.open\(` ban would close it; check for legitimate uses first | `scripts/check-no-url-open.sh:14` |

### Notes

| Id | Note |
| --- | --- |
| N1 | Known STATE items re-confirmed, not blocking: override with `super` observed twice (my throwaway test counted one listener `received`, because the event buffer de-duplicates by request id; the duplicate report in the store was not measured), `enqueue` without dedupe, a push from another SDK without `notification_id` not emitted as `received`, SwiftUI name predicate, `manualWillPresent` returning D2 options with swizzling on |
| N2 | Spec tension: DEL-14 says "no logging above `.debug`" for the launch hook, while DEL-02 requires an `.info` line on opt-out, DEL-13 an `.error` on install failure and the edge case a `.warn` on a non-Boolean value. All of these run inside `+load` through the installer. The default level is `.error`, so only the failure line is visible by default. Clarify the AC (suggest: the enabled, valid path logs nothing above `.debug`) |
| N3 | J5: the request identifier and the action identifier can be logged without a test noticing. They are not in the AC's forbidden list, and the request identifier is not a payload value |
| N4 | D2: an `aps` that is not a dictionary counts as silent. Degenerate payload, outside the ACs |
| N5 | `NottiDeepLinkTests.swift:180` `test_noCallbackOfEitherSwizzlerOpensAURL` is tautological: the spy is passed as the `application` / `center` argument, so it can only record a call the SDK would make on that argument. It would stay green for `UIApplication.shared.open`. The real guard is the script (M5). `traceability.md` already says this |
| N6 | DEL-06 AC text says "nil at install time"; the code and AD-010 (D1) use "nil at end of launch". `spec.md` has the D2 narrowing but not D1. Update the AC wording |
| N7 | `NottiBootstrap.h` is public in the pod (`public_header_files`), so ObjC consumers of the pod see `NottiBootstrap` and its counters. It is not in `PUBLIC_SURFACE.txt` (the script scans `.swift`). Design says so; confirm it is acceptable |
| N8 | `installCount` increments after the message send without checking that the install ran (L6 passes `check-hook-linked.sh`); the unit test `NottiDelegateInstallerTests.swift:422` is what kills it. The script proves the class is linked and `+load` ran, as it says |
| N9 | Late install path: UIKit may read the app delegate's capabilities when `setDelegate:` runs. If `Notti.initialize` is the first install (hook did not run) and the app delegate lacks a callback, the SDK adds it after UIKit looked. [Incerto], device-only; the main path (`+load` before `setDelegate:`) is not affected |
| N10 | Proposed lessons (not recorded; the brief says not to edit specs or STATE): (1) constants used by tests do not prove the constant's value, assert a public contract string literally; (2) a dependency injected in tests needs one test of the production binding; (3) an AC verified "by review" needs a grep check |

---

## Edge Cases (spec)

| Edge case | Result |
| --- | --- |
| `UIApplication.shared.delegate` nil or SwiftUI internal: no crash, one `.warn` | ✅ `NottiAppDelegateSwizzlerTests` (C13 killed); the name check is [Incerto] on device |
| host swaps `delegate` repeatedly: no growth | ✅ `NottiNotificationCenterSwizzlerTests.swift:351` |
| subclass of a swizzled class observed once | ✅ `NottiAppDelegateSwizzlerTests.swift:284`; throwaway test (subclass swizzled before the superclass, instances of both) observed once each |
| host `didReceive` never calls its completion: SDK does not call it a second time | ✅ A6 killed |
| background thread | ✅ no UIKit in the adapter (reviewed) |
| `initialize` never called: events buffered, nothing sent | ✅ `NottiPushAdapterTests.swift:220` |
| non-Boolean key: treated as on, one `.warn` | ✅ `NottiSwizzlingConfigurationTests.swift:34`, E3 and E4 killed |

---

## Fix Plans (to reach PASS)

1. **G1**: add literal-key tests (two, in `NottiSwizzlingConfigurationTests`). Done when mutant E1 fails a test.
2. **G2**: add the production-facade manual-call test described above. Done when mutant F2 fails a test. Optional for M2: a seam that proves `installDelegates` is `ensureInstalled` (F1).
3. **G3**: add the grep check in CI plus the "no log above `.debug` on the enabled launch path" test. Done when L1-L4, I9, I11 fail the check and I12 fails the test. Update the DEL-14 wording (N2).
4. Re-run the full gate and the 15 surviving mutants; the Minor items (M1-M5) are not required for PASS.

Maximum 3 fix to re-verify iterations apply; this is round 1.

---

## Not proven (do not read these as PASS)

- **CI**: the branch is not pushed. The three new steps (`check-no-url-open.sh` in `checks`, `check-hook-linked.sh spm` in `test`, `check-hook-linked.sh pod` in `pod-lint`) and the extended graph script were run locally only. The macOS CI image (`macos-26`, Xcode 26.6, iPhone 17) differs from this machine (Xcode 27, iPhone 17 Pro).
- **Static pods and an app target**: the pod proof is `nm` on the framework built by `pod lib lint --subspec=Core`. A static-library pod (`--use-libraries`), `use_frameworks! :linkage => :static`, and an Xcode app that links the SPM package are not run. The SPM proof is an executable target, not an app.
- **Real device and real callbacks**: no real push, no real `UIApplication` / `UNUserNotificationCenter` callback, no Firebase or OneSignal chain, no SwiftUI app with or without `@UIApplicationDelegateAdaptor` (the predicate is a class-name check), no cold start from a real notification tap.
- **Late install ordering** (N9) and **UIKit capability caching**: inferred, not run.
- **Strict device builds** ran incrementally on an existing derived-data directory with unchanged sources; a clean build was not forced.
- **Duplicate reports from an override that calls `super`**: only the listener count was measured.

---

## Summary

- **Verdict**: FAIL (round 1).
- **Gates**: 465 tests green (Shared 14, SDK 444, ObjC 6, Ext 1), SwiftLint 0 / 74 files, 5 scripts green (68 surface declarations), `pod lib lint` all and Extension green, `check-hook-linked.sh` spm and pod green, strict device builds (SDK and NSE) green, `validate_spec` 0/0, `validate_tasks` 0 errors.
- **Sensor**: 94 valid code mutants, 79 killed, 15 survived (9 blocking in 3 ACs: E1, F2, I9, I11, I12, L1-L4; 6 not blocking: C5, D2, D9, F1, F4, J5); 18 script cases, all graph and hook mutants caught, the URL-ban script misses aliased calls.
- **Blockers**: G1 (DEL-02 key literal), G2 (DEL-09 production wiring), G3 (DEL-14 launch path unguarded).
- **Report**: `.specs/features/delegate-integration/validation.md`.
