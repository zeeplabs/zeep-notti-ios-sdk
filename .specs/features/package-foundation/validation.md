# Validation: package-foundation - FAIL ❌

**Date**: 2026-10-09
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..b9a8785` (code surface: `Package.swift`, `NottiSDK.podspec`, `Sources/`, `Tests/`, `scripts/`, `.github/`, hygiene files; 26 files, +904. Since round 2 (`288bafa`) the code surface changed only in `4544b13`: `scripts/check-package-graph.sh` (new, 69 lines) and `.github/workflows/ci.yml:111-113` (new step). `Sources/`, `Tests/`, `Package.swift`, the podspec and the other two scripts are byte-identical to round 2.)
**Verifier**: independent sub-agent (author ≠ verifier), round 3 (final of 3)
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker), GNU grep 3.11 (`ubuntu:24.04`). CI evidence read-only (`gh run view`, `gh api …/check-runs/<id>/annotations`). No pushes, re-runs or edits on GitHub.

---

## Earlier gaps → status (rounds 1-2)

| Round | Gap | Status | Evidence (re-derived this round) |
| --- | --- | --- | --- |
| 1 | Flaky-test warning never fired on Xcode 26+ (PKG-09b) | ✅ Closed | `ci.yml:85` pattern `started \(Iteration [2-9][0-9]* of\|Restarting tests after unexpected exit`. Replayed the exact pattern (read from `ci.yml`) on the probe log of CI 38015155294 → match `1046:Test Case '-[NottiSharedTests.FlakyProbeTests test_failsOnceThenPasses]' started (Iteration 2 of 2).`; on the clean CI log of 38016135612 (9× `Iteration 1 of 2`) → silent. Same result on BSD grep and GNU grep 3.11. Old pattern (`247befa`) on the probe log → 0 matches (survivor reproduces against old code). CI annotation on check-run 114103674259: `warning \| Tests needed a retry - a test is flaky, not just green.` Head run 38016135612 test job: only the runner-capacity notice, no warning. `git diff ebf0a11..HEAD -- .github` touches only the new graph step, so the probe evidence still applies. |
| 1 | `check-extension-safety.sh` passed silently on GNU grep with a missing dir (PKG-03) | ✅ Closed | `scripts/check-extension-safety.sh:17-22,25-38`. `ubuntu:24.04` on copies: clean → `extension safety ok` rc 0; `NottiShared` renamed + `UIApplication.shared` planted in `NottiSDKExtension` → `error: expected directory not found: …/NottiShared` rc 1; `NottiSDKExtension` removed → rc 1; planted in `NottiShared` → rc 1 citing `Planted.swift:1:import UIKit`. Control: `247befa` script on the renamed+planted case → `grep: …No such file or directory` then `extension safety ok` rc 0. |
| 2 | No CI check caught the forbidden NSE → app edge (PKG-02; PKG-06 Extension half): M-D1 SPM, M-D2 podspec | ✅ Closed for dependency edges | `scripts/check-package-graph.sh:22-64`, run by `ci.yml:112-113` in the `pod-lint` job. Clean → `package graph ok` rc 0 (local and CI 38016135612 pod-lint log `2026-10-10T02:13:15Z package graph ok`). M-D1 → `error: SPM target NottiSDKExtension must depend on ['byName:NottiShared'], got ['byName:NottiSDK', 'byName:NottiShared']` rc 1; M-D2 → `error: podspec subspec Extension must depend on ['NottiSDK/Shared'], got ['NottiSDK/Core', 'NottiSDK/Shared']` rc 1. Variants also killed (sensor table). **Not closed for the source-glob route to the same invariant**: see Gap 1 (new this round). |
| 2 | tasks.md "Packaging" matrix row to mention the graph check (Fix 1 Done-when) | ⚠️ Not done | `tasks.md:25` still reads `none (build)` / `build gate + pod lib lint`; `tasks.md:38` Full gate omits `check-package-graph.sh`. `TESTING.md` and `AGENTS.md` were updated in `4544b13`. Doc drift only, non-blocking. |

---

## Task Completion

Checked against artifacts, not the ✅ marks.

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | AD-006 in `.specs/project/STATE.md`; `NottiSDK.podspec:22` `-package-name NottiSDK`; lint passes with `package` access across subspecs. |
| T2 | ✅ Done | `.gitignore:5,8,12,13,18`; `.swiftlint.yml`; `Tests/.swiftlint.yml`. `lint --strict` → `Found 0 violations, 0 serious in 12 files.` |
| T3 | ✅ Done | `Package.swift:1,6,9,11,16-26`; graph check reads it via `swift package dump-package` → ok. |
| T4 | ✅ Done | `Tests/NottiSharedTests/NottiLoggerTests.swift` (4 tests) passed. |
| T5 | ✅ Done | `Tests/NottiSharedTests/NottiPayloadKeysTests.swift` passed. |
| T6 | ✅ Done | `Tests/NottiSDKTests/PrivacyManifestTests.swift:16-45` (2 tests) passed. |
| T7 | ✅ Done | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:5-20` passed. |
| T8 | ✅ Done | `pod lib lint` full rc 0 and `--subspec=Extension` rc 0 (`NottiSDK passed validation.`). |
| T9 | ✅ Done | `scripts/check-version.sh` → `version ok: 0.1.0` rc 0; unchanged since round 1 proved drift. |
| T10 | ✅ Done | See round-1 gap row (GNU + BSD). |
| T11 | ✅ Done | Both strict device builds verbatim from `ci.yml:96-98` rc 0; full suite 6/2/1. |
| T12 | ✅ Done | `ci.yml` 4 jobs; run 38016135612 on `b9a8785` all success. |
| Round-2 Fix 1 (`4544b13`) | ⚠️ Partial | Dependency/product/default-subspec drift guarded; podspec `source_files` not guarded (Gap 1); tasks.md matrix not updated. |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Result |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `.iOS(.v15)`, exactly two library products `NottiSDK`, `NottiSDKExtension` | `Package.swift:6,9,11`. Now guarded: `check-package-graph.sh:25-27` `products != {"NottiSDK": ["NottiSDK"], "NottiSDKExtension": ["NottiSDKExtension"]}` → error; sensor M-E2 (third product) and M-E2b (`NottiSDK` added to the extension product) killed. Platform not asserted by the script, but `Package.swift:6` + the device/simulator builds depend on it. | ✅ PASS |
| PKG-02 | NSE links `NottiSDKExtension` | No `NottiSDK` target in its build graph (direct or transitive); shared code in an internal non-product target | `Package.swift:16,22-26`; `check-package-graph.sh:37-49` requires `NottiShared` deps `[]` and `NottiSDKExtension` deps exactly `[byName:NottiShared]` (transitively closed). Killed: M-D1, M-D1t (`.target(...)`), M-D1c (conditional), M-D1p (`.product(...)`, invalid manifest → rc 1), M-E1r (external `.product` on `NottiShared`), M-E1b (`NottiShared → Bridge → NottiSDK`). SPM source-overlap route is rejected by SwiftPM itself (`xcodebuild` rc 74, `target 'NottiSDKExtension' has overlapping sources`). | ✅ PASS (SPM path guarded) |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics | `ci.yml:98` strict extension device build with `APPLICATION_EXTENSION_API_ONLY=YES` rc 0 locally; `scripts/check-extension-safety.sh` rc 0 locally and CI (`extension safety ok`); GNU-grep cases above. Compiler-leg kill (M-A, round 2) still valid: `ci.yml:91-98` unchanged since. | ✅ PASS |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds; zero warnings treated as errors in CI | Device: `ci.yml:96-98` re-run verbatim → `sdk rc=0`, `ext rc=0`, no compiler warnings in output. Simulator: `xcodebuild test` (not strict) + `pod lib lint` (simulator, no `--allow-warnings`). | ✅ PASS + spec-precision note (unchanged) |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local full rc 0, `--subspec=Extension` rc 0. CI 38016135612 pod-lint `NottiSDK passed validation.` ×2. | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default Core; Extension gets only Extension + Shared sources, **no Core sources** | Holds today: `NottiSDK.podspec:24,27-29,39-43`; control `pod lib lint --subspec=Extension --verbose` compiles only `NottiLogger`, `NottiPayloadKeys`, `NottiSDKExtension`, `NottiSDKExtensionResources`, `NottiSDKVersion` (0 `Sources/NottiSDK/` files). Default-subspec and dependency drift now guarded (M-E3, M-D2, M-E4 killed). **Unguarded**: a podspec glob that pulls `Sources/NottiSDK/**` into `Extension` or `Shared` passes the graph check, both lints and all scripts while compiling `Sources/NottiSDK/NottiSDK.swift` and `NottiSDKResources.swift` into the Extension-only pod (M-F1, M-F2, M-F4 survived). Real Podfile app+NSE test still not run (STATE todo). | ⚠️ Holds today, ❌ "no Core sources" clause unguarded (Gap 1) |
| PKG-07 | Podspec globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,41` all under `Sources/`. Sensor M-07 (Shared glob widened to `Tests/NottiSharedTests`) → `pod lib lint` rc 1 (`ERROR … xcodebuild: Returned an unsuccessful exit code`). | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner builds both products for Simulator, runs all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7,24-31,45-76,100-119`. Run 38016135612 (`pull_request`, head `b9a8785`): lint/checks/test/pod-lint all success; `Executed 6 tests` / `2 tests` / `1 test`, `** TEST SUCCEEDED **`; `Found 0 violations`. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (`2756451`): `test=failure`, log `NottiSDKVersionTests.swift:16: error: -[NottiSharedTests.DeliberatelyFailin…`, `** TEST FAILED **`. `set -o pipefail` `ci.yml:69,95`; graph step runs under `bash -e` and the script exits 1 on error. | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log | `ci.yml:73-74,81-89`; probe run 38015155294 warning annotation + log line; clean head run silent (see round-1 row). | ✅ PASS |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | Local gate: `NottiSharedTests.xctest` passed (Executed 6), `NottiSDKTests.xctest` passed (2), `NottiSDKExtensionTests.xctest` passed (1). | ✅ PASS |
| PKG-11 | `NottiSDK` consumed | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone not tracking, + CoarseLocation + ProductInteraction | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `… as? [String], ["CA92.1"]`; `:35-40` set of the 4 types; `:43` `NSPrivacyCollectedDataTypeTracking == false` per entry. SPM path only (CocoaPods resource branch untested, STATE todo). | ✅ PASS (SPM), note |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false. | ✅ PASS |
| PKG-13 | Later feature adds API/data type | That feature updates manifest | Process rule, `AGENTS.md:68`. | ✅ N/A in scope (rule documented) |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; `Tests/NottiSharedTests/NottiSDKVersionTests.swift:7-10` semver assertion. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec version ≠ constant | `scripts/check-version.sh:13-24`, `ci.yml:39-40`; local + CI `version ok: 0.1.0`. Script unchanged since round 1 proved drift → rc 1. | ✅ PASS |
| PKG-16 | Repo cloned | Hygiene files present | `.gitignore:5,8,12,18`; `LICENSE:1` `MIT License`; `README.md:5` status, `:23-37` install + misconfiguration note; `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` rc 0 `Found 0 violations, 0 serious in 12 files.`; CI 38016135612 same line. | ✅ PASS |

**Status**: ❌ Gap present: PKG-06 "no Core sources" clause has no regression detector on the CocoaPods path (Gap 1). Spec-precision notes unchanged: PKG-04 (simulator compile), PKG-06 (Podfile test), PKG-11 (CocoaPods resource branch).

### Edge cases

- [x] Only `NottiSDKExtension` in an app target: documented `README.md:37`; product builds standalone (strict device build rc 0).
- [x] Both products in one binary, no duplicate symbols: round-2 throwaway SPM consumer (sources unchanged since); full `pod lib lint` builds Shared+Core+Extension together and passes.
- [x] `swift-tools-version` stays 5.9: `Package.swift:1`.

### Success criteria

- [x] Fresh project links both products and builds (round-2 SPM consumer; real NSE appex is `example-and-release`).
- [x] CI green on `main` (38012837541, `2511ac1`) and on final head (38016135612, `b9a8785`); red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations, local and CI).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/verifier3/wt HEAD` with `-derivedDataPath` inside scratch; extension-safety cases on copies under `<scratch>/verifier3/ext` in `ubuntu:24.04`; flaky-pattern replay on CI logs saved to scratch. The real tree was never touched (porcelain empty before and after; worktree removed + pruned).

| # | Target (`file:line`) | Fault | Detector → output | Killed? |
| --- | --- | --- | --- | --- |
| R1-a (re-run) | `ci.yml:85` | Real retry log line `started (Iteration 2 of 2)` (CI 38015155294) | Pattern matches on BSD + GNU grep; clean CI log silent | ✅ Killed |
| R1-b (re-run) | `scripts/check-extension-safety.sh:17-22` | `NottiShared` missing + `UIApplication.shared` planted in `NottiSDKExtension`, GNU grep | `error: expected directory not found`, rc 1 (old script rc 0) | ✅ Killed |
| M-D1 (re-run) | `Package.swift:24` | `NottiSDKExtension` deps `+ "NottiSDK"` | graph check rc 1, names `byName:NottiSDK` | ✅ Killed |
| M-D2 (re-run) | `NottiSDK.podspec:40` | Extension `+ ss.dependency 'NottiSDK/Core'` | graph check rc 1, names `NottiSDK/Core` | ✅ Killed |
| M-D1t | `Package.swift:24` | Same edge via `.target(name: "NottiSDK")` | rc 1, `target:NottiSDK` | ✅ Killed |
| M-D1c | `Package.swift:24` | Same edge via `.target(name: "NottiSDK", condition: .when(platforms: [.iOS]))` | rc 1, `target:NottiSDK` | ✅ Killed |
| M-D1p | `Package.swift:24` | Same edge via `.product(name: "NottiSDK", package: "NottiSDK")` | `dump-package` rejects the manifest, script rc 1 (fails closed) | ✅ Killed |
| M-E1r | `Package.swift:16` (+ package `dependencies:`) | `NottiShared` gains external `.product(name: "Foo", package: "foo")` | rc 1, `SPM target NottiShared must depend on nothing, got ['product:Foo']` | ✅ Killed |
| M-E1b | `Package.swift:16` | Transitive edge `NottiShared → Bridge → NottiSDK` | rc 1, `got ['byName:Bridge']` | ✅ Killed |
| M-E2 | `Package.swift:11` | Third product `NottiShared` | rc 1, products mismatch | ✅ Killed |
| M-E2b | `Package.swift:11` | Extension product also vends target `NottiSDK` | rc 1, products mismatch | ✅ Killed |
| M-E3 | `NottiSDK.podspec:24` | `default_subspecs = ['Core', 'Extension']` | rc 1, `default_subspecs must be Core` | ✅ Killed |
| M-E4 | `NottiSDK.podspec:28` | `Shared` gains `ss.dependency 'NottiSDK/Core'` | rc 1, `subspec Shared must depend on nothing` | ✅ Killed |
| M-07 | `NottiSDK.podspec:28` | Shared glob includes `Tests/NottiSharedTests` (PKG-07) | `pod lib lint` rc 1 | ✅ Killed |
| M-SPM-src | `Package.swift:22-26` | `NottiSDKExtension` `path: "Sources"`, `sources: [..., "NottiSDK/NottiSDK.swift"]` | SwiftPM: `target 'NottiSDKExtension' has overlapping sources`, `xcodebuild` rc 74 (graph check itself rc 0) | ✅ Killed |
| M-F3 | `NottiSDK.podspec:24` | Root-level `s.source_files = 'Sources/NottiSDK/**/*.swift'` | Equivalent: Extension lint compiles 0 `Sources/NottiSDK/` files (root files not pulled into the subspec) | ➖ Equivalent (excluded) |
| **M-F1** | `NottiSDK.podspec:41` | Extension `source_files` adds `'Sources/NottiSDK/**/*.swift'` | graph check `package graph ok` rc 0; `check-version` / `check-extension-safety` rc 0; `pod lib lint` full rc 0, `--subspec=Extension` rc 0 while compiling `Sources/NottiSDK/NottiSDK.swift` and `NottiSDKResources.swift` (control: 0) | ❌ Survived |
| **M-F2** | `NottiSDK.podspec:28` | Shared glob `'Sources/{NottiShared,NottiSDK}/**/*.swift'` | graph rc 0; `--subspec=Extension` lint rc 0 compiling the same 2 Core files | ❌ Survived |
| **M-F4** | `NottiSDK.podspec:28` | Shared glob simplified to `'Sources/**/*.swift'` (the RN `ios/**/*.swift` mistake PKG-07 cites) | graph rc 0; full lint rc 0; Extension lint rc 0 compiling the same 2 Core files | ❌ Survived |

M-F1/M-F2/M-F4 need no Swift change and leave SPM untouched, so the SPM test suite, SwiftLint and the device builds cannot see them either (they read only `Package.swift`).

**Sensor depth**: P1 packaging, focused on the round-2 fix: 4 earlier survivors re-run + 14 fresh mutations (1 equivalent excluded).
**Sensor result**: 17 non-equivalent injected, 14 killed, 3 survived (M-F1, M-F2, M-F4 - one root cause) - FAIL ❌.

Why it matters: PKG-06 explicitly says the NSE pod gets "no Core sources", and the Problem Statement names the app/extension split as the mistake every later feature (and the M2 RN migration, which consumes the podspec) inherits. With `core-port` landing ~3.3k lines in `Sources/NottiSDK`, a glob leak would ship app code (e.g. `UIApplication` paths annotated `@available(iOSApplicationExtension, unavailable)`, which compile under `-application-extension`) inside every RN app's NSE, with CI green. `check-package-graph.sh` header (`:5-6`) claims to guard the CocoaPods split but checks only `dependencies`.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ `4544b13` adds one 69-line script + a 3-line CI step. |
| Surgical changes | ✅ No source/test changes; docs (`TESTING.md`, `AGENTS.md`) updated alongside. |
| No scope creep | ✅ Products/default-subspec checks are within PKG-01/06. |
| Matches patterns | ✅ `set -euo pipefail`, repo-root arg like the other scripts, errors to stderr naming the offending edge; fails closed when `swift`/`pod` fail. |
| Spec-anchored outcome check | ⚠️ Graph check targets PKG-02 precisely on SPM; on CocoaPods it covers dependencies but not the "no Core sources" outcome of PKG-06. |
| Per-layer Coverage Expectation met | ⚠️ `tasks.md:25` matrix row and `tasks.md:38` Full gate not updated for the graph check. |
| Every test maps to a spec requirement | ✅ Unchanged since round 2 (logger/keys → T4/T5 + PKG-10; manifests → PKG-10/11/12; version → PKG-14). |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ |

Minor observations (non-blocking): the script treats `.target(name: "NottiShared")` as a violation (only `byName:` accepted) - a false positive, fails safe. Root-level `s.dependency` in the podspec (top-level `dependencies` in `pod ipc spec`) is not inspected; it would add an external dep to every subspec, not an NSE→app edge, so not an AC violation today. The script runs only on the macOS `pod-lint` job (by design; needs `swift` + `pod`).

---

## Gate Check

- **Gate command** (Full, tasks.md + TESTING.md + CI parity): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh` + `scripts/check-extension-safety.sh` + `scripts/check-package-graph.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`) + the two device builds verbatim from `ci.yml:95-98`.
- **Result**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, rc 0): NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1. SwiftLint `Found 0 violations, 0 serious in 12 files.` rc 0. `version ok: 0.1.0`, `extension safety ok`, `package graph ok` (all rc 0). `pod lib lint` full + Extension `NottiSDK passed validation.` rc 0. Device builds `NottiSDK` rc 0, `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) rc 0. Only non-compiler warnings in the test log (3× `appintentsmetadataprocessor … Metadata extraction skipped`).
- **Test count before feature**: 0 (greenfield). **After**: 9. **Delta**: +9. Unchanged vs rounds 1-2 (`Tests/` untouched since).
- **Skipped tests**: none. **Failures**: none.
- **CI (read-only)**: 38016135612 (`pull_request`, `b9a8785`) success, all 4 jobs, `package graph ok` in pod-lint, no warning annotation; 38015311084 (`288bafa`) success; 38015155294 (`637f45e`, flaky probe) success + warning annotation; 38012402254 (`2756451`) failure on `test` only (deliberate); 38012837541 (`main`, `2511ac1`) success.

---

## Fix Plans

### Fix 1: PKG-06 "no Core sources" is not guarded on the CocoaPods path - Major

- **Root cause**: `scripts/check-package-graph.sh:53-62` compares only each subspec's `dependencies`. CocoaPods compiles whatever `source_files` (and `resource_bundles`) a subspec globs, so Core sources can reach `NottiSDK/Extension` through `Extension` or `Shared` globs without any dependency edge. `pod lib lint` compiles them happily.
- **Fix task**: in the CocoaPods half of `check-package-graph.sh`, also assert the file patterns exactly (from `pod ipc spec`):
  - `Shared.source_files == "Sources/NottiShared/**/*.swift"`, `Core.source_files == "Sources/NottiSDK/**/*.swift"`, `Extension.source_files == "Sources/NottiSDKExtension/**/*.swift"` (normalize string vs list);
  - `Extension.resource_bundles` only references `Sources/NottiSDKExtension/`, `Shared` has none;
  - root spec has no `source_files` / `resources` / `resource_bundles` (cheap future-proofing; M-F3 is equivalent today).
  Print the offending subspec and pattern. Update `tasks.md:25` (Packaging row) and `tasks.md:38` (Full gate) to include the graph check.
- **Verify**: on a scratch copy, M-F1, M-F2 and M-F4 each make the script exit 1 naming the subspec; clean tree exits 0; M-D1/M-D2 still killed; step green in a CI run on the new head.
- **Alternative if the spec owner declines**: record an accepted risk in STATE ("PKG-06 source isolation guarded by review until `example-and-release` builds a real NSE via CocoaPods"). This is round 3 of 3, so per the process this goes to the user for the decision rather than another automatic fix→verify loop.

### Notes (already tracked as STATE todos, non-blocking)

- PKG-04 spec precision: the simulator compile in `xcodebuild test` is not warnings-as-errors; `pod lib lint` (simulator, no `--allow-warnings`) and the strict device builds are the guards.
- PKG-11: CocoaPods resource branch (`NottiSDKResources.swift`, `NottiSDKExtensionResources.swift`, non-`SWIFT_PACKAGE` path) never executed in a test.
- Manifest purposes (`PrivacyInfo.xcprivacy`) not asserted.
- PKG-06 independent test (throwaway Podfile, app + NSE) not run. Running it would not have killed M-F1/M-F4 either (the NSE would still build); only a file-pattern check does.

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-01, 02, 03, 04, 05, 07, 08, 09, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-06 | Done | ⚠️ Holds today; "no Core sources" clause unguarded on CocoaPods → Needs Fix (Fix 1) or accepted risk |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ❌ Not Ready (round 3 of 3 - escalate to user)

**Spec-anchored check**: 17/17 ACs hold on the current tree with evidence; PKG-06's source-isolation clause has no regression detector. Spec-precision notes: PKG-04, PKG-06, PKG-11.
**Sensor**: 17 non-equivalent injected, 14 killed, 3 survived (M-F1, M-F2, M-F4: podspec glob leaks Core sources into the Extension pod); 1 equivalent excluded (M-F3).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; all three scripts rc 0; `pod lib lint` full + Extension pass; both strict device builds rc 0; CI 38016135612 green.

**What works**: all round-1 and round-2 gaps are closed and proven against old code; the SPM split is fully guarded (dependency edges in every syntax, transitive edges, extra products, and SwiftPM's own overlap check); CocoaPods dependency edges and default subspec are guarded; manifests, version drift, lint and the test pipeline are correct.

**Issues found**: Fix 1 (assert podspec subspec file patterns in `check-package-graph.sh`); minor doc drift in `tasks.md:25,38`.

**Next steps**: user decides between Fix 1 (~10 lines in the existing script) followed by a confirmation run, or recording the accepted risk in STATE.
