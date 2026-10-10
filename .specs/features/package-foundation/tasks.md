# Package Foundation Tasks

**Design**: `.specs/features/package-foundation/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Status**: In Progress (T1–T7 done)

---

## Execution Plan

All tasks run sequentially (TESTING.md: unit/build gates are not parallel-safe in one checkout).

### Phase 1: Risk first

```
T1 (spike: -package-name in CocoaPods)
```

### Phase 2: Skeleton

```
T1 ──→ T2 ──→ T3
```

### Phase 3: Shared code and resources

```
T3 ──→ T4 ──→ T5
T3 ──→ T6 ──→ T7
```

### Phase 4: Packaging and guards

```
T1, T5, T7 ──→ T8 ──→ T9
T3 ─────────────────→ T10
T8 ─────────────────→ T11
```

### Phase 5: CI

```
T2, T9, T10, T11 ──→ T12
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12.

---

## Task Breakdown

### T1: Spike: CocoaPods honors `-package-name` across subspecs ✅ (AD-006)

**What**: In the scratchpad (not in the repo), build a throwaway package + podspec with subspecs `Shared` and `Core`, one `package func` in `Shared` called from `Core`, and run `pod lib lint`. Record the result as AD-006 in `STATE.md`.
**Where**: scratchpad dir (throwaway); `.specs/project/STATE.md` (AD-006, close the spike todo)
**Depends on**: None
**Reuses**: podspec sketch in design.md
**Requirement**: PKG-05 (risk), PKG-02

**Tools**: MCP: NONE. Skill: NONE. CLI: `pod`, `xcodebuild`.

**Done when**:

- [ ] `pod lib lint --platforms=ios --allow-warnings=false` result recorded (pass/fail plus the decisive log line)
- [ ] The same throwaway also builds through SPM (`xcodebuild build -scheme <Pkg>-Package`)
- [ ] AD-006 in STATE: either "`package` + `-package-name NottiSDK` works" or "fallback `@_spi(NottiInternal)` adopted", with the evidence
- [ ] If fallback: design.md "Cross-target visibility" updated to match, flagged in the task summary

**Tests**: none (spike)
**Gate**: none (the lint run is the evidence)
**Commit**: `docs(state): record CocoaPods package-name spike result (AD-006)`

---

### T2: Repo hygiene files ✅ (SwiftLint 0.65.1; `Tests/.swiftlint.yml` disables `identifier_name`; an empty tree exits 1, verified with temp files)

**What**: Add `.gitignore`, `LICENSE` (MIT, holder ZeepLabs), `README.md` stub (what it is, status "pre-release", SPM/CocoaPods install snippet), `CHANGELOG.md` (`[Unreleased]`) and `.swiftlint.yml` with the design thresholds.
**Where**: repo root
**Depends on**: T1
**Reuses**: `../zeep-notti-react-native/LICENSE`, `.gitignore`
**Requirement**: PKG-16, PKG-17

**Tools**: MCP: NONE. Skill: NONE. CLI: `docker`.

**Done when**:

- [ ] `.gitignore` covers `.build/`, `DerivedData/`, `Pods/`, `*.xcuserstate`, `.swiftpm/xcode/xcuserdata/`
- [ ] `.swiftlint.yml`: `included: [Sources, Tests]`; `file_length` error 2000; raised `type_body_length` / `function_body_length`; `identifier_name` disabled for `Tests`
- [ ] SwiftLint pinned image tag chosen and written down (used again in T12)
- [ ] `docker run ... swiftlint --strict` runs with 0 violations (empty tree is OK)

**Tests**: none
**Gate**: none (lint run)
**Commit**: `chore: add repo hygiene files and SwiftLint config`

---

### T3: `Package.swift`, version constant and placeholder targets ✅ (NottiSharedTests 1/1)

**What**: Create `Package.swift` per design (tools 5.9, iOS 15, Swift 5 mode, products `NottiSDK` + `NottiSDKExtension`, internal `NottiShared`, three test targets), `NottiSDKVersion.swift`, placeholder `NottiSDK.swift` / `NottiSDKExtension.swift`, and the first smoke test (version is semver). Uses the access keyword decided in T1.
**Where**: `Package.swift`, `Sources/NottiShared/NottiSDKVersion.swift`, `Sources/NottiSDK/NottiSDK.swift`, `Sources/NottiSDKExtension/NottiSDKExtension.swift`, `Tests/NottiSharedTests/NottiSDKVersionTests.swift`, placeholder files so `NottiSDKTests` / `NottiSDKExtensionTests` compile
**Depends on**: T2
**Reuses**: design.md "Package.swift"
**Requirement**: PKG-01, PKG-02, PKG-14

**Tools**: MCP: `context7` (SwiftPM manifest API, if a doubt comes up). Skill: NONE.

**Done when**:

- [ ] `swift package dump-package` shows exactly 2 library products and platform iOS 15
- [ ] `swift package show-dependencies` / `dump-package`: `NottiSDKExtension` target has no dependency on `NottiSDK`
- [ ] No `unsafeFlags`, no plugins
- [ ] `resources` and the `Fixtures` copy rule are NOT added yet if their folders don't exist (added in T6/T7 and core-port)
- [ ] Gate passes: quick `-only-testing:NottiSharedTests/NottiSDKVersionTests`
- [ ] Test count: NottiSharedTests 1

**Tests**: unit
**Gate**: quick
**Commit**: `feat(package): add Package.swift, version constant and target skeleton`

---

### T4: `NottiLogger` ✅ (NottiSharedTests 5/5; added a 4th test for `defaultLevel`)

**What**: `NottiLogLevel` and `NottiLogger` (default `.error`, lock-protected `level`/`sink`, `os.Logger` subsystem `app.notti.sdk`, `privacy: .public`) with tests.
**Where**: `Sources/NottiShared/NottiLogger.swift`, `Tests/NottiSharedTests/NottiLoggerTests.swift`
**Depends on**: T3
**Reuses**: design.md "NottiLogger"
**Requirement**: PKG-10 (smoke), prepares CORE-12/13

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] Default level is `.error`
- [ ] Tests: message at/above level reaches `sink`; message below is dropped and its autoclosure is not evaluated; `.none` drops everything
- [ ] `sink` reset in `tearDown` (no cross-test leak)
- [ ] Gate passes: quick `-only-testing:NottiSharedTests/NottiLoggerTests`
- [ ] Test count: NottiSharedTests 5 (1 + 4)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(shared): add NottiLogger with os.Logger backend and test sink`

---

### T5: `NottiPayloadKeys` ✅ (NottiSharedTests 6/6)

**What**: Payload key constants and the internal-key filter lists currently in RN `NottiNotificationParsing.swift:50-51`, plus a test that freezes their string values.
**Where**: `Sources/NottiShared/NottiPayloadKeys.swift`, `Tests/NottiSharedTests/NottiPayloadKeysTests.swift`
**Depends on**: T4
**Reuses**: RN `ios/NottiNotificationParsing.swift`, `ios/NotificationServiceExtension/NottiNotificationServiceExtension.swift:56`
**Requirement**: design (NottiShared); prepares CORE-01

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] Every key string copied verbatim from RN at `52e4b55`
- [ ] Test asserts the literal values (`notification_id`, `delivery_id`, `notti_image_url`, filter lists)
- [ ] Gate passes: quick `-only-testing:NottiSharedTests/NottiPayloadKeysTests`
- [ ] Test count: NottiSharedTests 6

**Tests**: unit
**Gate**: quick
**Commit**: `feat(shared): add frozen notification payload keys`

---

### T6: `NottiSDK` privacy manifest ✅ (NottiSDKTests 2/2; `NottiSDKResources.bundle` wraps `Bundle.module`)

**What**: `PrivacyInfo.xcprivacy` for `NottiSDK` (RN Core baseline + AD-005: CoarseLocation, ProductInteraction), wired as a `.process` resource, with a test that loads it from `Bundle.module` and asserts its content.
**Where**: `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy`, `Package.swift` (resources), `Tests/NottiSDKTests/PrivacyManifestTests.swift`
**Depends on**: T3
**Reuses**: `../zeep-notti-react-native/ios/PrivacyInfo.xcprivacy`
**Requirement**: PKG-11, PKG-13

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] `NSPrivacyTracking=false`; UserDefaults `CA92.1`; collected Email, Phone, CoarseLocation, ProductInteraction with linked/tracking/purposes per design
- [ ] `plutil -lint` passes
- [ ] Test: manifest present in the module bundle; 4 collected types + `CA92.1` asserted
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/PrivacyManifestTests`
- [ ] Test count: NottiSDKTests 2

**Tests**: unit
**Gate**: quick
**Commit**: `feat(sdk): add privacy manifest with AD-005 data types`

---

### T7: `NottiSDKExtension` privacy manifest ✅ (NottiSDKExtensionTests 1/1)

**What**: `PrivacyInfo.xcprivacy` for `NottiSDKExtension` (RN NSE baseline: FileTimestamp), wired as a resource, with a presence + content test.
**Where**: `Sources/NottiSDKExtension/Resources/PrivacyInfo.xcprivacy`, `Package.swift` (resources), `Tests/NottiSDKExtensionTests/PrivacyManifestTests.swift`
**Depends on**: T6
**Reuses**: `../zeep-notti-react-native/ios/NotificationServiceExtension/PrivacyInfo.xcprivacy`
**Requirement**: PKG-12

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] FileTimestamp accessed API with the same reason code as RN
- [ ] `plutil -lint` passes
- [ ] Gate passes: quick `-only-testing:NottiSDKExtensionTests/PrivacyManifestTests`
- [ ] Test count: NottiSDKExtensionTests 1

**Tests**: unit
**Gate**: quick
**Commit**: `feat(extension): add NSE privacy manifest`

---

### T8: `NottiSDK.podspec`

**What**: Podspec per design (subspecs Shared/Core/Extension, `resource_bundles`, `cocoapods_version >= 1.12`, `pod_target_xcconfig` per AD-006).
**Where**: `NottiSDK.podspec`
**Depends on**: T1, T5, T7
**Reuses**: design.md podspec sketch; `../zeep-notti-react-native/Notti.podspec`
**Requirement**: PKG-05, PKG-06, PKG-07

**Tools**: MCP: NONE. Skill: NONE. CLI: `pod`.

**Done when**:

- [ ] `pod lib lint NottiSDK.podspec --platforms=ios` passes
- [ ] `pod lib lint NottiSDK.podspec --platforms=ios --subspec=Extension` passes
- [ ] `pod ipc spec NottiSDK.podspec` shows `default_subspecs: Core` and no glob under `Tests/`
- [ ] `s.version` equals `NottiSDKVersion.current`

**Tests**: none (matrix: packaging = build)
**Gate**: build + `pod lib lint`
**Commit**: `feat(package): add NottiSDK podspec with Core and Extension subspecs`

---

### T9: `scripts/check-version.sh`

**What**: Script that compares `NottiSDKVersion.current` with the podspec `s.version` (and with the tag name on `refs/tags/*`), printing both values on mismatch.
**Where**: `scripts/check-version.sh`
**Depends on**: T8
**Reuses**: none
**Requirement**: PKG-15

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] Exit 0 on the current tree
- [ ] Exit 1 with both values printed when the podspec version is changed in a temp copy (do not commit the change)
- [ ] Exit 1 when `GITHUB_REF=refs/tags/9.9.9` is set
- [ ] POSIX `sh` or `bash` with `set -euo pipefail`; runs on ubuntu and macOS

**Tests**: none (verified by the three runs above)
**Gate**: script runs
**Commit**: `ci: add version drift check script`

---

### T10: `scripts/check-extension-safety.sh`

**What**: Script that greps `Sources/NottiShared` and `Sources/NottiSDKExtension` for `UIApplication`, `import UIKit`, `beginBackgroundTask`, `registerForRemoteNotifications`, `CLLocationManager`, and fails on any match.
**Where**: `scripts/check-extension-safety.sh`
**Depends on**: T3
**Reuses**: none
**Requirement**: PKG-03

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] Exit 0 on the current tree
- [ ] Exit 1 listing `file:line` when a temp file with `UIApplication.shared` is placed under `Sources/NottiShared` (removed after)
- [ ] Runs on ubuntu and macOS

**Tests**: none (verified by the two runs above)
**Gate**: script runs
**Commit**: `ci: add extension-safety guard script`

---

### T11: Device and simulator builds of both products

**What**: Verify locally that both products build for the iOS Simulator and for a generic iOS device (arm64), and that both products can be linked together without duplicate symbols. Fix whatever fails. No new files expected.
**Where**: none (fixes only, if needed)
**Depends on**: T8
**Reuses**: none
**Requirement**: PKG-04, PKG-02 (edge case: both products in one app)

**Tools**: MCP: NONE. Skill: NONE.

**Done when**:

- [ ] `xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS'` passes
- [ ] `xcodebuild build -scheme NottiSDKExtension -destination 'generic/platform=iOS'` passes
- [ ] The same two commands pass for `generic/platform=iOS Simulator`
- [ ] Full gate passes; total tests 9 (NottiSharedTests 6, NottiSDKTests 2, NottiSDKExtensionTests 1)

**Tests**: none (matrix: packaging = build)
**Gate**: full
**Commit**: only if a fix was needed: `fix(package): <what>`

---

### T12: GitHub Actions CI workflow

**What**: `.github/workflows/ci.yml` with jobs `lint`, `checks`, `test`, `pod-lint` per design, pinned Xcode + simulator in one `env:` block, flaky-warning grep ported from RN. Prove it red/green on a branch.
**Where**: `.github/workflows/ci.yml`
**Depends on**: T2, T9, T10, T11
**Reuses**: `../zeep-notti-react-native/.github/workflows/ci.yml` (`build-ios` job)
**Requirement**: PKG-08, PKG-09, PKG-10

**Tools**: MCP: NONE. Skill: NONE. CLI: `gh` (watch runs).

**Done when**:

- [ ] First run prints `xcodebuild -showsdks` / `xcrun simctl list` and the pins match what `macos-26` actually has (adjust and re-run if not)
- [ ] Branch `ci/bootstrap` push: all 4 jobs green
- [ ] A commit with a deliberately failing test turns `test` red; the revert turns it green again (both commits squashed/dropped before merge)
- [ ] Workflow triggers on `pull_request` and on `push` to `main`

**Tests**: none (verified by the red/green runs)
**Gate**: CI run
**Commit**: `ci: add GitHub Actions workflow (lint, checks, test, pod-lint)`

---

## Granularity Check

| Task | Scope | Status |
| --- | --- | --- |
| T1 | 1 spike + 1 AD | ✅ |
| T2 | 5 static repo files, no code | ⚠️ OK, cohesive (scaffolding, no logic) |
| T3 | manifest + 1 constant + placeholders the manifest needs to compile | ⚠️ OK, cannot build a manifest without its targets |
| T4 | 1 type + its test | ✅ |
| T5 | 1 file + its test | ✅ |
| T6 | 1 resource + wiring + test | ✅ |
| T7 | 1 resource + wiring + test | ✅ |
| T8 | 1 podspec | ✅ |
| T9 | 1 script | ✅ |
| T10 | 1 script | ✅ |
| T11 | verification only | ✅ |
| T12 | 1 workflow | ✅ |

## Diagram-Definition Cross-Check

| Task | Depends on (body) | Diagram shows | Status |
| --- | --- | --- | --- |
| T1 | None | none | ✅ |
| T2 | T1 | T1 → T2 | ✅ |
| T3 | T2 | T2 → T3 | ✅ |
| T4 | T3 | T3 → T4 | ✅ |
| T5 | T4 | T4 → T5 | ✅ |
| T6 | T3 | T3 → T6 | ✅ |
| T7 | T6 | T6 → T7 | ✅ |
| T8 | T1, T5, T7 | T1, T5, T7 → T8 | ✅ |
| T9 | T8 | T8 → T9 | ✅ |
| T10 | T3 | T3 → T10 | ✅ |
| T11 | T8 | T8 → T11 | ✅ |
| T12 | T2, T9, T10, T11 | T2, T9, T10, T11 → T12 | ✅ |

No `[P]` tasks (TESTING.md: not parallel-safe).

## Test Co-location Validation

| Task | Code layer | Matrix requires | Task says | Status |
| --- | --- | --- | --- | --- |
| T1 | spike (throwaway) | none | none | ✅ |
| T2 | repo hygiene | none | none | ✅ |
| T3 | `NottiShared` (version) + packaging | unit | unit | ✅ |
| T4 | `NottiShared` (logger) | unit | unit | ✅ |
| T5 | `NottiShared` (keys) | unit | unit | ✅ |
| T6 | resources | unit | unit | ✅ |
| T7 | resources | unit | unit | ✅ |
| T8 | packaging | build | none + build/lint gate | ✅ |
| T9 | scripts | none | none | ✅ |
| T10 | scripts | none | none | ✅ |
| T11 | packaging | build | none + full gate | ✅ |
| T12 | CI workflow | none | none | ✅ |

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| PKG-01 | T3 |
| PKG-02 | T1, T3, T11 |
| PKG-03 | T10 (+ `example-and-release` NSE build) |
| PKG-04 | T11, T12 |
| PKG-05 | T1, T8, T12 |
| PKG-06 | T8 |
| PKG-07 | T8 |
| PKG-08 | T12 |
| PKG-09 | T12 |
| PKG-10 | T3, T4, T6, T7, T12 |
| PKG-11 | T6 |
| PKG-12 | T7 |
| PKG-13 | T6 (process rule, re-checked per feature) |
| PKG-14 | T3 |
| PKG-15 | T9, T12 |
| PKG-16 | T2 |
| PKG-17 | T2, T12 |

17/17 mapped.
