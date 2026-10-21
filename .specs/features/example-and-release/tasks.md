# Example App and Release 0.1.0 Tasks

**Design**: `.specs/features/example-and-release/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: `nse-rich-media` done (586 tests on `main`)
**Status**: Draft

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: 586 SDK tests (unchanged by this feature; the example adds its own hosted tests).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| `ExampleConfig`, `ExampleLog`, `ExampleModel` | unit (hosted XCTest) | configured/unconfigured, closed log events, sentinel never in a row | `Example/Tests/*Tests.swift` | `xcodebuild test -project Example/NottiExample.xcodeproj -scheme NottiExample -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` |
| Hook and resources in the real product | integration (hosted XCTest) | `loadCount == installCount == 1`; privacy bundles present in app and appex | `Example/Tests/ProductIntegrationTests.swift` | same, per leg (spm, pods-static, pods-libs) |
| SwiftUI screens | none | covered by `docs/DEVICE_CHECKLIST.md` | - | build only |
| New scripts under `scripts/` | none (script) | each run against a passing tree and a mutated failing tree; both outputs in the commit body | - | the script |
| `README.md`, `CHANGELOG.md`, `docs/`, specs | none | `check-readme-snippets.sh`, `check-version.sh` | - | the scripts |
| `.github/workflows/ci.yml` | none | proven by the first PR run | - | PR CI |

## Gate Check Commands

> Xcode 27: run every `xcodebuild` through the scratchpad watchdog `run.sh`, simulator `iPhone 17 Pro`, no piping into grep, no `timeout`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After a task that only touches scripts or docs | the affected scripts, `scripts/check-version.sh`, `scripts/check-public-surface.sh` |
| Example | After tasks that touch `Example/` | `xcodegen generate --spec Example/project.yml` then the example test command above |
| Full | After T6, T7 and T11 | Example gate on every leg + `xcodebuild test -scheme NottiSDK-Package ...` + SwiftLint (`docker run ... lint --strict`) + all `scripts/check-*.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` |

---

## Rules (apply to every task)

1. No SDK behavior change (AD-001, AD-002). A bug found here becomes a `STATE.md` todo, or, if it blocks the example, its own commit with a test and a note to Julio.
2. No secret, appId, client key, push token, email or phone value in any tracked file, log, test name or screenshot. Fixtures: `example.invalid`, `fixture`.
3. The example never calls the network in tests: hosted tests do not call `Notti.initialize` with the sample config.
4. Do not run two `xcodebuild` processes on the same checkout. Never run `pod install` while a build runs.
5. Generated projects (`*.xcodeproj`, `*.xcworkspace`, `Pods/`) are git-ignored; a `project.yml` change ships with a generating, building project.
6. Each task is one commit, conventional style (`feat(example):`, `docs:`, `ci:`, `chore:`), no AI attribution. Work on a branch and a PR; nothing is pushed to `main` without Julio's explicit go-ahead.
7. The agent never creates the `0.1.0` tag, a GitHub Release or runs `pod trunk push`.

---

## Execution Plan

Sequential (TESTING.md: not parallel-safe). Suggested split for sub-agents: T1 to T6, then T7 to T12.

### Phase 1: Spikes and scaffold

```
T1 ──→ T2
T2 ──→ T3
```

### Phase 2: App and guards

```
T3 ──→ T4
T4 ──→ T5
T4 ──→ T6
```

### Phase 3: CocoaPods, docs, CI

```
T6 ──→ T7
T4 ──→ T8
T7 ──→ T9
T8 ──→ T9
T7 ──→ T10
T9 ──→ T10
T10 ──→ T11
T11 ──→ T12
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12.

### Diagram-definition cross-check

| Task | Depends on (definition) | Edges in the diagram |
| --- | --- | --- |
| T1 | None | none |
| T2 | T1 | `T1 → T2` |
| T3 | T2 | `T2 → T3` |
| T4 | T3 | `T3 → T4` |
| T5 | T4 | `T4 → T5` |
| T6 | T4 | `T4 → T6` |
| T7 | T6 | `T6 → T7` |
| T8 | T4 | `T4 → T8` |
| T9 | T7, T8 | `T7 → T9`, `T8 → T9` |
| T10 | T7, T9 | `T7 → T10`, `T9 → T10` |
| T11 | T10 | `T10 → T11` |
| T12 | T11 | `T11 → T12` |

All match. No `[P]` task.

---

## Task Breakdown

### T1: Spikes (XcodeGen, pod module, plist per configuration)

**What**: Install XcodeGen locally (`brew install xcodegen`, note the version) and prove in a scratch directory the five [Incerto] items of the design: local package with a different directory name shared by an app and an appex; `INFOPLIST_FILE` per configuration; optional `#include?` of the local xcconfig through `configFiles`; `NottiBootstrap` and `NottiNotificationServiceExtension` visibility under a local-path pod (static and dynamic); Extension subspec exposing the class in module `NottiSDK`. Write results into the design file ("Spike results" table), keep no scratch project in the repo.
**Where**: `.specs/features/example-and-release/design.md`
**Depends on**: None
**Reuses**: `scripts/hook-consumer` approach, `NottiSDK.podspec`
**Requirement**: EXR-01, EXR-04, EXR-17, EXR-18, EXR-19 (de-risk)

**Done when**:

- [x] Each of the five questions has a recorded result (works, or the fallback chosen) with the command that proved it
- [x] Any answer that changes the design updates the design in the same commit
- [ ] Gate check passes: quick

**Tests**: none
**Gate**: quick
**Commit**: `docs(specs): record the example app spike results`

---

### T2: Example scaffold (SPM) with a minimal app and NSE

**What**: `Example/project.yml`, `Config/Example.xcconfig` + `.sample`, minimal `ExampleApp` and `NotificationService` (the doc-comment wiring), entitlements and the two plists, `.gitignore` entries. Builds for the simulator and a generic device unsigned.
**Where**: `Example/`, `.gitignore`
**Depends on**: T1
**Reuses**: wiring snippet in `NottiNotificationServiceExtension.swift`
**Requirement**: EXR-01, EXR-05 (build part), EXR-07, EXR-08

**Done when**:

- [ ] `xcodegen generate` then the simulator build succeeds with only the sample xcconfig
- [ ] Generic device build succeeds with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and the NSE with `APPLICATION_EXTENSION_API_ONLY=YES`
- [ ] The NSE target links `NottiSDKExtension` and not `NottiSDK` (shown with the target's dependency list)
- [ ] `git status` shows no generated project file
- [ ] Gate check passes: Example (build)

**Tests**: none (build), scaffold has no logic
**Gate**: Example
**Commit**: `feat(example): scaffold the SwiftUI example app and NSE target`

---

### T3: `ExampleConfig`, `ExampleLog` and the hosted test target

**What**: `ExampleConfig` (reads the three Info.plist keys, `isConfigured`, optional `https://<host>`), `ExampleLog` with the closed `LogEvent` enum, and the `NottiExampleTests` target.
**Where**: `Example/App/ExampleConfig.swift`, `Example/App/ExampleLog.swift`, `Example/Tests/`, `Example/project.yml`
**Depends on**: T2
**Reuses**: none
**Requirement**: EXR-03, EXR-05, EXR-06

**Done when**:

- [x] Empty, `fixture` and unsubstituted `$(...)` values give `isConfigured == false`; a real-looking synthetic value gives true
- [x] A host `h.example.invalid` becomes `https://h.example.invalid`; empty host gives nil (SDK default)
- [x] `ExampleLog` has no API taking an arbitrary string from SDK data; a sentinel passed to every `LogEvent` constructor never appears in `rows`
- [x] Gate check passes: Example (tests)
- [x] Test count: at least 8 hosted tests (15: 8 config, 7 log)

**Tests**: unit (hosted)
**Gate**: Example
**Commit**: `feat(example): add the example config and a redacting log`

---

### T4: `ExampleModel`, screens and the manual-forwarding mode

**What**: One method per public member in `ExampleModel`, the five screens, `ExampleAppDelegate` behind `USE_ADAPTOR`, the manual-forwarding adapter active only when the plist key is present, `Debug-Manual` configuration with `Info-Manual.plist`.
**Where**: `Example/App/`, `Example/project.yml`
**Depends on**: T3
**Reuses**: `PUBLIC_SURFACE.txt` as the checklist of members
**Requirement**: EXR-02, EXR-03, EXR-04

**Done when**:

- [x] Every member in scope of EXR-02 is called from `ExampleModel` and reachable from a screen
- [x] In the unconfigured state no screen action calls the SDK and the UI says "not configured"
- [x] A hosted test drives `ExampleModel` with sentinel email, phone and key and finds none in the log rows
- [x] The `Debug-Manual` configuration builds; the manual path forwards the five calls and the default path forwards none
- [x] Gate check passes: Example

**Tests**: unit (hosted)
**Gate**: Example
**Commit**: `feat(example): exercise every public API from the example app`

---

### T5: Drift guards for the example

**What**: `scripts/check-example-coverage.sh` (EXR-02) and `scripts/check-example-config.sh` (EXR-04 plist diff, EXR-06 no real config in tracked files), both runnable on Linux; wire them into the `checks` job.
**Where**: `scripts/`, `.github/workflows/ci.yml`
**Depends on**: T4
**Reuses**: shape of `scripts/check-public-surface.sh`
**Requirement**: EXR-02, EXR-04, EXR-06, EXR-24 (part)

**Done when**:

- [x] Both scripts pass on the tree
- [x] Mutation evidence in the commit body: remove one call from `ExampleModel` (fails), change one key in only one plist (fails), put a non-`fixture` value in the sample (fails)
- [x] The allowlist of non-callable public names has a reason per line
- [x] Gate check passes: quick

**Tests**: none (script, mutation evidence)
**Gate**: quick
**Commit**: `ci(example): guard the example against public API and config drift`

---

### T6: Product integration tests (SPM leg)

**What**: `ProductIntegrationTests`: hook counts and the presence of the privacy bundles in the app and in `PlugIns/NotificationService.appex`, with the SPM bundle names.
**Where**: `Example/Tests/ProductIntegrationTests.swift`
**Depends on**: T4
**Reuses**: `NottiBootstrap.loadCount`/`installCount`
**Requirement**: EXR-18 (SPM), EXR-19 (SPM)

**Done when**:

- [x] `loadCount == 1` and `installCount == 1` in the hosted app process
- [x] The app product contains a bundle with `PrivacyInfo.xcprivacy`, and the appex contains one for the extension, by exact name asserted as a literal
- [x] Removing the `NottiSDKBootstrap` dependency in `Package.swift` makes the hook test fail (mutation evidence in the commit body)
- [x] Gate check passes: Example

**Tests**: integration (hosted)
**Gate**: Example
**Commit**: `test(example): prove the launch hook and privacy bundles in the built product`

---

### T7: CocoaPods variant (static frameworks, static libraries, dynamic frameworks)

**What**: `project-pods.yml`, `Podfile` (`:path => '..'`, `NOTTI_LINKAGE=static|libs|dynamic`), pod bundle names in the integration test; run the hosted tests and a generic device build for the three linkages.
**Where**: `Example/project-pods.yml`, `Example/Podfile`, `Example/Tests/ProductIntegrationTests.swift`, `.gitignore`
**Depends on**: T6
**Reuses**: T1 spike results, `scripts/check-hook-linked.sh pod` semantics
**Requirement**: EXR-17, EXR-18, EXR-19

**Done when**:

- [x] `pod install` + hosted tests pass with `use_frameworks! :linkage => :static`, with static libraries (`use_modular_headers!`) and with dynamic frameworks (`use_frameworks!`; S6 is fixed by AD-012)
- [x] App uses `pod 'NottiSDK'` and NSE uses `pod 'NottiSDKExtension'` only (NSE imports `NottiSDKExtension`, as in SPM; no conditional import)
- [x] The bundles `NottiSDK_Privacy` and `NottiSDKExtension_Privacy` are found in the products of each linkage
- [x] Hook counts equal 1 in each linkage (static libraries covered, which `check-hook-linked.sh pod` did not)
- [x] `PKG-06` independent test result and the CocoaPods `Resources` todo are noted in `STATE.md` as closed or narrowed
- [x] Gate check passes: Example on the three linkages

**Tests**: integration (hosted)
**Gate**: Example
**Commit**: `feat(example): build the example through CocoaPods`

---

### T8: README rewrite and snippet guard

**What**: Rewrite `README.md` per EXR-10..14 with `<!-- snippet:<id> -->` blocks taken from `Example/` regions, and `scripts/check-readme-snippets.sh`. Data section is derived from the code (`NottiCore`, `NottiDeviceStore`, storage keys, manifest).
**Where**: `README.md`, `Example/App/*` and `Example/NotificationService/*` (region markers), `scripts/check-readme-snippets.sh`, `.github/workflows/ci.yml`
**Depends on**: T4
**Reuses**: RN README "Privacy, App Store labels and LGPD" structure, `PrivacyInfo.xcprivacy`
**Requirement**: EXR-10, EXR-11, EXR-12, EXR-13, EXR-14, EXR-24

**Done when**:

- [x] Every section and limitation named in EXR-10..12 exists, with the CocoaPods import note for the NSE
- [x] The LGPD note recommends internal legal review and does not claim compliance; no host or key other than placeholders; production default host stated once
- [x] `check-readme-snippets.sh` passes, and fails when a snippet or its source region is edited (mutation evidence)
- [x] The listed fields and storage keys match the code (one grep per key recorded in the commit body)
- [x] Gate check passes: quick

**Tests**: none (script, mutation evidence)
**Gate**: quick
**Commit**: `docs: write the integrator README with checked snippets`

---

### T9: Device validation checklist

**What**: `docs/DEVICE_CHECKLIST.md` with every item of EXR-15, each citing its `STATE.md` todo, prerequisites (Push capability, key, real appId in the local xcconfig), steps and expected result.
**Where**: `docs/DEVICE_CHECKLIST.md`
**Depends on**: T7, T8
**Reuses**: STATE.md device todos
**Requirement**: EXR-15, EXR-16

**Done when**:

- [x] Every device-only todo in `STATE.md` appears exactly once (list of the todos matched in the commit body)
- [x] Each item has a pass/fail box, an observable expected result and no secret
- [x] The README links to it
- [x] Gate check passes: quick

**Tests**: none
**Gate**: quick
**Commit**: `docs: add the device validation checklist`

---

### T10: CI `example` job

**What**: Matrix job `spm | pods-static | pods-libs | pods-dynamic` (dynamic added by AD-012) on `macos-26` with a pinned XcodeGen, per leg: generate, (pod install), test, generic device build (warnings as errors, NSE with `APPLICATION_EXTENSION_API_ONLY=YES`); SPM leg also builds `Debug-Manual`.
**Where**: `.github/workflows/ci.yml`
**Depends on**: T7, T9
**Reuses**: existing `test` and `pod-lint` job steps
**Requirement**: EXR-23

**Done when**:

- [ ] Draft PR CI runs the legs green (link recorded). **Blocked 2026-10-21:** GitHub Actions billing; no job starts. The SPM leg's commands were run locally instead (generate, device build, `Debug-Manual`, `--built` plist checks).
- [x] A generated project or `Pods/` is never committed by a leg (step `Nothing generated is tracked`)
- [ ] Gate check passes: Full (pending the CI run above)

**Tests**: none (CI)
**Gate**: Full
**Commit**: `ci: build and test the example app through SPM and CocoaPods`

---

### T11: Release preparation

**What**: `CHANGELOG.md` `0.1.0` section (Added, Known limitations, migration from `react-native-notti` 0.6.0), README status banner, `check-version.sh` check for the top dated CHANGELOG section, release PR text with the pre-tag gates. Leaves the date to be set at release.
**Where**: `CHANGELOG.md`, `README.md`, `scripts/check-version.sh`
**Depends on**: T10
**Reuses**: RN CHANGELOG migration notes
**Requirement**: EXR-20, EXR-21, EXR-22

**Done when**:

- [ ] `check-version.sh` fails when the CHANGELOG top section, `NottiSDKVersion.current` and `s.version` differ (mutation evidence), passes when equal at `0.1.0`
- [ ] Migration notes cover storage keys and device id continuity
- [ ] Gates for Julio listed in the PR text: device checklist, Device ID manifest decision, UserID text confirmed, `pod lib lint`, tag, GitHub Release, `pod trunk push`
- [ ] Gate check passes: Full

**Tests**: none (script)
**Gate**: Full
**Commit**: `docs: prepare the 0.1.0 changelog and version guard`

---

### T12: Traceability and state

**What**: `traceability.md` mapping EXR-01..24 to files, scripts and tests, update `STATE.md` (closed todos, new todos, lessons), `ROADMAP.md` status, independent Verifier via `tlc-spec-driven` Validate.
**Where**: `.specs/features/example-and-release/traceability.md`, `.specs/project/STATE.md`, `.specs/project/ROADMAP.md`
**Depends on**: T11
**Reuses**: nse-rich-media `traceability.md` shape
**Requirement**: EXR-01 to EXR-24

**Done when**:

- [ ] Every EXR id maps to a file, a script or a test (or to the checklist, for device-only items)
- [ ] `STATE.md` closes only the todos the CI proved; device todos stay open until Julio runs the checklist
- [ ] `validate_tasks.py` and `validate_state.py` pass
- [ ] Gate check passes: Full

**Tests**: none
**Gate**: Full
**Commit**: `docs(specs): trace example-and-release and update state`
