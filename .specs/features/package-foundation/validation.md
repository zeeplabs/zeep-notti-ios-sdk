# Validation: package-foundation - FAIL ❌

**Date**: 2026-10-09
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..288bafa` (code surface: `Package.swift`, `NottiSDK.podspec`, `Sources/`, `Tests/`, `scripts/`, `.github/`, hygiene files; round-1 fix is `ebf0a11`, which touches only `.github/workflows/ci.yml` and `scripts/check-extension-safety.sh`)
**Verifier**: independent sub-agent (author ≠ verifier), round 2
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker), GNU grep 3.11 (`ubuntu:24.04`). CI evidence read-only (`gh run view`, `gh api …/check-runs/<id>/annotations`).

---

## Round 1 gaps → status

| Round 1 gap | Status | Evidence |
| --- | --- | --- |
| Fix 1: flaky-test warning never fired on Xcode 26+ (PKG-09b) | ✅ Closed | `ci.yml:85` pattern `started \(Iteration [2-9][0-9]* of\|Restarting tests after unexpected exit`. CI run 38015155294 (head `637f45e`, throwaway `FlakyProbeTests`): log line `FlakyProbeTests test_failsOnceThenPasses … started (Iteration 2 of 2)` → `passed`, `** TEST SUCCEEDED **`, step printed `##[warning]Tests needed a retry …`; `gh api …/check-runs/114103674259/annotations` → `warning \| Tests needed a retry - a test is flaky, not just green.` Final head run 38015311084 (job 114104157938): no warning annotation (only the runner capacity notice). Verifier replay of the exact step body against both reconstructed logs: probe → warning + `1046:… started (Iteration 2 of 2).`; clean (9× `Iteration 1 of 2` only) → silent. Same on macOS BSD grep and GNU grep. Round-1 pattern on the probe log → 0 matches (the old step would have stayed silent). |
| Fix 2: `check-extension-safety.sh` passed silently on GNU grep when a scanned dir was missing | ✅ Closed | `scripts/check-extension-safety.sh:17-22` (dir must exist) and `:25-38` (grep rc 0 → fail, rc >1 → fail). `ubuntu:24.04` runs: clean → `extension safety ok` rc 0; `NottiShared` renamed → `error: expected directory not found` rc 1; renamed + planted `UIApplication.shared` in `NottiSDKExtension` → rc 1; `NottiSDKExtension` removed → rc 1; planted in `NottiShared` → rc 1 with `Planted.swift:2`; nested `Sub/P.swift` with `import UIKit` → rc 1; unreadable dir (non-root) → `error: grep failed with exit code 2` rc 1. Same 8 cases on macOS BSD grep → identical exit codes. Control: round-1 script (`247befa`) on the renamed+planted case under GNU grep → `extension safety ok` rc 0 (the original survivor reproduces against old code, killed by new code). |
| Fix 3 (optional): compile-level `APPLICATION_EXTENSION_API_ONLY` | ✅ Done | `ci.yml:96-98`: device builds use `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`, extension build adds `APPLICATION_EXTENSION_API_ONLY=YES`. Fresh-DerivedData build log shows `-application-extension` and `-warnings-as-errors` on the swiftc invocations; sensor M-A/M-B below prove both settings bite. CI 38015311084 ran this step successfully. |
| PKG-04 note: only `pod lib lint` failed on warnings | ✅ Addressed | Device builds of both products now fail on a warning (sensor M-B, M-B2). Simulator compile in `xcodebuild test` is still not warnings-as-errors; `pod lib lint` (simulator) remains the guard there. See spec-precision note. |

---

## Task Completion

Checked against artifacts, not the ✅ marks.

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | `.specs/project/STATE.md:45-55` AD-006 records the spike; todo closed `STATE.md:102`. Throwaway not in repo by design. |
| T2 | ✅ Done | `.gitignore:6,8,12,13,18`; `.swiftlint.yml:4-26`; `Tests/.swiftlint.yml:2-3`; image pinned `.swiftlint.yml:1`, `ci.yml:21`. `lint --strict` → `Found 0 violations, 0 serious in 12 files.` |
| T3 | ✅ Done | `swift package dump-package`: tools `5.9.0`, platforms `[('ios','15.0')]`, products `NottiSDK`, `NottiSDKExtension` (library); `NottiSDKExtension` deps `['NottiShared']`; no settings/plugins; `grep unsafeFlags\|plugins Package.swift` rc 1. |
| T4 | ✅ Done | `NottiLogger.swift:38` default `.error`; tests `NottiLoggerTests.swift:21-59`; sink/level reset `:15-18`. |
| T5 | ✅ Done | `NottiPayloadKeys.swift:9-26`, frozen by `NottiPayloadKeysTests.swift:8-19`. |
| T6 | ✅ Done | `plutil -lint` OK; test asserts tracking, `CA92.1`, 4 types, linked/tracking flags. |
| T7 | ✅ Done | `plutil -lint` OK; test asserts `C617.1` + tracking false. |
| T8 | ✅ Done | `pod lib lint --platforms=ios` → `NottiSDK passed validation.` rc 0; `--subspec=Extension` rc 0. `pod ipc spec`: `default_subspecs Core`, version `0.1.0`, globs only under `Sources/`. |
| T9 | ✅ Done | `scripts/check-version.sh` → `version ok: 0.1.0` rc 0 (CI 38015311084 same line). Drift behavior re-proven by round 1; script unchanged since (`git diff 247befa..HEAD -- scripts/check-version.sh` empty). |
| T10 | ✅ Done | Was ⚠️ in round 1; now all Done-when outcomes hold on GNU and BSD grep (see Fix 2 row above). |
| T11 | ✅ Done | Device builds re-run exactly as `ci.yml:94-98` → rc 0 both; full gate 6/2/1. |
| T12 | ✅ Done | Was ⚠️ in round 1; flaky step now functional (CI probe run + annotation). Triggers `ci.yml:3-7`. |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Result |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `.iOS(.v15)`, exactly two library products `NottiSDK`, `NottiSDKExtension` | `Package.swift:6` `platforms: [.iOS(.v15)]`; `Package.swift:9,11`. dump-package: `platforms [('ios','15.0')]`, `products [('NottiSDK',…,['library']), ('NottiSDKExtension',…,['library'])]` | ✅ PASS |
| PKG-02 | NSE links `NottiSDKExtension` | Build graph has no `NottiSDK` target; shared code in internal non-product target | `Package.swift:16,22-26`; dump-package `NottiSDKExtension regular ['NottiShared']`. Strict device build of scheme `NottiSDKExtension` (fresh DerivedData) built only `NottiShared`, `NottiSDKExtension`, `NottiSDK_NottiSDKExtension`. `NottiSDK.podspec:39-43` Extension depends only on `NottiSDK/Shared`. **True today, but no gate step detects a regression**: sensor M-D1/M-D2 survived the whole gate + CI-equivalent pipeline. | ⚠️ PASS today, ❌ unguarded (Gap 1) |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics | Compiler leg: `ci.yml:98` builds `NottiSDKExtension` (which compiles `NottiShared`) with `APPLICATION_EXTENSION_API_ONLY=YES`; sensor M-A: planted `UIApplication.shared` in `NottiShared` → `error: 'shared' is unavailable in application extensions for iOS` rc 65; control without the flag → rc 0. Grep leg: `scripts/check-extension-safety.sh:12-38`, CI `ci.yml:42-43`, CI 38015311084 `extension safety ok`. Real appex build in `example-and-release`. | ✅ PASS |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds, zero warnings treated as errors in CI | Device: `ci.yml:96-98` strict flags; local run rc 0 both; sensor M-B/M-B2 (unused var in `NottiSDK` / `NottiSDKExtension`) → `error: initialization of immutable value 'unused' was never used` rc 65. Simulator: built by `xcodebuild test` (`ci.yml:70-76`, not strict) and by `pod lib lint` (fails on warnings, round 1 sensor #6). | ✅ PASS + spec-precision note |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local full rc 0, `--subspec=Extension` rc 0 (`NottiSDK passed validation.`). CI 38015311084 pod-lint log lines 157, 178 `NottiSDK passed validation.` | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default Core; Extension gets only Extension + Shared sources | `NottiSDK.podspec:24` `s.default_subspecs = 'Core'`; `:39-43`. `pod ipc spec`: Extension deps `{'NottiSDK/Shared'}`, globs `Sources/NottiSDKExtension/**/*.swift`. Real Podfile app+NSE test not run (STATE todo). Regression unguarded: see Gap 1 (M-D2). | ✅ PASS (structural), note |
| PKG-07 | Podspec globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,35,41,42` all under `Sources/`; no `test_spec`; `pod ipc spec` source_files confirm. | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner: build both products for Simulator, run all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7,46,67-76,100-115,24-31`. Run 38015311084 (PR, `288bafa`): lint/checks/test/pod-lint success; test log `Executed 6 tests` (shared) + 2 + 1, `** TEST SUCCEEDED **`; lint `Found 0 violations`. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (round-1 evidence, workflow semantics unchanged in `ebf0a11` for the test step): `test=failure`, `** TEST FAILED **`. `set -o pipefail` `ci.yml:69,95`. | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log | `ci.yml:73-74` retry flags; `ci.yml:81-89` step with `if: always()`. Run 38015155294 annotation `warning \| Tests needed a retry …`; log `1027:Test Case '-[NottiSharedTests.FlakyProbeTests test_failsOnceThenPasses]' started (Iteration 2 of 2).` Clean run 38015311084: no warning. | ✅ PASS |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | `NottiSDKVersionTests.swift:7-10`, `NottiLoggerTests.swift:21-59`, `NottiPayloadKeysTests.swift:8-19` (shared); `Tests/NottiSDKTests/PrivacyManifestTests.swift:17-19` (app); `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:6-19` (NSE). Local gate 6/2/1 passed. | ✅ PASS |
| PKG-11 | `NottiSDK` consumed | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone not tracking, + CoarseLocation + ProductInteraction | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `… ["CA92.1"]`; `:35-40` set of 4 types; `:43` `Tracking == false` per entry. SPM path tested; CocoaPods path compiled by lint only (STATE todo). | ✅ PASS (SPM), note |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false (sensor M-C killed). | ✅ PASS |
| PKG-13 | Later feature adds API/data type | That feature updates manifest | Process rule, `AGENTS.md:68`. Nothing to verify in this feature. | ✅ N/A in scope (rule documented) |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; consumers `NottiSDK.swift:8`, `NottiSDKExtension.swift:8`. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec version ≠ constant | `scripts/check-version.sh:13-24`, `ci.yml:39-40`; CI `version ok: 0.1.0`. Drift kill proven in round 1, script unchanged since `247befa`. | ✅ PASS |
| PKG-16 | Repo cloned | Hygiene files present | `.gitignore:8,12,18`; `LICENSE:1` MIT; `README.md:5` status, `:14-35` install snippets; `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` rc 0, `Found 0 violations, 0 serious in 12 files.`; CI 38015311084 lint log line 338 same. | ✅ PASS |

**Status**: ❌ Gaps present: PKG-02 (and the PKG-06 Extension half) hold today but have no regression detector (Gap 1). Spec-precision notes: PKG-04 (simulator compile), PKG-06, PKG-11.

### Edge cases

- [x] Only `NottiSDKExtension` in an app target: documented `README.md:37`; product builds standalone (strict device build rc 0).
- [x] Both products in one binary, no duplicate symbols: throwaway SPM consumer (dynamic library depending on both products by local path) for `generic/platform=iOS Simulator` → `** BUILD SUCCEEDED **`, `duplicate symbol` count 0. CocoaPods: full `pod lib lint` builds Shared+Core+Extension together and passes.
- [x] `swift-tools-version` stays 5.9: `Package.swift:1`; dump-package `5.9.0`.

### Success criteria

- [x] Fresh project links both products and builds: SPM consumer above (not a real NSE appex; that is `example-and-release`).
- [x] CI green on `main` (38012837541) and on final head (38015311084); red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations, local and CI).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/verifier2/wt HEAD` with `-derivedDataPath` inside scratch; script cases on copies under `<scratch>/verifier2/ext`. Real tree never touched.

| # | Target (`file:line`) | Fault | Detector | Killed? |
| --- | --- | --- | --- | --- |
| R1-7 (re-run) | `scripts/check-extension-safety.sh:12-38` | `Sources/NottiShared` missing + `UIApplication.shared` planted in `Sources/NottiSDKExtension`, GNU grep (`ubuntu:24.04`) | `error: expected directory not found: …/Sources/NottiShared`, rc 1 (old script: rc 0) | ✅ Killed |
| R1-8 (re-run) | `.github/workflows/ci.yml:81-89` | Test fails once, passes on retry (CI probe run 38015155294 + exact step body replayed on real logs) | `::warning::Tests needed a retry …` + annotation on check-run 114103674259; clean log → silent | ✅ Killed |
| M-A | `Sources/NottiShared/Planted.swift` (new) | `import UIKit` + `_ = UIApplication.shared` (compiler leg only) | `ci.yml:98` extension device build → `error: 'shared' is unavailable in application extensions for iOS`, rc 65 (control without the flag rc 0). Grep leg also kills it independently. | ✅ Killed |
| M-B | `Sources/NottiSDK/NottiSDK.swift` | Added unused-variable warning | `ci.yml:97` strict device build → `error: initialization of immutable value 'unused' was never used`, rc 65 | ✅ Killed |
| M-B2 | `Sources/NottiSDKExtension/NottiSDKExtension.swift` | Same warning in the extension product | `ci.yml:98` → same error, rc 65 | ✅ Killed |
| M-C | `Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy` | `NSPrivacyTracking` false → true | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:14` failed, `** TEST FAILED **` | ✅ Killed |
| M-D1 | `Package.swift:24` | `NottiSDKExtension` deps `["NottiShared"]` → `["NottiShared", "NottiSDK"]` (re-introduces the NSE → app edge PKG-02 forbids) | SwiftLint rc 0; `check-version.sh` rc 0; `check-extension-safety.sh` rc 0; both strict device builds rc 0 (extension build now compiles target `NottiSDK`); full `xcodebuild test` `** TEST SUCCEEDED **` | ❌ Survived → Fix 1 |
| M-D2 | `NottiSDK.podspec:40` | Extension subspec adds `ss.dependency 'NottiSDK/Core'` | `pod lib lint` full rc 0 and `--subspec=Extension` rc 0 (`NottiSDK passed validation.`); `pod ipc spec` shows Extension deps `{Shared, Core}` | ❌ Survived → Fix 1 |

**Sensor depth**: lightweight+ (P1 packaging feature): 2 round-1 survivors re-run + 6 fresh mutations, focused on the guards this feature exists to provide.
**Sensor result**: 6/8 killed - FAIL ❌ (both survivors are the same gap: PKG-02 has no regression detector on either packaging path).

Why M-D matters now and will not self-heal: the spec's Problem Statement names the target split as the mistake every later feature inherits, and `core-port` moves ~3.3k lines next. The strict extension build would only catch the edge if `NottiSDK` code used app-only API *without* an availability annotation, but `core-port/design.md:98` plans `live()` as `@available(iOSApplicationExtension, unavailable)`, which compiles fine under `-application-extension`. The CocoaPods path has no extension-only compile at all.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ `ebf0a11` changes 2 files, +33/-8, only what Fix 1-3 asked. |
| Surgical changes | ✅ No unrelated edits; device-build step renamed to cite PKG-03/04. |
| No scope creep | ✅ `GCC_TREAT_WARNINGS_AS_ERRORS` is harmless today (no C sources) and keeps the step correct if C code lands. |
| Matches patterns | ✅ Script keeps `set -euo pipefail` with a scoped `set +e` around grep; comments state the why. |
| Spec-anchored outcome check | ✅ Asserted values match spec outcomes (manifests, version, keys); PKG-09b now proven by CI. |
| Per-layer Coverage Expectation met | ⚠️ Matrix row "Packaging: none (build)" leaves PKG-02 without a regression detector (Gap 1). Manifest purposes and CocoaPods resource branch still unasserted (STATE todos). |
| Every test maps to a spec requirement | ✅ Logger/keys → T4/T5 + PKG-10; manifests → PKG-10/11/12; version → PKG-14. |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ |

Minor observations on `ebf0a11` (non-blocking): the flaky step stays silent if `notti-tests.log` is missing (`2>/dev/null`), which is acceptable because the test step would already be red; `[2-9][0-9]*` would miss `Iteration 1x` but any retry first prints `Iteration 2`, so detection holds for any `-test-iterations` value.

---

## Gate Check

- **Gate command** (Full, tasks.md + CI parity): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`) + the two device builds verbatim from `ci.yml:95-98`.
- **Result**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, rc 0). NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1. SwiftLint `Found 0 violations, 0 serious in 12 files.` `version ok: 0.1.0`. `extension safety ok`. `pod lib lint` full + Extension `NottiSDK passed validation.` (rc 0 both). Device builds `NottiSDK` rc 0, `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) rc 0; fresh-DerivedData rebuild confirms real compilation (`SwiftCompile … NottiLogger.swift` etc., `BUILD SUCCEEDED`, 0 warnings).
- **Test count before feature**: 0 (greenfield). **After**: 9. **Delta**: +9. Unchanged vs round 1 (no test removed or weakened by `ebf0a11`).
- **Skipped tests**: none. **Failures**: none.
- **CI (read-only)**: 38012275374 success; 38012402254 failure (deliberate, `test` only); 38012555329 success; 38012837541 main success; 38015155294 success + flaky warning annotation (probe head `637f45e`, not on the branch); 38015311084 success on final head `288bafa`, all 4 jobs, no warning annotation.

---

## Fix Plans

### Fix 1: No regression detector for the NSE → app separation (PKG-02, PKG-06 Extension half) - Major

- **Root cause**: PKG-02 is verified only by inspection. The test matrix classifies packaging as "none (build)", and no build fails when `NottiSDKExtension` gains a dependency on `NottiSDK` (SPM) or the `Extension` subspec gains `NottiSDK/Core` (CocoaPods): M-D1 and M-D2 pass every gate step.
- **Fix task**: Add a packaging-graph check run in CI (a step in `checks` or `pod-lint`, or a new `scripts/check-package-graph.sh` called from CI) that fails when:
  1. `swift package dump-package` shows any dependency of target `NottiSDKExtension` (or `NottiShared`) other than `NottiShared`, or `NottiShared` appears in `products` (needs a Swift toolchain: run it on the macOS job, or use the Swift preinstalled on `ubuntu-latest` after confirming it reads tools 5.9);
  2. `pod ipc spec NottiSDK.podspec` shows `Extension` (or `Shared`) depending on anything except `NottiSDK/Shared`, or `default_subspecs` ≠ `Core`.
  Print the offending edge on failure.
- **Verify**: on a scratch copy, re-apply M-D1 → check exits 1 naming `NottiSDKExtension -> NottiSDK`; re-apply M-D2 → exits 1 naming `Extension -> NottiSDK/Core`; clean tree → exit 0. Show the step green in a CI run on the final head.
- **Done when**: both mutants are killed by a CI step and the clean tree passes. Update the tasks.md matrix row "Packaging" to mention the graph check.
- **Alternative if the spec owner declines**: record in STATE an explicit accepted risk ("PKG-02 guarded by review only until example-and-release builds a real NSE appex"), then a round-3 Verifier can treat M-D as an accepted, documented gap. The verifier recommends the fix: it is ~20 lines and protects the invariant the spec calls the most expensive to get wrong, right before the 3.3k-line `core-port`.

### Notes (already tracked as STATE todos, non-blocking)

- PKG-04 spec precision: the simulator compile in `xcodebuild test` is not warnings-as-errors; simulator warnings are caught by `pod lib lint` (simulator build, no `--allow-warnings`) and the same sources fail the strict device builds. Spec wording could say "CI fails on any compiler warning in either product" to make the enforcing job explicit.
- PKG-11: CocoaPods resource branch (`NottiSDKResources.swift:12-18`, `NottiSDKExtensionResources.swift:12-18`) never executed in a test (`STATE.md` todo).
- Manifest purposes (`PrivacyInfo.xcprivacy:38-78`) not asserted (`STATE.md` todo).
- PKG-06 independent test (throwaway Podfile, app + NSE) not run (`STATE.md` todo).

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-01, 03, 04, 05, 07, 08, 09, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-02 | Done | ⚠️ Holds, unguarded → Needs Fix (Fix 1) |
| PKG-06 | Done | ⚠️ Holds, Extension-dependency regression unguarded (Fix 1); Podfile test in `example-and-release` |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ❌ Not Ready (round 2 of 3)

**Spec-anchored check**: 17/17 ACs hold on the current tree with evidence; PKG-02 (and the PKG-06 Extension half) have no regression detector. Spec-precision notes: PKG-04, PKG-06, PKG-11.
**Sensor**: 8 injected, 6 killed, 2 survived (M-D1 SPM edge, M-D2 podspec edge - same gap).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; both scripts rc 0; `pod lib lint` full + Extension pass; both strict device builds rc 0.

**What works**: all three round-1 gaps are closed and proven (CI flaky annotation fires on a real retry and stays silent on a clean run; guard fails closed on GNU and BSD grep; compiler now rejects app-only API and warnings in device builds). Manifests, version drift, lint, test pipeline, and the product split itself are correct.

**Issues found**: Fix 1 (packaging-graph regression check for PKG-02 on SPM and CocoaPods).

**Next steps**: route Fix 1 to an implementer (or have the spec owner record it as an accepted risk), then run the round-3 Verifier. Lessons: the Verifier was barred from running `lessons.py` this round; the orchestrator should record one for M-D ("an architectural invariant verified only by inspection needs a CI check that fails on the forbidden edge").
