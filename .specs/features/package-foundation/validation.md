# Validation: package-foundation - PASS ✅

**Date**: 2026-10-10
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..88e939e` (code surface: `Package.swift`, `NottiSDK.podspec`, `Sources/`, `Tests/`, `scripts/`, `.github/`, hygiene files; 26 files, +959). Since round 5 (`8e275b8`) the code surface changed only in `88e939e`: `scripts/check-package-graph.sh` +13/-2 (SPM `platforms` and `toolsVersion` assertions; `run()` keeps stderr in a temp file) and `.github/workflows/ci.yml` +2/-2 (`lint` and `checks` jobs pinned to `ubuntu-24.04`). `Sources/`, `Tests/`, `Package.swift`, the podspec and the other two scripts are byte-identical to round 5.
**Verifier**: independent sub-agent (author ≠ verifier), round 6 (owner-authorized extra round)
**Environment**: Xcode 27.0 (27A266a), simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker), GNU grep 3.11 (`ubuntu:24.04`). CI evidence read-only (`gh run view`, `gh api …/check-runs/<id>/annotations`). No pushes, re-runs or edits on GitHub.

---

## Earlier gaps → status (rounds 1-5)

| Round | Gap | Status | Evidence (re-derived this round) |
| --- | --- | --- | --- |
| 1 | Flaky-test warning never fired on Xcode 26+ (PKG-09b) | ✅ Closed | Pattern from `.github/workflows/ci.yml:85`, replayed only on the `Unit tests` step lines: probe run 38015155294 → 1 match (`…FlakyProbeTests test_failsOnceThenPasses]' started (Iteration 2 of 2).`) and the job emitted `##[warning]Tests needed a retry …`; head run 38079032514 → 0 matches (9× `Iteration 1 of 2`). Same counts with GNU grep 3.11. Head annotations: only the macOS capacity notice. |
| 1 | `check-extension-safety.sh` silent pass on GNU grep with a missing dir (PKG-03) | ✅ Closed | `scripts/check-extension-safety.sh:17-22`. `ubuntu:24.04` on a `git archive` copy with `NottiShared` renamed + `UIApplication.shared` planted in `NottiSDKExtension` → `error: expected directory not found: /s/arch/Sources/NottiShared` rc 1. Control: the `247befa` script on the same tree → `grep: … No such file or directory`, `extension safety ok` rc 0. |
| 2 | NSE→app edge not caught: M-D1 (SPM), M-D2 (podspec) | ✅ Closed | M-D1 → `SPM target NottiSDKExtension must depend on ['byName:NottiShared'], got ['byName:NottiSDK', 'byName:NottiShared']` rc 1; `.target(name: "NottiSDK")` variant → `got ['byName:NottiShared', 'target:NottiSDK']` rc 1; M-D2 → `podspec subspec Extension must be exactly …, got {… 'NottiSDK/Core': []…}` rc 1. |
| 3 | Widened podspec globs: M-F1, M-F2, M-F4 | ✅ Closed | `scripts/check-package-graph.sh:92-117`. Each rc 1 with the widened glob in the `got` dict (`['Sources/NottiSDKExtension/**/*.swift', 'Sources/NottiSDK/**/*.swift']`, `Sources/{NottiShared,NottiSDK}/**/*.swift`, `Sources/**/*.swift`). |
| 4 | Platform-scoped attributes / nested subspec: N1, N2, N3, N5, N6; swallowed command errors (N4) | ✅ Closed | Each rc 1 with the offending key shown: N1 `'ios': {'source_files': …}`, N2 `'ios': {'dependencies': {'NottiSDK/Core': []}}`, N3 (Shared) `'ios': {'source_files': …}`, N5 `'ios': {'resource_bundles': {'NottiSDK_Privacy': …}}`, N6 `'subspecs': [{'name': 'Helpers', …}]`. N4 → `error: 'pod ipc spec NottiSDK.podspec' failed:` + `A subspec can't require one of its parents specifications` (stderr still surfaced after the `run()` change). |
| 5 | Gap 1: SPM `platforms` / `swift-tools-version` unchecked (PKG-01, edge case 3) | ✅ Closed | `scripts/check-package-graph.sh:43-46`. F2 `.iOS(.v16)` → `error: SPM platforms must be exactly iOS 15.0, got [{'options': [], 'platformName': 'ios', 'version': '16.0'}]` rc 1. F2b tools `6.0` → `error: SPM swift-tools-version must be 5.9, got {'_version': '6.0.0'}` rc 1, no traceback (SwiftPM still prints its `swiftLanguageVersions` deprecation warning on stderr; it no longer reaches the parser). |
| 5 | Gap 2: `run()` merged stderr into parsed JSON (regression from `fc2da93`) | ✅ Closed | `scripts/check-package-graph.sh:20-31` (`2>"$err_file"`, printed only on failure). PATH shim that prepends `warning: synthetic tool warning` on stderr to both `swift` and `pod`: head script → `package graph ok` rc 0; control `fc2da93` script → `json.decoder.JSONDecodeError: Expecting value: line 1 column 1` rc 1. |
| 5 | Note: Linux jobs on `ubuntu-latest` | ✅ Closed | `ci.yml:25,34` `runs-on: ubuntu-24.04`; run 38079032514 `lint` and `checks` logs show `Image: ubuntu-24.04`; the `ubuntu-latest` migration annotation is gone. |

---

## Task Completion

Checked against artifacts, not the ✅ marks (the "Done when" checkboxes in `tasks.md` are unticked; headings carry ✅ and results).

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | AD-006 in `.specs/project/STATE.md`; `NottiSDK.podspec:22` `-package-name NottiSDK`; both lints pass with `package` access across subspecs. |
| T2 | ✅ Done | `.gitignore:5,8,12,18`; `.swiftlint.yml`; `Tests/.swiftlint.yml`; `lint --strict` → `Found 0 violations, 0 serious in 12 files.` rc 0. |
| T3 | ✅ Done | `Package.swift:1,6,9,11,16-26`; graph check now asserts platform + tools version. |
| T4 | ✅ Done | `Tests/NottiSharedTests/NottiLoggerTests.swift` 4 tests pass. One unclaimed branch (F3, note). |
| T5 | ✅ Done | `Tests/NottiSharedTests/NottiPayloadKeysTests.swift:8-19`; F4 killed. |
| T6 | ✅ Done | `Tests/NottiSDKTests/PrivacyManifestTests.swift` 2 tests pass; G6 killed. |
| T7 | ✅ Done | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift` passes; G5 killed. |
| T8 | ✅ Done | `pod lib lint` full rc 0 and `--subspec=Extension --verbose` rc 0; the Extension lint compiles only the 3 `NottiShared` + 2 `NottiSDKExtension` Swift files (0 `Sources/NottiSDK/*.swift`). |
| T9 | ✅ Done | `version ok: 0.1.0` rc 0 (macOS + `ubuntu:24.04`); G4 drift killed. |
| T10 | ✅ Done | See round-1 row; F5 killed. |
| T11 | ✅ Done | Strict device builds verbatim from `ci.yml:96-98` rc 0 with empty logs (only `IDERunDestination` noise); full suite 6/2/1. |
| T12 | ✅ Done | `ci.yml` 4 jobs; run 38079032514 on `88e939e` all success. |
| Round-5 Fix 1 + Fix 2 (`88e939e`) | ✅ Done | Both closed (rows above); no regression found. |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Status |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `.iOS(.v15)` and exactly two library products `NottiSDK`, `NottiSDKExtension` | `Package.swift:6,9,11`. `scripts/check-package-graph.sh:43` `spm.get("platforms") != [{"platformName": "ios", "version": "15.0", "options": []}]` → error; `:49` products dict equality. F2, G1 (`+ .macOS(.v12)`), G3 (no `platforms`) killed with named errors; `.iOS("15.0")` (equivalent) passes. | ✅ PASS |
| PKG-02 | NSE links `NottiSDKExtension` | No `NottiSDK` in its graph; shared code in internal non-product target | `Package.swift:16,22-26`; `check-package-graph.sh:61-71` (`NottiShared` deps `[]`, `NottiSDKExtension` exactly `[byName:NottiShared]`). M-D1, M-D1b killed. SPM source widening via `path:`/`sources:` rejected by SwiftPM itself (round 5 F1, sources unchanged). | ✅ PASS |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics | `ci.yml:98` strict extension build with `APPLICATION_EXTENSION_API_ONLY=YES` rc 0; `check-extension-safety.sh:26-34` rc 0 clean, rc 1 on planted `UIApplication.shared` / `import UIKit` and nested `registerForRemoteNotifications()` (F5), macOS + GNU. | ✅ PASS |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds; warnings are errors in CI | Device: `ci.yml:96-98` verbatim → `sdk rc=0`, `ext rc=0`, no warnings. Simulator: `xcodebuild test` (not strict) + `pod lib lint` (simulator, no `--allow-warnings`) rc 0. | ✅ PASS + spec-precision note (unchanged) |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local full rc 0, `--subspec=Extension` rc 0 (`NottiSDK passed validation.` ×2); CI 38079032514 same ×2. | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default Core; Extension gets Extension + Shared sources only | `NottiSDK.podspec:24,27-43`; `check-package-graph.sh:87` default Core; `:92-117` exact subspec shapes; `:77-84` root allowlist. Kills M-D2, M-F1/2/4, N1-N6. Extension lint compiles 0 Core files. Real Podfile app+NSE test still not run (`STATE.md:109`). | ✅ PASS (note) |
| PKG-07 | Podspec globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,41` all under `Sources/`; any other glob or root `source_files`/`testspecs` fails `check-package-graph.sh:82-84,116`. | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner builds both products for Simulator, runs all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7,31,45-76,100-119`. Run 38079032514 (`pull_request`, `88e939e`): 4 jobs success; `Executed 6 tests` / `2 tests` / `1 test`, `** TEST SUCCEEDED **`; `Found 0 violations`; `package graph ok`; `NottiSDK passed validation.` ×2. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (`2756451`) `failure` on the deliberate failing test; `set -o pipefail` `ci.yml:69,95`; graph check `sys.exit(1)` (`check-package-graph.sh:122`). | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log | `ci.yml:73,85-89`; round-1 row (probe run emitted the warning). | ✅ PASS |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | Local: `NottiSharedTests.xctest` passed (Executed 6), `NottiSDKTests.xctest` (2), `NottiSDKExtensionTests.xctest` (1); CI same. | ✅ PASS |
| PKG-11 | `NottiSDK` consumed | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone + CoarseLocation + ProductInteraction, not tracking | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `["CA92.1"]`; `:35-40` set of the 4 types; `:43` tracking false per entry. G6 killed. SPM path only. | ✅ PASS (note) |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false. G5 killed. | ✅ PASS |
| PKG-13 | Later feature adds API/data type | That feature updates the manifest | Process rule (`AGENTS.md`, Privacy and logging). | ✅ N/A in scope |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; `Tests/NottiSharedTests/NottiSDKVersionTests.swift:7-10` semver assertion. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec version ≠ constant | `scripts/check-version.sh:21-24`, `ci.yml:40`; G4 (`s.version = '0.1.1'`) → `error: version drift: NottiSDKVersion.current=0.1.0, NottiSDK.podspec s.version=0.1.1` rc 1. | ✅ PASS |
| PKG-16 | Repo cloned | Hygiene files present | `.gitignore:5,8,12,18`; `LICENSE:1` `MIT License`; `README.md:5,23,37`; `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` rc 0 `Found 0 violations, 0 serious in 12 files.`; CI same. | ✅ PASS |

**Status**: ✅ All 17 ACs covered with evidence and a discriminating guard. Spec-precision notes unchanged: PKG-04 (simulator compile not strict), PKG-06 (Podfile test), PKG-11 (CocoaPods resource branch).

### Edge cases

- [x] Only `NottiSDKExtension` in an app target: documented `README.md:37`; product builds standalone (strict device build rc 0).
- [x] Both products in one binary, no duplicate symbols: full `pod lib lint` builds Shared+Core+Extension together and passes; round-2 SPM consumer (sources unchanged since).
- [x] `swift-tools-version` stays 5.9: `Package.swift:1`, now guarded by `check-package-graph.sh:45` (F2b `6.0` and G2 `5.10` killed with named errors; `// swift-tools-version: 5.9` with a space passes).

### Success criteria

- [x] Fresh project links both products and builds (round-2 SPM consumer; real NSE appex is `example-and-release`).
- [x] CI green on `main` (38012837541, `2511ac1`) and on head (38079032514, `88e939e`); red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations, local and CI).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/verifier6/wt HEAD` with `-derivedDataPath <scratch>/verifier6/dd-wt`; each mutation applied by exact-anchor replace (asserted unique), run, reverted with `git checkout -- .` and checked clean. Extension-safety and version cases on a `git archive` copy in `ubuntu:24.04`; flaky-pattern replay on CI logs saved to scratch; stderr robustness via a PATH shim for `swift`/`pod`. The real tree was never touched.

| # | Target (`file:line`) | Fault | Detector → output | Killed? |
| --- | --- | --- | --- | --- |
| R1-a | `ci.yml:85` | Real retry line (CI 38015155294) | 1 match in the `Unit tests` step (BSD + GNU); head 0 | ✅ Killed |
| R1-b | `scripts/check-extension-safety.sh:17-22` | `NottiShared` missing + `UIApplication.shared` planted, GNU grep | `error: expected directory not found` rc 1 (`247befa` script rc 0) | ✅ Killed |
| M-D1 | `Package.swift:24` | `NottiSDKExtension` deps `+ "NottiSDK"` | graph rc 1, names `byName:NottiSDK` | ✅ Killed |
| M-D1b | `Package.swift:24` | `+ .target(name: "NottiSDK")` | graph rc 1, names `target:NottiSDK` | ✅ Killed |
| M-D2 | `NottiSDK.podspec:40` | Extension `+ ss.dependency 'NottiSDK/Core'` | graph rc 1 | ✅ Killed |
| M-F1 | `NottiSDK.podspec:41` | Extension globs add `Sources/NottiSDK/**/*.swift` | graph rc 1 | ✅ Killed |
| M-F2 | `NottiSDK.podspec:28` | Shared `Sources/{NottiShared,NottiSDK}/**/*.swift` | graph rc 1 | ✅ Killed |
| M-F4 | `NottiSDK.podspec:28` | Shared `Sources/**/*.swift` | graph rc 1 | ✅ Killed |
| N1 | `NottiSDK.podspec:41` | Extension `+ ss.ios.source_files` (Core glob) | graph rc 1, `'ios': {'source_files': …}` | ✅ Killed |
| N2 | `NottiSDK.podspec:41` | Extension `+ ss.ios.dependency 'NottiSDK/Core'` | graph rc 1 | ✅ Killed |
| N3 | `NottiSDK.podspec:28` | Shared `+ ss.ios.source_files` (Core glob) | graph rc 1 | ✅ Killed |
| N4 | `NottiSDK.podspec:41` | Extension `+ ss.dependency 'NottiSDK'` | `error: 'pod ipc spec NottiSDK.podspec' failed:` + CocoaPods reason (from the stderr file), rc 1 | ✅ Killed |
| N5 | `NottiSDK.podspec:42` | Extension `+ ss.ios.resource_bundles` (Core manifest) | graph rc 1 | ✅ Killed |
| N6 | `NottiSDK.podspec:41` | Nested `ss.subspec 'Helpers'` with a Core glob | graph rc 1, `'subspecs': [{'name': 'Helpers', …}]` | ✅ Killed |
| F2 (R5 survivor) | `Package.swift:6` | `.iOS(.v15)` → `.iOS(.v16)` (PKG-01) | `error: SPM platforms must be exactly iOS 15.0, got [… 'version': '16.0'}]` rc 1 | ✅ Killed |
| F2b (R5 incidental) | `Package.swift:1` | tools `5.9` → `6.0` (edge case 3) | `error: SPM swift-tools-version must be 5.9, got {'_version': '6.0.0'}` rc 1, no traceback | ✅ Killed (clean message) |
| S1 (stderr) | `scripts/check-package-graph.sh:24` | Tools write a warning to stderr on success (PATH shim) | head → `package graph ok` rc 0 (no false positive); `fc2da93` control → `JSONDecodeError` rc 1 | ✅ Behaves as specified |
| G1 (fresh) | `Package.swift:6` | `+ .macOS(.v12)` (iOS-only, Out of Scope) | `SPM platforms must be exactly iOS 15.0, got [… ios 15.0 …, … macos 12.0 …]` rc 1 | ✅ Killed |
| G2 (fresh) | `Package.swift:1` | tools `5.9` → `5.10` | `got {'_version': '5.10.0'}` rc 1 | ✅ Killed |
| G3 (fresh) | `Package.swift:6` | Remove `platforms:` | `got []` rc 1 | ✅ Killed |
| G4 (fresh) | `NottiSDK.podspec:4` | `s.version` `0.1.0` → `0.1.1` (PKG-15) | `error: version drift: …=0.1.0, … s.version=0.1.1` rc 1 | ✅ Killed |
| G5 (fresh) | `Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy:12` | `C617.1` → `0A2A.1` (PKG-12) | `PrivacyManifestTests.swift:19` fails, `** TEST FAILED **` rc 65 | ✅ Killed |
| G6 (fresh) | `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy:6` | `NSPrivacyTracking` `<false/>` → `<true/>` (PKG-11) | `PrivacyManifestTests.swift:25` fails, rc 65 | ✅ Killed |
| F4 (re-run) | `Sources/NottiShared/NottiPayloadKeys.swift:26` | Drop `"aps."` prefix | `NottiPayloadKeysTests.swift:19` fails, rc 65 | ✅ Killed |
| F5 (re-run) | `scripts/check-extension-safety.sh:26` | Nested `Sources/NottiShared/Deep/Er/X.swift` with `registerForRemoteNotifications()`, GNU grep | rc 1 citing `X.swift:2` | ✅ Killed |
| F3 (re-run) | `Sources/NottiShared/NottiLogger.swift:61` | Remove `guard messageLevel != .none else { return }` | `** TEST SUCCEEDED **` | ❌ Survived - outside every package-foundation AC (logger is T4 / CORE-12; T4 Done-when covers *level* `.none`, not a *message* at `.none`). Note, not a blocker. |

False-positive probes (not mutants): `.iOS("15.0")` and `// swift-tools-version: 5.9` → `package graph ok` rc 0; core-port shape (`Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Sources/NottiShared/Parsing/NottiParsing.swift`, `Tests/NottiSDKTests/Fixtures/rn-0.6.0-state.plist` + `resources: [.copy("Fixtures")]` on `NottiSDKTests`, per `core-port/tasks.md:343-344`) → `package graph ok` rc 0.

**Sensor depth**: P1 packaging: 16 earlier mutants re-run (R1-a, R1-b, M-D1, M-D1b, M-D2, M-F1, M-F2, M-F4, N1-N6, F2, F2b) + 1 stderr behavior check (S1) + 6 fresh (G1-G6) + 3 earlier fresh re-runs (F3, F4, F5).
**Sensor outcome**: 25 mutants injected, 24 killed, 1 survived (F3, outside AC scope). Every mutant against an in-scope AC killed.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ `88e939e`: two `if` checks and a 4-line stderr change; nothing speculative. |
| Surgical changes | ✅ Only `scripts/check-package-graph.sh` and two `runs-on` lines. |
| No scope creep | ✅ |
| Matches patterns | ✅ Same `errors.append(f"… got {…!r}")` style as the rest of the script; header comment (`:3`) updated. |
| Spec-anchored outcome check | ✅ PKG-01 platform + edge case 3 now asserted on the exact spec values. |
| Per-layer Coverage Expectation met | ✅ `tasks.md:25,38` include the graph check. |
| Every test maps to a spec requirement | ✅ Logger/keys → T4/T5 + PKG-10; manifests → PKG-10/11/12; version → PKG-14. |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ |

`88e939e` review:

- **Correct.** `:43` compares the whole `platforms` list, so a raised, added or removed platform all fail; `:45` reads `toolsVersion._version`. Errors name the field and print the actual value.
- **`run()` (`:20-31`)**: stderr goes to a `mktemp` file removed by the `EXIT` trap; on failure it prints the command, its stderr, then its stdout, and exits 1 (the command substitution's failure propagates under `set -e`). Successful-command warnings are now silent; acceptable for a check script.
- **Low, fails closed**: the platform literal includes `"options": []`, a SwiftPM `dump-package` serialization detail. If a future toolchain omits empty `options`, the check fails with `got [...]` showing the difference (no silent pass). Verified on Xcode 27 locally and Xcode 26.6 in CI.
- **Cosmetic**: `ci.yml:111` comment still says `(PKG-02, PKG-06)` while the step name at `:112` says `(PKG-01, PKG-02, PKG-06)`.
- **False positives on planned work: none found** (probes above). The exact-shape friction for new podspec attributes (round 5 note) is unchanged and by design.

---

## Gate Check

- **Gate command** (Full, `tasks.md:38` + CI parity): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" -retry-tests-on-failure -test-iterations 2 CODE_SIGNING_ALLOWED=NO` (log to file, `perl alarm` timeout) + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`) + the two strict device builds verbatim from `ci.yml:96-98`.
- **Outcome**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, rc 0): NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1; no `Iteration 2` lines. SwiftLint `Found 0 violations, 0 serious in 12 files.` rc 0. `version ok: 0.1.0`, `extension safety ok` (macOS + `ubuntu:24.04`), `package graph ok` (all rc 0). `pod lib lint` full + Extension `NottiSDK passed validation.` rc 0. Device builds `NottiSDK` rc 0, `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) rc 0. Only non-compiler warnings in the test log (3× `appintentsmetadataprocessor … Metadata extraction skipped`).
- **Test count before feature**: 0 (greenfield). **After**: 9. **Delta**: +9. Unchanged vs rounds 1-5.
- **Skipped tests**: none. **Failures**: none.
- **CI (read-only)**: 38079032514 (`pull_request`, `88e939e`) success, 4 jobs (`lint`/`checks` on `Image: ubuntu-24.04`, `test`/`pod-lint` on `macos-26-arm64`, Xcode 26.6), annotations only the macOS capacity notice; 38078188795 (`fc2da93`), 38056359219 (`caac386`), 38016135612 (`b9a8785`) success; 38015155294 (`637f45e`, flaky probe) success + retry warning; 38012402254 (`2756451`) failure (deliberate); 38012837541 (`main`, `2511ac1`) success.

---

## Fix Plans

None blocking. Notes (non-blocking):

- PKG-04 spec precision: the simulator compile in `xcodebuild test` is not warnings-as-errors; `pod lib lint` (simulator, no `--allow-warnings`) and the strict device builds are the guards. Not recorded in `STATE.md` today.
- PKG-11: CocoaPods resource branch of `NottiSDKResources` / `NottiSDKExtensionResources` never executed in a test (`STATE.md:107`).
- Manifest purposes (`NSPrivacyCollectedDataTypePurposes`) not asserted (`STATE.md:108`).
- PKG-06 independent test (throwaway Podfile, app + NSE) not run (`STATE.md:109`).
- F3: `NottiLogger.log(.none, …)` reaching the sink is untested; belongs to `core-port`/CORE-12 if that behavior matters. Not recorded in `STATE.md` today.
- Cosmetic: `ci.yml:111` comment PKG list.

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ✅ Ready (round 6, owner-authorized extra round)

**Spec-anchored check**: 17/17 ACs with evidence and a discriminating guard; spec-precision notes PKG-04, PKG-06, PKG-11 (non-blocking).
**Sensor**: 25 injected, 24 killed, 1 survived (F3, outside AC scope).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; all three scripts rc 0; `pod lib lint` full + Extension pass; both strict device builds rc 0; CI 38079032514 green.

**What works**: every round 1-5 gap is closed with re-derived evidence; the SPM half now asserts platform and tools version with named errors; tool stderr no longer breaks parsing yet is still shown on failure; Linux jobs pinned to `ubuntu-24.04`; no false positive on the planned core-port shape.

**Issues found**: none blocking. Notes above.

**Next steps**: mark package-foundation done; optionally add STATE todos for the PKG-04 simulator-strictness note and F3 (logger `.none` message) so they are not lost.
