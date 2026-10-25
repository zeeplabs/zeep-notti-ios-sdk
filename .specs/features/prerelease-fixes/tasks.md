# Pre-release Fixes Tasks

**Spec**: `.specs/features/prerelease-fixes/spec.md` (design inline, D1-D9)
**Testing**: `.specs/codebase/TESTING.md`
**Status**: Execute in progress

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`) and `AGENTS.md`. One commit per task, conventional style, no AI attribution. Stay on the current branch; commit locally only.

---

## Test Coverage Matrix

> Baseline (STATE, in-app-open-url): Shared 14, SDK 894, ObjC 7, Extension 110, ExtensionObjC 3. Counts below are minimum additions per task.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| --- | --- | --- | --- | --- |
| ObjC layer (`NottiObjC.swift`) | unit + ObjC compile check | Runtime names; every entry point compiles from ObjC; mixed arrays | `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m` | quick `-only-testing:NottiSDKTests/NottiObjCBridgeTests -only-testing:NottiSDKObjCTests` |
| Facade (`NottiFacade`) | unit | Warning per dropped call, none after initialize, sentinel-free | `Tests/NottiSDKTests/NottiFacadeProfileTests.swift` | quick, `NottiFacadeProfileTests` |
| Delegates (`NottiAppDelegateSwizzler`, `NottiDelegateInstaller`) | unit | Fake dynamic subclasses in both install orders; late observe once and on main | `Tests/NottiSDKTests/NottiAppDelegateSwizzlerTests.swift`, `Tests/NottiSDKTests/NottiDelegateInstallerTests.swift` | quick, those classes |
| Runtime + In-App engine hooks | unit | Retired core's late registration ignored; current core's accepted | `Tests/NottiSDKTests/NottiInAppWiringTests.swift`, `Tests/NottiSDKTests/NottiInAppEngineFetchTests.swift` | quick, those classes |
| In-App UI (`NottiInAppWindowHost`) | unit | Scene key from the target | `Tests/NottiSDKTests/NottiInAppPresenterTests.swift` | quick, `NottiInAppPresenterTests` |
| In-App engine log text | unit | 403 literal | `Tests/NottiSDKTests/NottiInAppEngineFetchTests.swift`, `Tests/NottiSDKTests/NottiInAppPrivacyTests.swift` | quick, those classes |
| Docs, specs | none | By review | - | - |

## Gate Check Commands

| Gate Level | When to Use | Command |
| --- | --- | --- |
| Quick | After each code task | `caffeinate -dimsu xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | After T12 | the same without `-only-testing`, plus `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` and the seven guard scripts of AGENTS.md |
| Build | Docs-only tasks | none (review), SwiftLint when a Swift file changed |

---

## Execution Plan

### Phase 1: Spec

```
T1
```

### Phase 2: Fixes

```
T1 ──→ T2
T1 ──→ T3
T1 ──→ T4
T4 ──→ T5
T4 ──→ T6
T1 ──→ T7
T1 ──→ T8
T1 ──→ T9
T1 ──→ T10
T1 ──→ T11
T1 ──→ T12
```

Sequential order used in Execute: T1 → T2 → ... → T12.

---

## Task Breakdown

### T1: Spec, AD-021 and todos

**What**: This spec and tasks file; AD-021 (ObjC rename) and the N5, N6 and UN-delegate todos in `STATE.md`.
**Where**: `.specs/features/prerelease-fixes/spec.md`, `.specs/project/STATE.md`
**Depends on**: None
**Requirement**: PRF-12

**Done when**:

- [x] `validate_spec.py` and `validate_tasks.py` exit 0
- [x] AD-021 and the three todos in `STATE.md`

**Tests**: none
**Gate**: build
**Commit**: `docs(specs): prerelease-fixes spec and AD-021`

---

### T2: Rename the ObjC facade class to `NottiSDK`

**What**: `@objc(NottiSDK)` on `NottiObjC`; ObjC tests, README ObjC block, CHANGELOG and doc comments use `NottiSDK`; a test pins the runtime names against RN's classes.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`
**Depends on**: T1
**Requirement**: PRF-01

**Done when**:

- [x] `NSClassFromString("NottiSDK") === NottiObjC.self` and no `Notti`, `NottiImpl`, `NottiBridge`, `NottiPushDelegate` class is registered
- [x] `NottiObjCTests.m` calls `[NottiSDK ...]` and passes
- [x] Test count: SDK +1
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(objc): register the Objective-C facade as NottiSDK`

---

### T3: Warn on identity calls before initialize

**What**: One fixed `.warn` per `login`, tag and `setSubscription` call made before a valid `initialize`; docs say these are dropped and `logout` is kept.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadeProfileTests.swift`
**Depends on**: T1
**Requirement**: PRF-02

**Done when**:

- [x] Each dropped call logs its fixed line once; none after initialize; no sentinel in any line
- [x] Doc comment, README and CHANGELOG corrected
- [x] Test count: SDK +2
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(facade): warn when identity calls are dropped before initialize`

---

### T4: Pin one observation behind an isa-swizzled app delegate

**What**: Verify the review's M2 in code. Result: `type(of:)` already answers `-class`, so no double observation; no source change. Regression tests pin the single observation and the premise.
**Where**: `Tests/NottiSDKTests/NottiAppDelegateSwizzlerTests.swift`
**Depends on**: T1
**Requirement**: PRF-03

**Done when**:

- [x] SDK-first order observes each callback once and calls the host original once (test)
- [x] A proxied SwiftUI internal delegate takes the adaptor path (test)
- [x] `type(of:)` answering `-class` pinned (test)
- [x] Test count: SDK +3
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `test(delegates): pin one observation behind an isa-swizzled app delegate`

---

### T5: Look at existing delegates once (not implemented)

**What**: Dropped: its only reason was the double observation that T4 disproved; the repeated late look is idempotent.
**Where**: `Sources/NottiSDK/Delegates/NottiDelegateInstaller.swift`
**Depends on**: T4
**Requirement**: PRF-04

**Done when**:

- [x] Recorded as not implemented in the spec traceability

**Tests**: none
**Gate**: build
**Commit**: none

---

### T6: Read existing delegates on the main thread

**What**: The late look goes through `Environment.runOnMain` (sync on main, async otherwise).
**Where**: `Sources/NottiSDK/Delegates/NottiDelegateInstaller.swift`, `Tests/NottiSDKTests/NottiDelegateInstallerTests.swift`
**Depends on**: T4
**Requirement**: PRF-05

**Done when**:

- [x] The delegate is not read until the main hop runs; the production hop runs a background caller's task on main
- [x] Test count: SDK +2
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(delegates): read existing delegates on the main thread`

---

### T7: Sanitize ObjC `removeTags:`

**What**: `removeTags:` takes `NSArray` and drops non-strings; `PUBLIC_SURFACE.txt` updated.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`
**Depends on**: T1
**Requirement**: PRF-06

**Done when**:

- [x] A mixed `NSArray` from ObjC does not crash; the PATCH removes only the string keys
- [x] Test count: SDK +1, ObjC +1
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(objc): drop non-string keys in removeTags`

---

### T8: Scope the registration hook to the core's config

**What**: A replaced core's registration does not mark the new In-App config as registered.
**Where**: `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Sources/NottiSDK/InApp/Engine/NottiInAppHooks.swift`, `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift`, `Tests/NottiSDKTests/NottiInAppWiringTests.swift`
**Depends on**: T1
**Requirement**: PRF-07

**Done when**:

- [x] Retired core's late success: `registeredInProcess` false, no `eligible`; current core's success marks it
- [x] Test count: SDK +2
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(in-app): ignore a replaced core's device registration`

---

### T9: Document the `opensInAppURLs` rule

**What**: Docs (Options, ObjC, README, AD-020 note) and a public-API test: an `initialize` without the option sets it to true.
**Where**: `Sources/NottiSDK/Public/Notti.swift`, `Tests/NottiSDKTests/NottiInAppURLOpenerTests.swift`
**Depends on**: T1
**Requirement**: PRF-08

**Done when**:

- [x] `Notti.initialize(appId:clientKey:)` after `opensInAppURLs: false` gives `true`
- [x] Test count: SDK +1
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `docs(in-app): every initialize sets opensInAppURLs`

---

### T10: Scene key from the host's target

**What**: `NottiInAppWindowHost.sceneKey` returns the target's scene.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppWindow.swift`, `Tests/NottiSDKTests/NottiInAppPresenterTests.swift`
**Depends on**: T1
**Requirement**: PRF-09

**Done when**:

- [x] A host for `.scene(s)` reports `s` with no window; a `.screen` host reports nil
- [x] Test count: SDK +1
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(in-app): match a disconnected scene against the host's target`

---

### T11: 403 log text

**What**: New fixed 403 text; README and CHANGELOG; AD-013 note.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift`, `Tests/NottiSDKTests/NottiInAppEngineFetchTests.swift`
**Depends on**: T1
**Requirement**: PRF-11

**Done when**:

- [x] Tests assert the new literal; no line says "until the next registration"
- [x] Test count: unchanged
- [x] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `fix(in-app): say the 403 pause lasts for the session`

---

### T12: Click and runtime doc nits, final record

**What**: `takeInitialClick`/`addClickedListener` docs (Swift, ObjC, facade, README), `ensureCore` comment; STATE current-work line with counts; full gate.
**Where**: `Sources/NottiSDK/Public/Notti.swift`, `Sources/NottiSDK/Runtime/NottiRuntime.swift`
**Depends on**: T1
**Requirement**: PRF-10

**Done when**:

- [ ] Docs match the buffer's behavior
- [ ] Full gate green, counts not lower than baseline
- [ ] Gate passes: full

**Tests**: none
**Gate**: full
**Commit**: `docs: click delivery and pre-initialize core notes`
