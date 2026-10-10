# Validation: package-foundation - FAIL ❌

**Date**: 2026-10-09
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..HEAD` (code surface last changed in `247befa`; `2511ac1..HEAD` touches only docs/`.claude`, verified with `git diff --stat 2511ac1..HEAD -- <surface>` = empty)
**Verifier**: independent sub-agent (author ≠ verifier)
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker). CI evidence read with `gh run view` (read-only).

---

## Task Completion

Checked against artifacts, not the ✅ marks.

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | `.specs/project/STATE.md:45` AD-006 records the spike (SPM build + `pod lib lint` pass); todo closed at `STATE.md:102`. The throwaway itself is not in the repo (by design), so the evidence is the AD text. |
| T2 | ✅ Done | `.gitignore:6,8,12,13,18` cover `*.xcuserstate`, `DerivedData/`, `.build/`, `.swiftpm/xcode/xcuserdata/`, `Pods/`; `.swiftlint.yml:4-26` thresholds; `Tests/.swiftlint.yml:2-3` disables `identifier_name`; image pinned `.swiftlint.yml:1`, `ci.yml:21`. SwiftLint run: `Found 0 violations, 0 serious in 12 files`. |
| T3 | ✅ Done | `swift package dump-package`: products `NottiSDK`, `NottiSDKExtension` (both library); platform `ios 15.0`; tools `5.9.0`; `NottiSDKExtension` deps = `[NottiShared]`; no `unsafeFlags`/plugins (`grep` exit 1). |
| T4 | ✅ Done | `NottiLogger.swift:38` default `.error`; tests `NottiLoggerTests.swift:21-59`; sink reset `NottiLoggerTests.swift:16`. |
| T5 | ✅ Done | Values match RN `52e4b55` (`ios/NottiNotificationParsing.swift` internalKeys/prefixes, `NottiNotificationServiceExtension.swift:56`, `NottiPushDelegate.swift:127-128`). Frozen by `NottiPayloadKeysTests.swift:8-19`. |
| T6 | ✅ Done | `plutil -lint` OK; manifest content matches design `design.md:122-123` and RN Core baseline. Test asserts 4 types + `CA92.1`. Purposes are not asserted (see notes). |
| T7 | ✅ Done | `C617.1` matches RN `52e4b55:ios/NotificationServiceExtension/PrivacyInfo.xcprivacy`; `plutil -lint` OK. |
| T8 | ✅ Done | `pod lib lint --platforms=ios` → `NottiSDK passed validation.` exit 0; `--subspec=Extension` → same, exit 0. `pod ipc spec`: `default_subspecs Core`, globs only under `Sources/`; `s.version` 0.1.0 = constant. |
| T9 | ✅ Done | Re-ran: current tree exit 0; podspec drift exit 1 printing both values; `GITHUB_REF=refs/tags/9.9.9` exit 1; `refs/tags/0.1.0` exit 0. |
| T10 | ⚠️ Partial | Pass + planted-file runs reproduced (exit 0 / exit 1 with `file:line`). "Runs on ubuntu" holds, but under GNU grep the script fails open when a scanned directory is missing (see Gap 2). |
| T11 | ✅ Done | Re-ran 4 builds (both schemes × device/simulator) with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`: all `BUILD SUCCEEDED`, 0 compiler warnings. Full gate 9 tests (6/2/1). |
| T12 | ⚠️ Partial | 4 jobs present, triggers OK, red/green proven on PR #1. The flaky-warning step is non-functional (see Gap 1), so the PKG-09 "flaky visible" part of the Done-when intent is not met. |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Result |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `.iOS(.v15)` and exactly two library products `NottiSDK`, `NottiSDKExtension` | `Package.swift:6` `platforms: [.iOS(.v15)]`; `Package.swift:9,11`. `swift package dump-package` → `platforms [('ios','15.0')]`, `products [('NottiSDK',…,['library']), ('NottiSDKExtension',…,['library'])]` | ✅ PASS |
| PKG-02 | NSE links `NottiSDKExtension` | No edge to `NottiSDK`; shared code in internal non-product target | `Package.swift:16,22-26` (`NottiSDKExtension` deps `["NottiShared"]`, `NottiShared` not in products). dump-package: `target NottiSDKExtension regular ['NottiShared']`. Device build of scheme `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) built targets only `NottiShared`, `NottiSDKExtension`, `NottiSDK_NottiSDKExtension` (resource bundle) - no `NottiSDK` target. | ✅ PASS |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics, no extension-unavailable API | Guard: `scripts/check-extension-safety.sh:13-19`, CI `ci.yml:42-43`; CI main run 38012837541 `extension safety ok`. Verifier extra: `xcodebuild build -scheme NottiSDKExtension -destination generic/platform=iOS APPLICATION_EXTENSION_API_ONLY=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` → exit 0 (compiles `NottiShared` + `NottiSDKExtension`). Real appex build deferred to `example-and-release` by design. | ⚠️ PASS in scope, with Gap 2 (guard fails open) and a spec-precision note (grep is a proxy for the compiler setting) |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds, zero warnings treated as errors in CI | Local: 4/4 `BUILD SUCCEEDED`, 0 warnings with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. CI: `ci.yml:87-92` device builds; simulator via `xcodebuild test` (`ci.yml:70-76`). Warnings-as-errors in CI is enforced **only by `pod lib lint`** (`ci.yml:105-109`, no `--allow-warnings`): injected warning in `NottiSDKExtension.swift` → `pod lib lint --subspec=Extension` exit 1 (`WARN | … never used`), while the same warning let `xcodebuild test` build and run. | ✅ PASS (via pod-lint) + spec-precision note |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local: full exit 0, `--subspec=Extension` exit 0 (`NottiSDK passed validation.`). CI main run 38012837541 `pod-lint=success`. | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default = Core; Extension gets only Extension + Shared sources | `NottiSDK.podspec:24` `s.default_subspecs = 'Core'`; `:39-43` Extension depends only on `NottiSDK/Shared`, globs `Sources/NottiSDKExtension/**`. `pod ipc spec` confirms. `pod lib lint --subspec=Extension` builds only Shared+Extension and passes. The spec's "throwaway Podfile app + NSE installs and builds" independent test was not run (no evidence in repo). | ✅ PASS (structural + lint), note |
| PKG-07 | Podspec source globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,35,41,42` - all globs under `Sources/`; no `test_spec`. `pod ipc spec` source_files: `Sources/NottiShared/**/*.swift`, `Sources/NottiSDK/**/*.swift`, `Sources/NottiSDKExtension/**/*.swift`. | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner builds both products for Simulator, runs all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7` (`pull_request`, push `main`); `ci.yml:46,70-76` test on `macos-26`; `:94-109` pod-lint; `:24-31` SwiftLint. Run 38012275374 (PR, 64e9d6b): lint/checks/test/pod-lint = success. Main run 38012837541 (2511ac1): all 4 success, `Executed 6/2/1 tests`. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (PR, 2756451): `test=failure`, `Executed 8 tests, with 2 failures`, `** TEST FAILED **`, `Process completed with exit code 65`. `set -o pipefail` at `ci.yml:69`. | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log, parity with RN flaky warning | `ci.yml:73-74` enables `-retry-tests-on-failure -test-iterations 2`; warning step `ci.yml:78-85` greps `Restarting tests after unexpected exit\|^Testing failed:\|Repeating test`. None of these strings is emitted by Xcode 26/27: in red run 38012402254 a retry happened (`started (Iteration 2 of 2)`) and the flag step printed nothing (pattern hits in that log = the step's own script text only). Local probe (test failing once then passing, same xcodebuild flags): `(Iteration 2 of 2) … passed`, CI grep → 0 matches → **no warning**. A flaky test goes green silently. | ❌ GAP (Gap 1) |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | `NottiSDKVersionTests.swift:7-10`, `NottiLoggerTests.swift:21-59`, `NottiPayloadKeysTests.swift:8-19` (shared); `Tests/NottiSDKTests/PrivacyManifestTests.swift:17-19` `XCTAssertNotNil(…url(forResource: "PrivacyInfo"…))` (app); `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:6-9,19` (NSE). Local: 6/2/1 executed, 0 failures. | ✅ PASS |
| PKG-11 | `NottiSDK` consumed via SPM or CocoaPods | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone (not tracking), + CoarseLocation + ProductInteraction | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `XCTAssertEqual(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])`; `:35-40` set of 4 types; `:43` `Tracking == false` per entry. Manifest `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy:5-79`. SPM path tested; CocoaPods path only proven by `resource_bundles` (`NottiSDK.podspec:35`) + lint - `NottiSDKResources.swift:12-18` (non-SPM branch) has no test. | ✅ PASS (SPM), note on CocoaPods path |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false. Same reason code as RN `52e4b55`. | ✅ PASS |
| PKG-13 | Later feature adds required-reason API / data type | Same feature updates manifest | Process rule. Recorded at `AGENTS.md` "Privacy and logging" (PKG-13 bullet). This feature adds no required-reason API beyond the manifests themselves. Verified per later feature. | ✅ N/A-in-scope (rule documented) |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; used by `Sources/NottiSDK/NottiSDK.swift:8`, `Sources/NottiSDKExtension/NottiSDKExtension.swift:8`. `grep -rn '0\.1\.0' Sources` → only that line. Semver test `NottiSDKVersionTests.swift:7-10`. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec `version` ≠ constant | `scripts/check-version.sh:13-24`, CI `ci.yml:39-40`. Injected `s.version='0.1.1'` → `error: version drift: NottiSDKVersion.current=0.1.0, NottiSDK.podspec s.version=0.1.1`, exit 1. Tag drift `GITHUB_REF=refs/tags/9.9.9` → exit 1. Main run `version ok: 0.1.0`. | ✅ PASS |
| PKG-16 | Repo cloned | `.gitignore` (Xcode/SPM/CocoaPods, `.build/`, `DerivedData/`, `Pods/`), `LICENSE`, `README.md` stub, `CHANGELOG.md` `[Unreleased]`, `.swiftlint.yml` | `.gitignore:8,12,18`; `LICENSE:1-3` (MIT, Zeep Tecnologia); `README.md:5` status, `:14-35` SPM + CocoaPods snippet; `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` → `Done linting! Found 0 violations, 0 serious in 12 files.` exit 0; CI main run same line. | ✅ PASS |

**Status**: ❌ Gaps present (PKG-09b). Spec-precision notes on PKG-03, PKG-04, PKG-06, PKG-11.

### Edge cases

- [x] Only `NottiSDKExtension` in an app target builds; documented, not enforced: `README.md:37`. Product builds standalone (scheme `NottiSDKExtension` device + simulator `BUILD SUCCEEDED`).
- [x] Both products in one binary, no duplicate symbols: verifier built a throwaway SPM consumer (dynamic framework depending on both `NottiSDK` and `NottiSDKExtension` products by local path) for iOS Simulator → `** BUILD SUCCEEDED **`, no `duplicate symbol`. CocoaPods side: full `pod lib lint` builds Shared+Core+Extension into one pod and passes.
- [x] `swift-tools-version` stays 5.9: `Package.swift:1` `// swift-tools-version:5.9`; dump-package `toolsVersion 5.9.0`.

### Success criteria

- [x] Fresh project links both products and builds: reproduced with the SPM consumer above (not a real NSE target; that part is in `example-and-release`).
- [x] CI green on `main` (38012837541) and red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/wt HEAD` with `-derivedDataPath <scratch>/dd`. Real tree never touched.

| # | Target (`file:line`) | Fault | Detector | Killed? |
| --- | --- | --- | --- | --- |
| 1 | `Sources/NottiShared/NottiLogger.swift:63` | `messageLevel <= currentLevel` → `<` (level filter off-by-one) | `NottiLoggerTests.swift:28` and `:36-37` failed (`test_defaultLevelIsErrorOnly`, `test_messageAtOrAboveTheLevelReachesTheSink`) | ✅ Killed |
| 2 | `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy:16` | UserDefaults reason `CA92.1` → `1C8F.1` | `Tests/NottiSDKTests/PrivacyManifestTests.swift:31` failed | ✅ Killed |
| 3 | `Sources/NottiShared/NottiPayloadKeys.swift:13` | `"delivery_id"` → `"deliveryId"` | `NottiPayloadKeysTests.swift:10` failed | ✅ Killed |
| 4 | `NottiSDK.podspec:4` | `s.version` → `0.1.1` (drift) | `scripts/check-version.sh` exit 1, both values printed | ✅ Killed |
| 5 | `Sources/NottiShared/Planted.swift` (new) | `_ = UIApplication.shared` | `scripts/check-extension-safety.sh` exit 1 with `Planted.swift:2` | ✅ Killed |
| 6 | `Sources/NottiSDKExtension/NottiSDKExtension.swift` | Added unused-variable compiler warning | `pod lib lint --subspec=Extension` exit 1 (`WARN`); note `xcodebuild test` did not fail | ✅ Killed (by pod-lint job) |
| 7 | `scripts/check-extension-safety.sh:12,15` | Plant `UIApplication.shared` in `Sources/NottiSDKExtension` + rename `Sources/NottiShared` (scanned dir missing), run in `ubuntu:24.04` (GNU grep 3.11, same as CI `checks` job) | Script printed `grep: /w/Sources/NottiShared: No such file or directory` then `extension safety ok`, exit 0 (grep rc 2 is treated as "no match"). On macOS BSD grep the same input exits 1. | ❌ Survived → Fix 2 |
| 8 | `.github/workflows/ci.yml:78-85` | Test that fails on first attempt and passes on retry, run with CI flags `-retry-tests-on-failure -test-iterations 2` | Log shows `failed` then `started (Iteration 2 of 2)` → `passed`; CI grep patterns: 0 matches → no `::warning::`. Corroborated by CI run 38012402254. | ❌ Survived → Fix 1 |

**Sensor depth**: lightweight (P1 packaging feature, not P0 critical path), extended to scripts/CI because they are the main guards of this feature.
**Sensor result**: 6/8 killed - FAIL ❌

Note: the local probe run (#8) hung in `xcodebuild` after `All tests passed` (Xcode 27 + piped output); it was killed after ~9 min. The decision only depends on the already-written test lines.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ Only the skeleton, logger, keys, version, manifests, resource accessors, two scripts, one workflow. |
| Surgical changes | ✅ Each commit maps to one task (`git log 92ccd8c..HEAD`). |
| No scope creep | ✅ CI also triggers on `tags: ['*']` (`ci.yml:7`), beyond design's "PR + main"; justified by the tag check in `check-version.sh:26-33`. |
| Matches patterns | ✅ `package` access in `NottiShared` (AD-006); `#if canImport(NottiShared)`; resource accessors instead of `Bundle.module` (per `AGENTS.md`). |
| Spec-anchored outcome check | ⚠️ All asserted values match the spec; PKG-09b mechanism does not work. |
| Per-layer Coverage Expectation met | ⚠️ Matrix row "Resources: every declared type/reason asserted": types + reasons asserted; purposes (`PrivacyInfo.xcprivacy:38-78`) not asserted. CocoaPods branch of `NottiSDKResources`/`NottiSDKExtensionResources` (`:12-18`) is compiled by lint but never executed in a test. |
| Every test maps to a spec requirement | ✅ Logger/keys tests map to T4/T5 Done-when and PKG-10; manifest tests to PKG-10/11/12; version to PKG-14. |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ Default log level `.error`, no PII in logs, conventional commits, SwiftLint clean, counts match. |

---

## Gate Check

- **Gate command** (Full, tasks.md): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`)
- **Gate result**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, exit 0). SwiftLint 0 violations. `version ok: 0.1.0`. `extension safety ok`. `pod lib lint` full + Extension: `NottiSDK passed validation.` (exit 0 both).
- **Per target**: NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1 (matches expected).
- **Test count before feature**: 0 (greenfield)
- **Test count after feature**: 9
- **Delta**: +9
- **Skipped tests**: none
- **Failures**: none
- **Extra builds (verifier)**: `NottiSDK` / `NottiSDKExtension` × `generic/platform=iOS` / `generic/platform=iOS Simulator` with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`: 4/4 succeeded, 0 warnings.
- **CI (read-only)**: 38012275374 success (64e9d6b); 38012402254 failure, `test` job only (2756451, deliberate `DeliberatelyFailingTests`); 38012555329 success (64e9d6b again, after dropping the failing commit); 38012837541 push `main` success (2511ac1).

---

## Fix Plans

### Fix 1: Flaky-test warning never fires (PKG-09b) - Major

- **Root cause**: `ci.yml:82,84` grep for `Restarting tests after unexpected exit`, `^Testing failed:`, `Repeating test`. Xcode 26/27 marks a retry as `Test Case '…' started (Iteration 2 of 2).` and prints `Failing tests:` on failure. Nothing matches, so a test that passes on retry is silently green, and even a real failure produces no annotation.
- **Fix task**: In `.github/workflows/ci.yml` "Flag retried (flaky) tests", match the retry marker, e.g. `grep -E "started \(Iteration [2-9][0-9]* of"` (or parse the `.xcresult` with `xcrun xcresulttool`) and emit `::warning::` listing the affected test cases. Keep the step `if: always()`.
- **Verify**: on a throwaway PR branch (not merged), add a test that fails on first attempt and passes on retry (static counter): `test` job is green AND the run shows the `::warning::` annotation naming that test. Drop the commit afterwards.
- **Done when**: the annotation appears for a retried-then-passed test, and not on a clean run.

### Fix 2: `check-extension-safety.sh` fails open on GNU grep when a scanned directory is missing - Minor

- **Root cause**: `scripts/check-extension-safety.sh:15` treats any non-zero grep exit as "no match". GNU grep (CI `checks` runs on `ubuntu-latest`) returns 2 when one path is missing even if the other path has matches, so a rename of `Sources/NottiShared` or `Sources/NottiSDKExtension` disables the guard silently.
- **Fix task**: Before grepping, fail if any entry in `dirs` is not a directory (`[[ -d "$d" ]] || { echo "error: missing $d" >&2; exit 1; }`), and distinguish grep exit 1 (clean) from 2 (error → exit 1).
- **Verify**: in a temp copy, run in `ubuntu:24.04` with `Sources/NottiShared` renamed → exit 1; with planted `UIApplication.shared` → exit 1; clean tree → exit 0. Same on macOS.
- **Done when**: all three outcomes hold on both GNU and BSD grep.

### Fix 3 (optional hardening, not blocking): compile-level extension check - Minor

- **Root cause**: PKG-03 is guarded by a grep proxy; SPM can't set the flag per target, but `xcodebuild` can for a whole build.
- **Fix task**: Add `APPLICATION_EXTENSION_API_ONLY=YES` to the CI device build of the `NottiSDKExtension` scheme (`ci.yml:91`). Verifier confirmed the current tree builds with it (exit 0).
- **Done when**: CI device build of `NottiSDKExtension` runs with the setting and passes.

### Notes (no fix task required unless the spec owner wants them)

- PKG-04: "zero warnings treated as errors in CI" is enforced only through `pod lib lint` (proven by sensor #6). Warnings in test targets are not covered. If the intent is that the `xcodebuild` steps also fail, add `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` to them. Spec wording should say which job enforces it.
- PKG-11: the CocoaPods resource path (`NottiSDK_Privacy` bundle via `NottiSDKResources.swift:13-18`) is never executed in a test. Real-app proof belongs to `example-and-release` (spec Independent Test: archive + privacy report).
- PKG-06: the spec's Independent Test (throwaway Podfile, app + NSE target) was not run; evidence is `pod ipc spec` + `pod lib lint --subspec=Extension`.
- Manifest purposes (`PrivacyInfo.xcprivacy:38-78`) match `design.md:122-123` but are not asserted; a test assertion would freeze them as AD-005 intends.

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-01, 02, 05, 06, 07, 08, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-03 | Done | ⚠️ Verified in scope (Fix 2; real appex build in `example-and-release`) |
| PKG-04 | Done | ✅ Verified (via pod-lint; note) |
| PKG-09 | Done | ❌ Needs Fix (Fix 1) |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ❌ Not Ready

**Spec-anchored check**: 16/17 ACs matched spec outcome (PKG-09 flaky-visibility half fails); 4 spec-precision notes (PKG-03, 04, 06, 11).
**Sensor**: 6/8 killed (2 survived: flaky warning, extension-safety fail-open).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; both scripts exit 0; `pod lib lint` full + Extension pass.

**What works**: SPM manifest and product split (no NSE → app edge), CocoaPods subspecs and lint, privacy manifests with discriminating tests, single version constant + drift check, CI red/green on real failures, repo hygiene, zero lint/compiler warnings.

**Issues found**: Fix 1 (flaky warning grep matches nothing on Xcode 26/27), Fix 2 (extension-safety guard fails open under GNU grep when a directory is missing).

**Next steps**: route Fix 1 and Fix 2 to an implementer, then re-run this Verifier (iteration 1 of max 3). Fix 3 is optional hardening.
