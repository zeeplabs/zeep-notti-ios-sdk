# Validation: package-foundation - FAIL ❌

**Date**: 2026-10-10
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..caac386` (code surface: `Package.swift`, `NottiSDK.podspec`, `Sources/`, `Tests/`, `scripts/`, `.github/`, hygiene files; 26 files, +936. Since round 3 (`3268452`) the code surface changed only in `caac386`: `scripts/check-package-graph.sh` +34/-1 (podspec file-pattern asserts, lines 66-95). Docs: `tasks.md:25,38` and `core-port/tasks.md:44` now list the graph check. `Sources/`, `Tests/`, `Package.swift`, the podspec, `ci.yml` and the other two scripts are byte-identical to round 3.)
**Verifier**: independent sub-agent (author ≠ verifier), round 4 (owner-authorized extra round)
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker), GNU grep 3.11 (`ubuntu:24.04`). CI evidence read-only (`gh run view`, `gh api …/check-runs/<id>/annotations`). No pushes, re-runs or edits on GitHub.

---

## Earlier gaps → status (rounds 1-3)

| Round | Gap | Status | Evidence (re-derived this round) |
| --- | --- | --- | --- |
| 1 | Flaky-test warning never fired on Xcode 26+ (PKG-09b) | ✅ Closed | Pattern read from `ci.yml:85` (`started \(Iteration [2-9][0-9]* of\|Restarting tests after unexpected exit`) replayed on the `Unit tests` step of probe run 38015155294 → 1 match (`…FlakyProbeTests test_failsOnceThenPasses]' started (Iteration 2 of 2).`); on the head run 38056359219 → 0 matches (9× `Iteration 1 of 2`). Same counts on BSD grep and GNU grep 3.11. Old `247befa` pattern on the probe log → 0 (gap reproduces against old code). Head run test-job annotations: only the runner-capacity notice, no warning. |
| 1 | `check-extension-safety.sh` silent pass on GNU grep with a missing dir (PKG-03) | ✅ Closed | `scripts/check-extension-safety.sh:17-22`. `ubuntu:24.04` on copies: clean → `extension safety ok` rc 0; `NottiShared` renamed + `UIApplication.shared` planted in `NottiSDKExtension` → `error: expected directory not found: /e/missing/Sources/NottiShared` rc 1; `import UIKit` planted in `NottiShared` → rc 1 citing `Planted.swift:1:import UIKit`. Control: `247befa` script on the missing-dir case → `grep: … No such file or directory` then `extension safety ok` rc 0. |
| 2 | No CI check for the NSE→app dependency edge: M-D1 (SPM), M-D2 (podspec) | ⚠️ Closed for the tested syntaxes, **open for platform-scoped dependencies** | M-D1 → `error: SPM target NottiSDKExtension must depend on ['byName:NottiShared'], got ['byName:NottiSDK', 'byName:NottiShared']` rc 1; M-D2 → `error: podspec subspec Extension must depend on ['NottiSDK/Shared'], got ['NottiSDK/Core', 'NottiSDK/Shared']` rc 1. But the same edge written `ss.ios.dependency 'NottiSDK/Core'` (N2) passes the graph check and both lints while the Extension-only lint compiles Core sources and the Core privacy manifest (see sensor). |
| 3 | Podspec glob widening leaks Core sources into the Extension pod: M-F1, M-F2, M-F4 | ⚠️ Closed for the plain `source_files` key, **open for equivalent podspec syntax** | `scripts/check-package-graph.sh:66-95`. M-F1 → `error: podspec subspec Extension source_files must be 'Sources/NottiSDKExtension/**/*.swift', got [...]` rc 1; M-F2, M-F4 → `error: podspec subspec Shared source_files must be 'Sources/NottiShared/**/*.swift', got [...]` rc 1. Same leak via `ss.ios.source_files` (N1, N3), `ss.ios.resource_bundles` (N5) or a nested subspec under `Extension` (N6) → `package graph ok` rc 0 (Gap 1). |
| 3 | `tasks.md` matrix / Full gate lacked the graph check | ✅ Closed | `tasks.md:25` Packaging row now names `scripts/check-package-graph.sh`; `tasks.md:38` Full gate includes it; `core-port/tasks.md:44` too. |

---

## Task Completion

Checked against artifacts, not the ✅ marks.

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | AD-006 in `.specs/project/STATE.md`; `NottiSDK.podspec:22` `-package-name NottiSDK`; `package` access compiles across subspecs (both lints pass). |
| T2 | ✅ Done | `.gitignore:5,6,8,12,13,18`; `.swiftlint.yml`; `Tests/.swiftlint.yml` disables `identifier_name`. `lint --strict` → `Found 0 violations, 0 serious in 12 files.` rc 0. |
| T3 | ✅ Done | `Package.swift:1,6,9,11,16-26`; graph check (`dump-package`) ok; no `unsafeFlags`/plugins. |
| T4 | ✅ Done | `Tests/NottiSharedTests/NottiLoggerTests.swift` 4 tests passed; sensor L1/L2 killed. |
| T5 | ✅ Done | `Tests/NottiSharedTests/NottiPayloadKeysTests.swift:8-19` passed. |
| T6 | ✅ Done | `Tests/NottiSDKTests/PrivacyManifestTests.swift` 2 tests passed; `plutil -lint` OK. |
| T7 | ✅ Done | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift` passed; `plutil -lint` OK. |
| T8 | ✅ Done | `pod lib lint` full rc 0 and `--subspec=Extension` rc 0 (`NottiSDK passed validation.`); Extension lint compiles only the 3 `NottiShared` + 2 `NottiSDKExtension` files. |
| T9 | ✅ Done | `scripts/check-version.sh` → `version ok: 0.1.0` rc 0 (macOS and `ubuntu:24.04`); unchanged since round 1 proved drift. |
| T10 | ✅ Done | See round-1 row. |
| T11 | ✅ Done | Both strict device builds verbatim from `ci.yml:96-98` rc 0; full suite 6/2/1. |
| T12 | ✅ Done | `ci.yml` 4 jobs; run 38056359219 on `caac386` all success. |
| Round-3 Fix 1 (`caac386`) | ⚠️ Partial | Plain `source_files` / `resource_bundles` / root-file drift guarded; platform-scoped attributes and nested subspecs not (Gap 1). Doc drift fixed. |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Result |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `.iOS(.v15)`, exactly two library products `NottiSDK`, `NottiSDKExtension` | `Package.swift:6,9,11`; `scripts/check-package-graph.sh:26` `products != {"NottiSDK": ["NottiSDK"], "NottiSDKExtension": ["NottiSDKExtension"]}` → error. Platform not asserted by a script; enforced by `Package.swift:6` and the builds. | ✅ PASS |
| PKG-02 | NSE links `NottiSDKExtension` | No `NottiSDK` target in its graph (direct/transitive); shared code in internal non-product target | `Package.swift:16,22-26`; `check-package-graph.sh:38-48` requires `NottiShared` deps `[]` and `NottiSDKExtension` deps exactly `[byName:NottiShared]`. M-D1 killed this round; SwiftPM rejects overlapping target sources (round 3). | ✅ PASS (SPM path guarded) |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics | `ci.yml:98` strict extension build with `APPLICATION_EXTENSION_API_ONLY=YES` rc 0; sensor M-A: `UIApplication.shared` in `NottiShared` → `Planted.swift:3:52: error: 'shared' is unavailable in application extensions for iOS` rc 65 (compiler leg works on Xcode 27); `check-extension-safety.sh` rc 0 (macOS + GNU) and kills planted cases. | ✅ PASS |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds; zero warnings treated as errors in CI | Device: `ci.yml:96-98` re-run verbatim → `sdk rc=0`, `ext rc=0`, no compiler warnings. Simulator: `xcodebuild test` (not strict) + `pod lib lint` (simulator, no `--allow-warnings`). | ✅ PASS + spec-precision note (unchanged) |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local full rc 0, `--subspec=Extension` rc 0; CI 38056359219 pod-lint `NottiSDK passed validation.` ×2. | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default Core; Extension gets only Extension + Shared sources, **no Core sources** | Holds today: `NottiSDK.podspec:24,28,40-42`; control Extension lint (`--verbose`) compiles 0 `Sources/NottiSDK/` files. Guard: `check-package-graph.sh:52-53` (default), `:56-64` (deps), `:66-95` (file patterns) - kills M-D2, M-F1, M-F2, M-F4. **Unguarded**: N1, N2, N3, N5, N6 leak Core sources / Core dependency / Core privacy bundle into the Extension-only pod with the graph check, both lints and every other gate step green (Gap 1). Real Podfile app+NSE test still not run (STATE todo). | ⚠️ Holds today, ❌ "no Core sources" clause still bypassable (Gap 1) |
| PKG-07 | Podspec globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,41` all under `Sources/`; any `Tests/` glob in the plain key now fails `check-package-graph.sh:88` (exact match). | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner builds both products for Simulator, runs all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7,24-31,45-76,100-119`. Run 38056359219 (`pull_request`, head `caac386`): lint/checks/test/pod-lint success; `Executed 6 tests` / `2 tests` / `1 test`, `** TEST SUCCEEDED **`; `Found 0 violations`; `package graph ok`. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (`2756451`) `failure` on the deliberate failing test; `set -o pipefail` `ci.yml:69,95`; graph step exits 1 on error (`check-package-graph.sh:99`). | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log | `ci.yml:73-74,81-89`; probe run 38015155294 matched; head run silent (round-1 row). | ✅ PASS |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | Local: `NottiSharedTests.xctest` passed (Executed 6), `NottiSDKTests.xctest` passed (2), `NottiSDKExtensionTests.xctest` passed (1); CI same. | ✅ PASS |
| PKG-11 | `NottiSDK` consumed | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone not tracking, + CoarseLocation + ProductInteraction | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `… as? [String], ["CA92.1"]`; `:35-40` set of the 4 types; `:43` tracking false per entry. SPM path only. | ✅ PASS (SPM), note |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false. | ✅ PASS |
| PKG-13 | Later feature adds API/data type | That feature updates manifest | Process rule, `AGENTS.md`. | ✅ N/A in scope (rule documented) |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; `Tests/NottiSharedTests/NottiSDKVersionTests.swift:7-10` semver assertion. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec version ≠ constant | `scripts/check-version.sh:13-24`, `ci.yml:39-40`; local + CI `version ok: 0.1.0`. | ✅ PASS |
| PKG-16 | Repo cloned | Hygiene files present | `.gitignore:5-18`; `LICENSE:1` `MIT License`; `README.md` status + install + misconfiguration note (`:37`); `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` rc 0 `Found 0 violations, 0 serious in 12 files.`; CI 38056359219 same line. | ✅ PASS |

**Status**: ❌ Gap present: PKG-06 "no Core sources" clause still bypassable on the CocoaPods path (Gap 1). Spec-precision notes unchanged: PKG-04 (simulator compile not strict), PKG-06 (Podfile test), PKG-11 (CocoaPods resource branch).

### Edge cases

- [x] Only `NottiSDKExtension` in an app target: documented `README.md:37`; product builds standalone (strict device build rc 0).
- [x] Both products in one binary, no duplicate symbols: full `pod lib lint` builds Shared+Core+Extension together and passes; round-2 SPM consumer (sources unchanged since).
- [x] `swift-tools-version` stays 5.9: `Package.swift:1`.

### Success criteria

- [x] Fresh project links both products and builds (round-2 SPM consumer; real NSE appex is `example-and-release`).
- [x] CI green on `main` (38012837541, `2511ac1`) and on head (38056359219, `caac386`); red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations, local and CI).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/verifier4/wt HEAD` with `-derivedDataPath` in scratch; one nested-subspec case and the false-positive probe on a `git archive` copy (`<scratch>/verifier4/cp2`); extension-safety cases on copies in `ubuntu:24.04`; flaky-pattern replay on CI logs saved to scratch. Each mutation applied, run, then reverted with `git checkout`. The real tree was never touched.

| # | Target (`file:line`) | Fault | Detector → output | Killed? |
| --- | --- | --- | --- | --- |
| R1-a (re-run) | `ci.yml:85` | Real retry line `started (Iteration 2 of 2)` (CI 38015155294) | Pattern matches (BSD + GNU); head log silent | ✅ Killed |
| R1-b (re-run) | `scripts/check-extension-safety.sh:17-22` | `NottiShared` missing + `UIApplication.shared` planted, GNU grep | `error: expected directory not found` rc 1 (old script rc 0) | ✅ Killed |
| M-D1 (re-run) | `Package.swift:24` | `NottiSDKExtension` deps `+ "NottiSDK"` | graph rc 1, names `byName:NottiSDK` | ✅ Killed |
| M-D2 (re-run) | `NottiSDK.podspec:41` | Extension `+ ss.dependency 'NottiSDK/Core'` | graph rc 1, names `NottiSDK/Core` | ✅ Killed |
| M-F1 (re-run) | `NottiSDK.podspec:41` | Extension `source_files` adds `Sources/NottiSDK/**/*.swift` | graph rc 1, `subspec Extension source_files must be …` | ✅ Killed |
| M-F2 (re-run) | `NottiSDK.podspec:28` | Shared `Sources/{NottiShared,NottiSDK}/**/*.swift` | graph rc 1, `subspec Shared source_files must be …` | ✅ Killed |
| M-F4 (re-run) | `NottiSDK.podspec:28` | Shared `Sources/**/*.swift` | graph rc 1, same | ✅ Killed |
| N4 | `NottiSDK.podspec:41` | Extension `+ ss.dependency 'NottiSDK'` (root = default Core) | CocoaPods rejects (`A subspec can't require one of its parents specifications`), graph rc 1 (fails closed, but prints nothing - see Code Quality) | ✅ Killed |
| L1 | `Sources/NottiShared/NottiLogger.swift:63` | `messageLevel <= currentLevel` → `<` | `NottiLoggerTests.swift:28,36,37` fail, `** TEST FAILED **` rc 65 | ✅ Killed |
| L2 | `Sources/NottiShared/NottiLogger.swift:61` | Evaluate the autoclosure before the level guard (lazy evaluation removed) | `NottiLoggerTests.swift:51` `XCTAssertFalse failed` | ✅ Killed |
| M-A (re-run, compiler leg) | `Sources/NottiShared/Planted.swift` (new) | `UIApplication.shared.applicationIconBadgeNumber` in shared code | `ci.yml:98` build → `error: 'shared' is unavailable in application extensions for iOS` rc 65 | ✅ Killed |
| **N1** | `NottiSDK.podspec:41` | Extension `+ ss.ios.source_files = 'Sources/NottiSDK/**/*.swift'` | graph `package graph ok` rc 0; `check-version`/`check-extension-safety` rc 0; `pod lib lint` full rc 0 and `--subspec=Extension` rc 0 **while compiling `Sources/NottiSDK/NottiSDK.swift` and `NottiSDKResources.swift`** (control: 0 Core files) | ❌ Survived |
| **N2** | `NottiSDK.podspec:41` | Extension `+ ss.ios.dependency 'NottiSDK/Core'` (the R2 edge, platform-scoped) | graph rc 0 (`pod ipc spec` puts it under `"ios": {"dependencies": …}`); Extension lint rc 0 compiling both Core files and `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy` | ❌ Survived |
| **N3** | `NottiSDK.podspec:28` | Shared `+ ss.ios.source_files = 'Sources/NottiSDK/**/*.swift'` | graph rc 0; Extension lint rc 0 compiling both Core files | ❌ Survived |
| **N5** | `NottiSDK.podspec:42` | Extension `+ ss.ios.resource_bundles = { 'NottiSDK_Privacy' => [Core manifest] }` | graph rc 0; Extension lint rc 0 shipping `NottiSDK_Privacy.bundle` with the Core manifest | ❌ Survived |
| **N6** | `NottiSDK.podspec:41` | Nested `ss.subspec 'Helpers'` under Extension with `source_files = 'Sources/NottiSDK/**/*.swift'` | graph rc 0 (nested `subspecs` key never read); Extension lint rc 0 compiling both Core files | ❌ Survived |

No podspec mutation touches `Package.swift` or Swift code, so the SPM test suite, SwiftLint and the device builds cannot see N1-N6 either.

**Sensor depth**: P1 packaging, focused on the round-3 fix: 7 earlier survivors/kills re-run (R1-a, R1-b, M-D1, M-D2, M-F1, M-F2, M-F4) + 9 fresh (N1-N6, L1, L2, M-A).
**Sensor result**: 16 injected, 11 killed, 5 survived (N1, N2, N3, N5, N6 - one root cause) - FAIL ❌.

Root cause: `check-package-graph.sh:55-95` validates a fixed list of top-level keys (`dependencies`, `source_files`, `resource_bundles`, `resources`) on each subspec as they appear in `pod ipc spec` JSON. CocoaPods also merges platform-scoped attributes (`ios`, `osx`, …) and nested subspecs into what a consumer of `NottiSDK/Extension` compiles, and the script never reads those keys. The header claim (`:5-6`, "each subspec compiles exactly its own Sources/ folder") is therefore not true for every podspec that CocoaPods accepts.

Severity judgment: the leak class is the same one the owner treated as blocking in round 3 (Core code in every RN app's NSE with CI green). N1-N3/N5 need syntax that is unusual in an iOS-only pod but valid and common in copy-pasted podspecs; N2 also reopens the round-2 dependency edge. Realism is lower than M-F1/M-F4, so this could be accepted as a documented risk instead of fixed.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ `caac386` adds ~30 lines to the existing script; no new files. |
| Surgical changes | ✅ Only the script and two `tasks.md` rows. |
| No scope creep | ✅ |
| Matches patterns | ✅ Same structure as the round-2 checks; errors name the subspec and the offending value. |
| Spec-anchored outcome check | ⚠️ Asserts podspec syntax, not the PKG-06 outcome ("Extension gets no Core sources"); see Gap 1. |
| Per-layer Coverage Expectation met | ✅ `tasks.md:25,38` now include the graph check. |
| Every test maps to a spec requirement | ✅ Unchanged (logger/keys → T4/T5 + PKG-10; manifests → PKG-10/11/12; version → PKG-14). |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ |

`check-package-graph.sh` review:

- Readable and correct for what it checks; the `as_list` normalization (`:71-74`) handles string vs list; root-spec check (`:67-69`) is cheap future-proofing.
- **False positives on planned work: none found.** Probe on a copy with the core-port shape (`Sources/NottiSDK/Runtime/NottiRuntime.swift` + `Tests/NottiSDKTests/Fixtures/` + `resources: [.copy("Fixtures")]` on the `NottiSDKTests` test target) → `package graph ok` rc 0. New files under existing folders match the `**` globs; test targets are ignored (`:37`, only `type == "regular"`); `NottiSDK`/`Core` dependencies are not constrained. Expected friction, by design: a later feature adding a resource to Core or Extension (or a new subspec key) must update the script's expected values.
- Minor: when `pod ipc spec` or `swift package dump-package` fails (`:16-17`), the error goes to the captured stdout and the script exits 1 with no message (N4). Fails closed, but undiagnosable in CI. Low.
- Minor (from round 3, still present): `.target(name: "NottiShared")` is rejected (only `byName:` accepted). False positive that fails safe. Low.

---

## Gate Check

- **Gate command** (Full, `tasks.md:38` + CI parity): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`) + the two strict device builds verbatim from `ci.yml:94-98`.
- **Result**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, rc 0): NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1. SwiftLint `Found 0 violations, 0 serious in 12 files.` rc 0. `version ok: 0.1.0`, `extension safety ok` (macOS + `ubuntu:24.04`), `package graph ok` (all rc 0). `pod lib lint` full + Extension `NottiSDK passed validation.` rc 0. Device builds `NottiSDK` rc 0, `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) rc 0. Only non-compiler warnings in the test log (3× `appintentsmetadataprocessor … Metadata extraction skipped`).
- **Test count before feature**: 0 (greenfield). **After**: 9. **Delta**: +9. Unchanged vs rounds 1-3 (`Tests/` untouched).
- **Skipped tests**: none. **Failures**: none.
- **CI (read-only)**: 38056359219 (`pull_request`, `caac386`) success, 4 jobs, `package graph ok`, no warning annotation; 38016135612 (`b9a8785`) success; 38015311084 (`288bafa`) success; 38015155294 (`637f45e`, flaky probe) success + retry line; 38012402254 (`2756451`) failure (deliberate); 38012837541 (`main`, `2511ac1`) success.

---

## Fix Plans

### Fix 1: the CocoaPods guard checks podspec syntax, not the effective Extension file set - Major (or accepted risk)

- **Root cause**: `scripts/check-package-graph.sh:55-95` reads only top-level `dependencies` / `source_files` / `resource_bundles` / `resources` of each subspec. Platform-scoped attributes (`ss.ios.*`) and nested subspecs reach `NottiSDK/Extension` without touching those keys.
- **Fix task (smallest that closes the class)**: in the CocoaPods half, add a key allowlist so any attribute the script does not validate fails the check:
  - each of `Shared`, `Core`, `Extension` may only have keys `{name, source_files, dependencies, resource_bundles}` (current set; verified from `pod ipc spec`); anything else (`ios`, `osx`, `subspecs`, `exclude_files`, `vendored_frameworks`, …) → error naming the subspec and key;
  - the root may not have platform keys (`ios`, `osx`, `tvos`, `watchos`, `visionos`) and may only have the subspecs `Shared`, `Core`, `Extension`;
  - when `pod ipc spec` / `dump-package` fails, print its output to stderr (N4 diagnostics).
  Alternative (behavior-level, more code): evaluate the podspec in Ruby (`Pod::Specification.from_file`), walk the `NottiSDK/Extension` dependency closure with `consumer(:ios)` (merges platform attributes) and nested subspecs, expand the globs, and fail on any path under `Sources/NottiSDK/`.
- **Verify**: on a scratch copy, N1, N2, N3, N5, N6 each exit 1 naming the subspec/key; M-D1, M-D2, M-F1, M-F2, M-F4 still exit 1; clean tree and the core-port-shape probe exit 0; CI green on the new head.
- **Alternative if the owner declines**: record an accepted risk in STATE ("podspec platform-scoped attributes and nested subspecs are review-guarded until `example-and-release` builds a real NSE via CocoaPods"). The allowlist closes the whole syntactic class, so a further round would only need to confirm closure, not hunt new syntax.

### Notes (already tracked as STATE todos, non-blocking)

- PKG-04 spec precision: the simulator compile in `xcodebuild test` is not warnings-as-errors; `pod lib lint` (simulator, no `--allow-warnings`) and the strict device builds are the guards.
- PKG-11: CocoaPods resource branch (`NottiSDKResources.swift:12-18`, `NottiSDKExtensionResources.swift:12-18`) never executed in a test.
- Manifest purposes (`NSPrivacyCollectedDataTypePurposes`) not asserted.
- PKG-06 independent test (throwaway Podfile, app + NSE) not run. It would not catch N1-N6 either (the NSE still builds); only a file-set check does.

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-01, 02, 03, 04, 05, 07, 08, 09, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-06 | Done | ⚠️ Holds today; "no Core sources" clause bypassable via platform-scoped attributes / nested subspecs → Needs Fix (Fix 1) or accepted risk |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ❌ Not Ready (round 4, owner-authorized extra round - decision goes back to the owner)

**Spec-anchored check**: 17/17 ACs hold on the current tree with evidence; PKG-06's source-isolation guard is bypassable by valid podspec syntax. Spec-precision notes: PKG-04, PKG-06, PKG-11.
**Sensor**: 16 injected, 11 killed, 5 survived (N1, N2, N3, N5, N6: platform-scoped `ss.ios.*` attributes and a nested subspec leak Core sources / Core dependency / Core privacy bundle into the Extension pod).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; all three scripts rc 0; `pod lib lint` full + Extension pass; both strict device builds rc 0; CI 38056359219 green.

**What works**: round-1 gaps closed and proven against old code; round-3 plain-glob leaks (M-F1/M-F2/M-F4) and doc drift fixed; SPM split fully guarded; logger tests discriminate (L1, L2); the extension-API compiler leg works on Xcode 27 (M-A); no false positive for the planned core-port changes.

**Issues found**: Fix 1 (key allowlist in `check-package-graph.sh`, ~10 lines) or an accepted-risk entry in STATE. Minor: swallowed `pod ipc spec` error output.

**Next steps**: owner decides between Fix 1 plus a closure-confirmation run, or recording the accepted risk.
