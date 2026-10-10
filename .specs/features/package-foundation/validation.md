# Validation: package-foundation - FAIL ❌

**Date**: 2026-10-10
**Spec**: `.specs/features/package-foundation/spec.md`
**Diff range**: `92ccd8c..fc2da93` (code surface: `Package.swift`, `NottiSDK.podspec`, `Sources/`, `Tests/`, `scripts/`, `.github/`, hygiene files). Since round 4 (`ccf605a`) the code surface changed only in `fc2da93`: `scripts/check-package-graph.sh` +59/-47 (CocoaPods half rewritten as an exact-shape allowlist; new `run()` wrapper for `swift`/`pod`). `Sources/`, `Tests/`, `Package.swift`, the podspec, `ci.yml` and the other two scripts are byte-identical to round 4.
**Verifier**: independent sub-agent (author ≠ verifier), round 5 (owner-authorized extra round)
**Environment**: Xcode 27.0 (27A266a), simulator `iPhone 17 Pro`, CocoaPods 1.17.0, SwiftLint 0.65.1 (Docker), GNU grep 3.11 (`ubuntu:24.04`). CI evidence read-only (`gh run view`, `gh api …/check-runs/<id>/annotations`). No pushes, re-runs or edits on GitHub.

---

## Earlier gaps → status (rounds 1-4)

| Round | Gap | Status | Evidence (re-derived this round) |
| --- | --- | --- | --- |
| 1 | Flaky-test warning never fired on Xcode 26+ (PKG-09b) | ✅ Closed | Pattern read from `ci.yml:85` replayed on the `Unit tests` step: probe run 38015155294 → 1 match (`…FlakyProbeTests test_failsOnceThenPasses]' started (Iteration 2 of 2).`); head run 38078188795 → 0 matches (9× `Iteration 1 of 2`). Same counts on BSD grep and GNU grep 3.11. Head test-job annotations: only the runner-capacity notice, no warning. |
| 1 | `check-extension-safety.sh` silent pass on GNU grep with a missing dir (PKG-03) | ✅ Closed | `scripts/check-extension-safety.sh:17-22`. `ubuntu:24.04` on a `git archive` copy: clean → `extension safety ok` rc 0; `NottiShared` renamed + `UIApplication.shared` planted in `NottiSDKExtension` → `error: expected directory not found: /e/Sources/NottiShared` rc 1. Control: `247befa` script on the same tree → `grep: … No such file or directory` then `extension safety ok` rc 0. |
| 2 | NSE→app dependency edge not caught: M-D1 (SPM), M-D2 (podspec) | ✅ Closed | M-D1 → `error: SPM target NottiSDKExtension must depend on ['byName:NottiShared'], got ['byName:NottiSDK', 'byName:NottiShared']`; M-D2 → `error: podspec subspec Extension must be exactly {…}, got {…'dependencies': {'NottiSDK/Core': [], …}`; both rc 1. Fresh syntax `.target(name: "NottiSDK")` → `got ['byName:NottiShared', 'target:NottiSDK']` rc 1. |
| 3 | Widened podspec globs leak Core into the Extension pod: M-F1, M-F2, M-F4 | ✅ Closed | `check-package-graph.sh:81-106` (exact subspec equality). M-F1 → `subspec Extension must be exactly …` rc 1; M-F2 → `got {'name': 'Shared', 'source_files': 'Sources/{NottiShared,NottiSDK}/**/*.swift'}` rc 1; M-F4 → `got {… 'Sources/**/*.swift'}` rc 1. |
| 4 | Platform-scoped attributes / nested subspec bypass: N1, N2, N3, N5, N6; swallowed command errors (N4) | ✅ Closed | Exact-shape compare (`:105`) and root allowlist (`:66-73`). Each rc 1 with the offending key in the `got` dict: N1 `'ios': {'source_files': 'Sources/NottiSDK/**/*.swift'}`; N2 `'ios': {'dependencies': {'NottiSDK/Core': []}}`; N3 (Shared) `'ios': {'source_files': …}`; N5 `'ios': {'resource_bundles': {'NottiSDK_Privacy': […]}}`; N6 `'subspecs': [{'name': 'Helpers', 'source_files': 'Sources/NottiSDK/**/*.swift'}]`. N4 now prints `error: 'pod ipc spec NottiSDK.podspec' failed:` + `A subspec can't require one of its parents specifications` rc 1. Root-level variants also killed (fresh F6). |

---

## Task Completion

Checked against artifacts, not the ✅ marks (the "Done when" checkboxes in `tasks.md` are unticked; the task headings carry the ✅ and results).

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | AD-006 in `.specs/project/STATE.md:48-55`; `NottiSDK.podspec:22` `-package-name NottiSDK`; `package` access compiles across subspecs (both lints pass). |
| T2 | ✅ Done | `.gitignore`; `.swiftlint.yml`; `Tests/.swiftlint.yml` disables `identifier_name`; `lint --strict` → `Found 0 violations, 0 serious in 12 files.` rc 0. |
| T3 | ✅ Done | `Package.swift:1,6,9,11,16-26`; `dump-package` shows 2 products, `[{'platformName': 'ios', 'version': '15.0'}]`, tools `5.9.0`; no `unsafeFlags`/plugins. |
| T4 | ✅ Done | `Tests/NottiSharedTests/NottiLoggerTests.swift` 4 tests pass. One unclaimed branch (sensor F3, note). |
| T5 | ✅ Done | `Tests/NottiSharedTests/NottiPayloadKeysTests.swift:8-19`; sensor F4 killed. |
| T6 | ✅ Done | `Tests/NottiSDKTests/PrivacyManifestTests.swift` 2 tests pass. |
| T7 | ✅ Done | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift` passes. |
| T8 | ✅ Done | `pod lib lint` full rc 0, `--subspec=Extension --verbose` rc 0; Extension lint touches only the 3 `NottiShared` + 2 `NottiSDKExtension` Swift files and the Extension manifest (0 `Sources/NottiSDK/` paths). |
| T9 | ✅ Done | `scripts/check-version.sh` → `version ok: 0.1.0` rc 0 (macOS + `ubuntu:24.04`). |
| T10 | ✅ Done | See round-1 row. |
| T11 | ✅ Done | Both strict device builds verbatim from `ci.yml:94-98` rc 0, no warnings; full suite 6/2/1. |
| T12 | ✅ Done | `ci.yml` 4 jobs; run 38078188795 on `fc2da93` all success. |
| Round-4 Fix 1 (`fc2da93`) | ✅ Done, with a regression note | Closes the N1-N6 class; `run()` now merges stderr into the JSON it parses (Gap 2). |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | Evidence (`file:line` + assertion / command output) | Result |
| --- | --- | --- | --- | --- |
| PKG-01 | Consumer resolves package | `Package.swift` declares `.iOS(.v15)` and exactly two library products `NottiSDK`, `NottiSDKExtension` | Products: `Package.swift:9,11`; `scripts/check-package-graph.sh:38` `products != {"NottiSDK": ["NottiSDK"], "NottiSDKExtension": ["NottiSDKExtension"]}` → error. Platform: `Package.swift:6` holds today, **but no gate step asserts it**: sensor F2 (`.iOS(.v16)`) passes the graph check, both strict device builds, the full test suite and every other step. The podspec side does assert it (`check-package-graph.sh:74`, F6 `16.0` killed). Round-4's "enforced by the builds" is disproven. | ⚠️ Holds today, ❌ platform clause unguarded (Gap 1) |
| PKG-02 | NSE links `NottiSDKExtension` | No `NottiSDK` target in its graph; shared code in internal non-product target | `Package.swift:16,22-26`; `check-package-graph.sh:50-60` (`NottiShared` deps `[]`, `NottiSDKExtension` deps exactly `[byName:NottiShared]`). M-D1 and `.target(name:)` variant killed. Source widening via `path:`/`sources:` (F1) is rejected by SwiftPM itself: `target 'NottiSDKExtension' has overlapping sources: …/Sources/NottiSDK/NottiSDK.swift`, build rc 74. | ✅ PASS |
| PKG-03 | Extension + shared target built | `APPLICATION_EXTENSION_API_ONLY` semantics | `ci.yml:98` strict extension build with `APPLICATION_EXTENSION_API_ONLY=YES` rc 0; `check-extension-safety.sh` rc 0 (macOS + GNU), kills planted cases incl. nested dirs (F5: `…/Deep/Er/X.swift:2:…registerForRemoteNotifications()` rc 1). Compiler leg proven in round 4 (M-A); sources unchanged. | ✅ PASS |
| PKG-04 | Either product built for Simulator and device arm64 | Succeeds; warnings are errors in CI | Device: `ci.yml:96-98` verbatim → `sdk rc=0`, `ext rc=0`, empty warning/error grep. Simulator: `xcodebuild test` (not strict) + `pod lib lint` (simulator, no `--allow-warnings`). | ✅ PASS + spec-precision note (unchanged) |
| PKG-05 | `pod lib lint NottiSDK.podspec` | Passes for both subspecs | Local full rc 0, `--subspec=Extension` rc 0 (`NottiSDK passed validation.` ×2); CI 38078188795 same ×2. | ✅ PASS |
| PKG-06 | Podfile `NottiSDK` / NSE `NottiSDK/Extension` | Default Core; Extension gets only Extension + Shared sources, no Core sources | `NottiSDK.podspec:24,28,40-42`; `check-package-graph.sh:76` default Core; `:81-106` exact shape of `Shared`/`Core`/`Extension` (deps, globs, resource bundles, no `ios`/`subspecs`/other keys); `:66-73` root allowlist. Kills M-D2, M-F1/2/4, N1-N6, F6. Control Extension lint compiles 0 Core files. Real Podfile app+NSE test still not run (STATE todo). | ✅ PASS (note) |
| PKG-07 | Podspec globs evaluated | Test sources excluded from every subspec | `NottiSDK.podspec:28,34,41` all under `Sources/`; any other glob fails exact equality (`:105`); root `source_files = 'Tests/**/*.swift'` and `test_spec` → `podspec root has keys outside the allowlist: ['source_files']` / `['testspecs']` rc 1. | ✅ PASS |
| PKG-08 | PR opened/updated | macOS runner builds both products for Simulator, runs all XCTest targets, `pod lib lint`, SwiftLint | `ci.yml:3-7,24-31,45-76,100-119`. Run 38078188795 (`pull_request`, `fc2da93`): lint/checks/test/pod-lint success; `Executed 6 tests` / `2 tests` / `1 test`, `** TEST SUCCEEDED **`; `Found 0 violations`; `package graph ok`. | ✅ PASS |
| PKG-09a | Any step fails | Workflow fails | Run 38012402254 (`2756451`) `failure` on the deliberate failing test; `set -o pipefail` `ci.yml:69,95`; graph check `sys.exit(1)` (`check-package-graph.sh:111`). | ✅ PASS |
| PKG-09b | Flaky retries enabled | Retries visible in the log | `ci.yml:73,85-89`; round-1 row. | ✅ PASS |
| PKG-10 | Skeleton only | ≥1 smoke test per product runs and passes | Local: `NottiSharedTests.xctest` passed (Executed 6), `NottiSDKTests.xctest` passed (2), `NottiSDKExtensionTests.xctest` passed (1); CI same. | ✅ PASS |
| PKG-11 | `NottiSDK` consumed | `NSPrivacyTracking=false`, UserDefaults `CA92.1`, Email + Phone, CoarseLocation, ProductInteraction, not tracking | `Tests/NottiSDKTests/PrivacyManifestTests.swift:25` `XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)`; `:31` `… as? [String], ["CA92.1"]`; `:35-40` set of the 4 types; `:43` tracking false per entry. SPM path only. | ✅ PASS (note) |
| PKG-12 | `NottiSDKExtension` consumed | ≥ RN NSE manifest (FileTimestamp) | `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift:19` `XCTAssertEqual(fileTimestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])`; `:14` tracking false. | ✅ PASS |
| PKG-13 | Later feature adds API/data type | That feature updates the manifest | Process rule (`AGENTS.md`). | ✅ N/A in scope |
| PKG-14 | Code needs SDK version | Single constant in one file | `Sources/NottiShared/NottiSDKVersion.swift:8` `package static let current = "0.1.0"`; `Tests/NottiSharedTests/NottiSDKVersionTests.swift:7-10` semver assertion. | ✅ PASS |
| PKG-15 | CI runs | Fails if podspec version ≠ constant | `scripts/check-version.sh:13-24`, `ci.yml:40`; local + CI `version ok: 0.1.0`. | ✅ PASS |
| PKG-16 | Repo cloned | Hygiene files present | `.gitignore`; `LICENSE:1` `MIT License`; `README.md:23,37`; `CHANGELOG.md:7` `## [Unreleased]`; `.swiftlint.yml`. | ✅ PASS |
| PKG-17 | SwiftLint on skeleton | Zero violations | Local `lint --strict` rc 0 `Found 0 violations, 0 serious in 12 files.`; CI same. | ✅ PASS |

**Status**: ❌ One in-scope clause without a discriminating guard: PKG-01 platform (Gap 1). Spec-precision notes unchanged: PKG-04 (simulator compile not strict), PKG-06 (Podfile test), PKG-11 (CocoaPods resource branch).

### Edge cases

- [x] Only `NottiSDKExtension` in an app target: documented `README.md:37`; product builds standalone (strict device build rc 0).
- [x] Both products in one binary, no duplicate symbols: full `pod lib lint` builds Shared+Core+Extension together and passes; round-2 SPM consumer (sources unchanged since).
- [x] `swift-tools-version` stays 5.9: `Package.swift:1`. Guard is incidental only: bumping to `6.0` (F2b) fails the graph check with a `json.decoder.JSONDecodeError` traceback because SwiftPM prints a deprecation warning that `run()` merges into the JSON (Gap 2). Builds and tests pass with 6.0. Fixing Gap 2 alone would turn F2b into a survivor, so the fix for Gap 1 should assert `toolsVersion` too.

### Success criteria

- [x] Fresh project links both products and builds (round-2 SPM consumer; real NSE appex is `example-and-release`).
- [x] CI green on `main` (38012837541, `2511ac1`) and on head (38078188795, `fc2da93`); red on a deliberately broken test (38012402254).
- [x] `pod lib lint` passes (both invocations, local and CI).

---

## Discrimination Sensor

Run in `git worktree add --detach <scratch>/verifier5/wt HEAD` with `-derivedDataPath <scratch>/verifier5/dd-wt`; each mutation applied with an exact-anchor replace, run, then reverted with `git checkout -- .` (`git clean -fdq` after the false-positive probe). Extension-safety cases on a `git archive` copy in `ubuntu:24.04`; flaky-pattern replay on CI logs saved to scratch. The real tree was never touched.

| # | Target (`file:line`) | Fault | Detector → output | Killed? |
| --- | --- | --- | --- | --- |
| R1-a (re-run) | `ci.yml:85` | Real retry line `started (Iteration 2 of 2)` (CI 38015155294) | Pattern matches 1 (BSD + GNU); head log 0 | ✅ Killed |
| R1-b (re-run) | `scripts/check-extension-safety.sh:17-22` | `NottiShared` missing + `UIApplication.shared` planted, GNU grep | `error: expected directory not found` rc 1 (old `247befa` script rc 0) | ✅ Killed |
| M-D1 (re-run) | `Package.swift:24` | `NottiSDKExtension` deps `+ "NottiSDK"` | graph rc 1, names `byName:NottiSDK` | ✅ Killed |
| M-D2 (re-run) | `NottiSDK.podspec:41` | Extension `+ ss.dependency 'NottiSDK/Core'` | graph rc 1, `subspec Extension must be exactly` | ✅ Killed |
| M-F1 (re-run) | `NottiSDK.podspec:41` | Extension globs add `Sources/NottiSDK/**/*.swift` | graph rc 1 | ✅ Killed |
| M-F2 (re-run) | `NottiSDK.podspec:28` | Shared `Sources/{NottiShared,NottiSDK}/**/*.swift` | graph rc 1 | ✅ Killed |
| M-F4 (re-run) | `NottiSDK.podspec:28` | Shared `Sources/**/*.swift` | graph rc 1 | ✅ Killed |
| N1 (re-run) | `NottiSDK.podspec:41` | Extension `+ ss.ios.source_files = 'Sources/NottiSDK/**/*.swift'` | graph rc 1, `got` shows `'ios': {'source_files': …}` | ✅ Killed |
| N2 (re-run) | `NottiSDK.podspec:41` | Extension `+ ss.ios.dependency 'NottiSDK/Core'` | graph rc 1, `'ios': {'dependencies': {'NottiSDK/Core': []}}` | ✅ Killed |
| N3 (re-run) | `NottiSDK.podspec:28` | Shared `+ ss.ios.source_files = 'Sources/NottiSDK/**/*.swift'` | graph rc 1 | ✅ Killed |
| N4 (re-run) | `NottiSDK.podspec:41` | Extension `+ ss.dependency 'NottiSDK'` | `error: 'pod ipc spec NottiSDK.podspec' failed:` + CocoaPods reason, rc 1 (now diagnosable) | ✅ Killed |
| N5 (re-run) | `NottiSDK.podspec:42` | Extension `+ ss.ios.resource_bundles = { 'NottiSDK_Privacy' => [Core manifest] }` | graph rc 1, `'ios': {'resource_bundles': …}` | ✅ Killed |
| N6 (re-run) | `NottiSDK.podspec:41` | Nested `ss.subspec 'Helpers'` with a Core glob | graph rc 1, `'subspecs': [{'name': 'Helpers', …}]` | ✅ Killed |
| F1 (fresh) | `Package.swift:22-26` | SPM analog of M-F1: `NottiSDKExtension` gets `path: "Sources", sources: ["NottiSDKExtension", "NottiSDK/NottiSDK.swift"]` | graph check passes (does not read `path`/`sources`), but SwiftPM rejects it: `target 'NottiSDKExtension' has overlapping sources: …/Sources/NottiSDK/NottiSDK.swift`, `describe` rc 1, extension build rc 74 | ✅ Killed (by SwiftPM) |
| **F2 (fresh)** | `Package.swift:6` | `platforms: [.iOS(.v15)]` → `[.iOS(.v16)]` (PKG-01) | graph `package graph ok` rc 0; strict device builds `sdk rc=0`, `ext rc=0`; full suite `** TEST SUCCEEDED **`; `check-version` / `check-extension-safety` rc 0; podspec untouched so both lints unaffected | ❌ Survived |
| F2b (fresh) | `Package.swift:1` | `swift-tools-version:5.9` → `6.0` (edge case 3) | graph rc 1, but only via `JSONDecodeError: Expecting value: line 1 column 1` (SwiftPM's `swiftLanguageVersions` deprecation warning on stderr merged into the JSON by `run()`); builds pass | ⚠️ Killed incidentally (see Gap 2) |
| F3 (fresh) | `Sources/NottiShared/NottiLogger.swift:61` | Remove `guard messageLevel != .none else { return }` (a `.none`-level call now reaches the sink) | full suite `** TEST SUCCEEDED **` | ❌ Survived - not covered by any package-foundation AC (logger is T4 / CORE-12; T4 Done-when covers *level* `.none`, not a *message* at `.none`). Non-blocking note. |
| F4 (fresh) | `Sources/NottiShared/NottiPayloadKeys.swift:26` | `internalKeyPrefixes` drops `"aps."` | `NottiPayloadKeysTests.swift:19` fails, `** TEST FAILED **` rc 65 | ✅ Killed |
| F5 (fresh) | `scripts/check-extension-safety.sh:26` | `registerForRemoteNotifications()` in `Sources/NottiShared/Deep/Er/X.swift` (nested dir), GNU grep | rc 1 citing `X.swift:2` | ✅ Killed |
| F6 (fresh) | `NottiSDK.podspec:24` (root) | Root `s.ios.source_files` (Core glob), `s.ios.dependency`, `s.source_files = 'Tests/**'`, `s.test_spec`, `s.ios.deployment_target = '16.0'` | graph rc 1 each: `root has keys outside the allowlist: ['ios']` / `['source_files']` / `['testspecs']`; `platforms must be {'ios': '15.0'}, got {'ios': '16.0'}` | ✅ Killed |

**Sensor depth**: P1 packaging: 13 earlier mutants re-run (R1-a, R1-b, M-D1, M-D2, M-F1, M-F2, M-F4, N1-N6) + 7 fresh (F1, F2, F2b, F3, F4, F5, F6).
**Sensor result**: 20 injected, 18 killed (1 incidentally: F2b), 2 survived: **F2** (in-scope, PKG-01) and F3 (out of AC scope, note) - FAIL ❌ on F2.

Severity of F2: Minor. A raise of the SPM deployment target silently drops iOS 15 SPM consumers and makes SPM and CocoaPods disagree (the podspec raise is caught, the SPM raise is not). A realistic trigger is a later feature using an iOS 16 API and bumping `Package.swift` to silence availability errors; that particular case would also break `pod lib lint` (podspec still 15.0), so the pure-bump case is the one that slips through. The behavioral packaging invariants (dependency edges, source isolation, resources) are fully guarded.

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ `fc2da93` replaces the field-by-field checks with one allowlist + three literal shapes; net +12 lines. |
| Surgical changes | ✅ Only `scripts/check-package-graph.sh`. |
| No scope creep | ✅ |
| Matches patterns | ✅ Same structure as the SPM half; errors name the subspec. |
| Spec-anchored outcome check | ⚠️ PKG-06 now guarded as a whole-shape check (closes the syntactic class). PKG-01 platform not asserted on the SPM side (Gap 1). |
| Per-layer Coverage Expectation met | ✅ `tasks.md:25,38` include the graph check. |
| Every test maps to a spec requirement | ✅ Logger/keys → T4/T5 + PKG-10; manifests → PKG-10/11/12; version → PKG-14. |
| Documented guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml` | ✅ |

`check-package-graph.sh` review (`fc2da93`):

- **Correct and closes the class.** The CocoaPods half is now a literal: root keys allowlist (`:66-73`), `platforms == {'ios': '15.0'}` (`:74`), `default_subspecs` Core (`:76`), subspec names in order (`:99-101`) and each subspec equal to its expected dict (`:103-106`). Platform-scoped keys, nested subspecs, extra deps, widened globs, borrowed resources and test specs all fail. Readable: the expected shapes are the documentation.
- **Gap 2 (regression in `fc2da93`, Minor): `run()` merges stderr into the parsed JSON** (`:20` `out="$("$@" 2>&1)"`). Any warning that `swift package dump-package` or `pod ipc spec` writes to stderr - a SwiftPM deprecation (proven with F2b), a Ruby/gem warning from a future CocoaPods or runner image - turns a valid manifest into `json.decoder.JSONDecodeError` with a Python traceback and no hint of the cause. Fails closed, so not an AC violation, but it is a latent false positive on runner/Xcode bumps and makes F2b's kill accidental. Fix: capture stderr to a temp file and print it only on failure (`out="$("$@" 2>"$err")"`).
- **Error messages are long**: on a mismatch the script prints the whole expected and actual dicts on one line (~400 chars). Usable (the offending key is visible), not a defect.
- **False positives on planned work: none found.** Probe on a scratch copy with the core-port shape (`Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Sources/NottiShared/Parsing/NottiParsing.swift`, `Tests/NottiSDKTests/Fixtures/rn-0.6.0-state.plist` + `resources: [.copy("Fixtures")]` on the `NottiSDKTests` test target, as in `core-port/tasks.md:343-344`) → `package graph ok` rc 0. New files under existing folders match the `**` globs; test targets are ignored (`:49`).
- **Expected friction, by design (Low)**: any podspec attribute added to a subspec - e.g. `ss.frameworks = 'UserNotifications'` (probe: rc 1, `subspec Core must be exactly …`), a new resource bundle, `exclude_files`, `weak_frameworks` - fails until the expected shape is updated in the same change. ROADMAP features that may touch packaging (`nse-rich-media`, `nse-shared-state`, `delegate-integration`, `rn-consumes-native-sdk`) are mostly code-only (Swift autolinks system frameworks), so the friction is occasional and the header (`:9`) tells the author what to do. Acceptable.
- Minor (from round 3, still present): `.target(name: "NottiShared")` dependency syntax is rejected by the SPM half (only `byName:` expected). Fails safe. Low.

---

## Gate Check

- **Gate command** (Full, `tasks.md:38` + CI parity): `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" -retry-tests-on-failure -test-iterations 2 CODE_SIGNING_ALLOWED=NO` (log to file, `perl alarm` timeout) + `docker run … swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` (+ `--subspec=Extension`) + the two strict device builds verbatim from `ci.yml:94-98`.
- **Result**: 9 passed, 0 failed, 0 skipped (`** TEST SUCCEEDED **`, rc 0): NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1; no `Iteration 2` lines. SwiftLint `Found 0 violations, 0 serious in 12 files.` rc 0. `version ok: 0.1.0`, `extension safety ok` (macOS + `ubuntu:24.04`), `package graph ok` (all rc 0). `pod lib lint` full + Extension `NottiSDK passed validation.` rc 0. Device builds `NottiSDK` rc 0, `NottiSDKExtension` (+`APPLICATION_EXTENSION_API_ONLY=YES`) rc 0. Only non-compiler warnings in the test log (3× `appintentsmetadataprocessor … Metadata extraction skipped`).
- **Test count before feature**: 0 (greenfield). **After**: 9. **Delta**: +9. Unchanged vs rounds 1-4.
- **Skipped tests**: none. **Failures**: none.
- **CI (read-only)**: 38078188795 (`pull_request`, `fc2da93`) success, 4 jobs, `package graph ok`, annotations only runner notices (macOS capacity; `ubuntu-latest` migrates to Ubuntu 26 from 2026-10-19); 38056359219 (`caac386`) success; 38016135612 (`b9a8785`) success; 38015155294 (`637f45e`, flaky probe) success + retry line; 38012402254 (`2756451`) failure (deliberate); 38012837541 (`main`, `2511ac1`) success.

---

## Fix Plans

### Fix 1: assert the SPM platform and tools version in the graph check - Minor (blocks a strict PASS)

- **Root cause**: the SPM half of `scripts/check-package-graph.sh:36-60` checks products and two targets' dependencies, but not `platforms` or `toolsVersion`, while the CocoaPods half asserts `platforms == {'ios': '15.0'}` (`:74`). Nothing else in the gate depends on the SPM minimum.
- **Fix task**: in the SPM half add, with named errors:
  - `spm["platforms"] == [{"platformName": "ios", "version": "15.0", "options": []}]` (shape verified from `dump-package` on Xcode 27);
  - `spm["toolsVersion"]["_version"] == "5.9.0"` (edge case 3).
- **Verify**: on a scratch copy, F2 (`.iOS(.v16)`), `.iOS(.v15), .macOS(.v12)` and F2b (`6.0`, after Fix 2) each exit 1 with a named error; clean tree and the core-port-shape probe exit 0; CI green.
- **Alternative if the owner declines**: record in STATE that the SPM platform/tools version are review-guarded only. Accepting it is defensible (declaration literal, visible in any diff); this report fails on it only because it is an in-scope AC clause with a surviving mutant and the CocoaPods side already guards the same value.

### Fix 2: keep stderr out of the parsed JSON - Minor (code quality, not blocking on its own)

- **Root cause**: `check-package-graph.sh:20` `out="$("$@" 2>&1)"`.
- **Fix task**: capture stderr separately (e.g. `err="$(mktemp)"; out="$("$@" 2>"$err")" || { cat "$err" >&2; exit 1; }`), print stderr only on failure.
- **Verify**: F2b then fails on the Fix 1 tools-version assertion, not on a traceback; N4 still prints the CocoaPods reason.

### Notes (non-blocking; first four already tracked as STATE todos)

- PKG-04 spec precision: the simulator compile in `xcodebuild test` is not warnings-as-errors; `pod lib lint` (simulator, no `--allow-warnings`) and the strict device builds are the guards.
- PKG-11: CocoaPods resource branch (`NottiSDKResources.swift:12-18`, `NottiSDKExtensionResources.swift:12-18`) never executed in a test (`STATE.md:107`).
- Manifest purposes (`NSPrivacyCollectedDataTypePurposes`) not asserted (`STATE.md:108`).
- PKG-06 independent test (throwaway Podfile, app + NSE) not run (`STATE.md:109`).
- F3: `NottiLogger.log(.none, …)` reaching the sink is untested; belongs to `core-port`/CORE-12 if that behavior matters.
- CI: `ubuntu-latest` (lint, checks jobs) moves to Ubuntu 26 on 2026-10-19; GNU-grep behavior was verified on 24.04 only. Pin `ubuntu-24.04` or re-check after the switch.

---

## Requirement Traceability Update

The verifier does not edit `spec.md` (out of its write scope). Recommended statuses:

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| PKG-02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 14, 15, 16, 17 | Done | ✅ Verified |
| PKG-01 | Done | ⚠️ Holds today; platform clause unguarded → Needs Fix (Fix 1) or accepted risk |
| PKG-13 | Done | ✅ Process rule documented; re-checked per feature |

---

## Summary

**Overall**: ❌ Not Ready (round 5, owner-authorized extra round; one Minor gap - decision goes back to the owner)

**Spec-anchored check**: 17/17 ACs hold on the current tree with evidence; PKG-01's platform clause has no discriminating guard on the SPM side. Spec-precision notes: PKG-04, PKG-06, PKG-11.
**Sensor**: 20 injected, 18 killed (F2b incidentally), 2 survived: F2 (SPM `.iOS(.v16)`, in scope) and F3 (logger `.none` message, out of AC scope).
**Gate**: 9 passed / 0 failed / 0 skipped; SwiftLint 0; all three scripts rc 0; `pod lib lint` full + Extension pass; both strict device builds rc 0; CI 38078188795 green.

**What works**: every round 1-4 gap is closed with re-derived evidence (R1 flaky pattern + GNU grep guard, R2 edges, R3 globs, R4 platform-scoped/nested podspec bypasses and swallowed errors); the podspec guard is now an exact-shape allowlist with no false positive on the planned core-port shape; SwiftPM itself rejects SPM source widening; Swift tests discriminate (F4).

**Issues found**: Fix 1 (2 assertions in the SPM half, Minor) or an accepted-risk entry; Fix 2 (stderr separation, Minor, regression from `fc2da93`).

**Next steps**: owner decides between Fix 1 + Fix 2 with a closure-confirmation run, or accepting Gap 1 as a documented risk (Fix 2 still recommended).
