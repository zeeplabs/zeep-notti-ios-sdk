# macOS Support (0.3.0) Tasks

**Spec**: `.specs/features/macos-support/spec.md` (MAC-01..26)
**Design**: `.specs/features/macos-support/design.md` (Draft, approval is the owner's)
**Testing**: `.specs/codebase/TESTING.md`
**Status**: Draft (tasks awaiting approval)

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`) and `AGENTS.md`. One commit per task, conventional style, no AI attribution. Work on a feature branch created from `docs/macos-support-spec` so the specs travel with the code; push and open PRs only with Julio's OK. One `xcodebuild` at a time on this machine; never two on one checkout.

**If the skill cannot be activated, STOP and tell the user.**

Scope: all 26 requirements. T27 needs a real Mac with an Apple Developer team and the backend `macos-platform` deployed to a reachable environment; T28 (tag, GitHub Release, `pod trunk push`) is Julio's.

## Defaults applied (change here before the named task if you disagree)

| Question | Default used |
| --- | --- |
| Branch | `feat/macos-support` from `docs/macos-support-spec` |
| macOS gate destination | `platform=macOS,arch=arm64` for tests, `generic/platform=macOS` for builds (design D14); T14 confirms on this machine and on the CI image |
| macOS evidence before the module compiles | The located-error count of `xcodebuild build -scheme NottiSDK-Package -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \| grep -E '\.swift:[0-9]+:[0-9]+: error:' \| sort -u \| wc -l`. Baseline after T4 is the Pass 2 list of the design (22); each task in phase 2 records the new number and must not raise it |
| macOS destination (T14 result) | `platform=macOS,arch=arm64` resolves to the native `My Mac` as the first of several matches (it prints a warning, the first listed is native); `generic/platform=macOS` for builds has one match. Mac Catalyst builds the iOS path |
| macOS-only tests | Written in T19 to T22, after the module compiles (design C7) |
| Public surface | The macOS `Void` variant of `didReceiveRemoteNotification` is accepted (design D4); T9 stops if Julio chooses otherwise |
| iOS regression guard | The iOS suite passes with no edit to an existing assertion. Allowed test edits: wrapping a UIKit-only file or line in `#if canImport(UIKit)`, and making a platform constant conditional |

---

## Test Coverage Matrix

> Guidelines found: `AGENTS.md` (Commands, Rules, Public API surface, Privacy and logging, Extension safety, Git and CI), `.specs/codebase/TESTING.md` (coverage matrix, gate commands, test counts), `.github/workflows/ci.yml`, `.swiftlint.yml`. Baseline from STATE at `3d1cad6`: Shared 14, SDK 907, ObjC 8, Extension 110, ExtensionObjC 3. T1 re-measures. Counts below are minimum additions.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| --- | --- | --- | --- | --- |
| `NottiShared` (`NottiSDKVersion.platform`, `name`) | unit | Per-platform literal asserted as a literal (`ios` on iOS, `macos` on macOS); AD-024 wrapper override unchanged | `Tests/NottiSharedTests/` | quick |
| `NottiPlatformInfo` pure helpers | unit (both platforms) | Version formatting: `14.0.0` to `14.0`, `14.4.1` to `14.4.1`, `15.0` to `15.0`; model nil on empty | `Tests/NottiSDKTests/NottiPlatformInfoTests.swift` | quick |
| `NottiLifecycle` seam | unit | iOS names equal the `UIApplication` constants; macOS names equal the `NSApplication` constants; observers fire the same core paths; zero registered observers fails | `Tests/NottiSDKTests/NottiLifecycleTests.swift`, `NottiCoreTests` | quick |
| Core and runtime lifecycle (macOS) | unit | become active starts a session, resign active ends it, terminate ends it once with a bounded wait, a second end is a no-op | `Tests/NottiSDKTests/NottiCoreTerminateTests.swift` (`#if os(macOS)`) | macOS quick |
| Background wrapper (macOS) | unit | Activity begun once, ended once, idempotent end, end after terminate flush | `Tests/NottiSDKTests/NottiBackgroundActivityTests.swift` (`#if os(macOS)`) | macOS quick |
| Delegate integration (macOS) | unit | Fake `NSApplicationDelegate` classes (own `objc_allocateClassPair`, unique names): token, failure, remote notification with and without each host original, original called once with the same arguments, double-swizzle guard, SwiftUI-internal class skipped, adaptor target swizzled; no test swizzles `NSApplication` or `UNUserNotificationCenter` | `Tests/NottiSDKTests/NottiAppDelegateSwizzlerMacTests.swift` (`#if os(macOS)`) | macOS quick |
| Push adapter and manual API | unit | macOS `Void` variant; ignored with one warning while swizzling is active; iOS `.noData` unchanged | `NottiPushAdapterTests`, `NottiPublicApiTests`, `NottiObjCBridgeTests` | quick |
| Registration and profile on macOS | unit | `POST /devices` body has `platform: "macos"` and the hex token; PATCH `sdk_name: "macos"`; wrapper value wins; failure logs `domain#code` only | `NottiCoreTests`, `NottiRuntimeTests`, `NottiLoggingPrivacyTests` | macOS quick |
| In-App inert on macOS | unit | No request through `StubURLProtocol`, no `notti_pending_inapp_events` write, no engine config, `trackEvent` and click listener compile and do nothing | `Tests/NottiSDKTests/NottiInAppMacInertTests.swift` (`#if os(macOS)`) | macOS quick |
| Privacy manifests | unit | Both plists parse on both platforms; required-reason list unchanged; no new collected type | `NottiLoggingPrivacyTests`, extension tests | quick |
| NSE (`NottiSDKExtension`) | unit | The existing 110 plus 3 ObjC tests pass on the macOS destination with the stub session | `Tests/NottiSDKExtensionTests/`, `NottiSDKExtensionObjCTests` | macOS full |
| Objective-C layer | ObjC compile check | `@objc` surface compiles on macOS; the UIKit-only reference is `#if` | `Tests/NottiSDKObjCTests/NottiObjCTests.m` | macOS full |
| Scripts (`check-*.sh`) | script mutation | A passing tree and one failing fixture per new banned token or required attribute | `scripts/`, fixtures in the task | run the script on mutated trees |
| Packaging (`Package.swift`, podspecs) | build | `xcodebuild build` both platforms; `pod lib lint --platforms=ios,osx` for both pods, with and without `--use-libraries` | n/a | build gate |
| Example app (macOS) | build | `xcodebuild build` of the generated macOS project; hosted tests out of scope | `Example/project-mac.yml` | build gate |
| Docs, specs, versions | none | By review; `check-version.sh`; `validate_*.py` | n/a | build gate |

## Gate Check Commands

| Gate Level | When to Use | Command |
| --- | --- | --- |
| Quick | After a code task | `caffeinate -dimsu xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17" CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` plus, in phase 2, the macOS located-error count of the Defaults table |
| macOS quick | After T19 | `caffeinate -dimsu xcodebuild test -scheme NottiSDK-Package -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | T14, T19, T21, T22, T24, T27, T28 | The iOS test run without `-only-testing`, the same on `platform=macOS,arch=arm64` (from T19), SwiftLint (`docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict`), the seven guard scripts of AGENTS.md (`check-version.sh`, `check-extension-safety.sh`, `check-package-graph.sh`, `check-public-surface.sh`, `check-no-url-open.sh`, `check-launch-hook-purity.sh`, `check-nse-logging.sh`), strict builds (`xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -quiet`, the same for `generic/platform=macOS`, and `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES` for both), `scripts/check-hook-linked.sh spm` (and `spm-macos` from T24), `pod lib lint NottiSDK.podspec --platforms=ios,osx` and the Extension pod, with and without `--use-libraries` |
| Build | Docs, script and packaging tasks | The check named in the task (script on fixtures, `pod lib lint`, `validate_*.py`, `check-version.sh`) |

Test counts are read from the `Executed N tests` line of each bundle. A lower number than the one recorded in T1 (iOS) or T19 (macOS) is a silently dropped test and fails the task.

---

## Execution Plan

### Phase 1: Decisions and manifest

```
T1
T1 → T2
T2 → T3
```

### Phase 2a: Compile burndown, seams and platform info

```
T2 → T4
T4 → T5
T4 → T6
T3 → T6
T4 → T7
T5 → T8
T4 → T9
```

### Phase 2b: AppKit adapters, In-App out, compile green

```
T9 → T10
T10 → T11
T5 → T11
T6 → T11
T8 → T11
T4 → T12
T12 → T13
T11 → T13
T5 → T13
T6 → T14
T7 → T14
T8 → T14
T9 → T14
T10 → T14
T11 → T14
T12 → T14
T13 → T14
```

### Phase 3: Guards, packaging, privacy

```
T14 → T15
T14 → T16
T14 → T17
T14 → T18
```

### Phase 4: Tests on macOS

```
T14 → T19
T19 → T20
T10 → T20
T9 → T20
T19 → T21
T8 → T21
T13 → T21
T19 → T22
T17 → T22
```

### Phase 5: CI, example, docs

```
T19 → T23
T15 → T23
T16 → T23
T17 → T23
T14 → T24
T14 → T25
T25 → T26
T18 → T26
```

### Phase 6: Verification and release

```
T20 → T27
T21 → T27
T22 → T27
T23 → T27
T24 → T27
T26 → T27
T27 → T28
```

Sequential order for Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14 → T15 → T16 → T17 → T18 → T19 → T20 → T21 → T22 → T23 → T24 → T25 → T26 → T27 → T28.

---

## Task Breakdown

### T1: AD-025 follow-through, AGENTS.md platform rules and baselines

**What**: Update `AGENTS.md` for two platforms: the intro (iOS 15+ and macOS 12+), the "M1 is a port" rule marked expired by `0.1.0` (AD-002 note), the Commands block (macOS test and build commands), the Extension-safety paragraph (`AppKit`, `NSApplication`, `NSWorkspace` banned; `macOSApplicationExtension`), the Public API surface paragraph (both attributes), the No-URL-open paragraph (`NSWorkspace`), the version paragraph (nothing changes). `STATE.md` Current Work line. Re-measure and record the iOS test counts of `main`.
**Where**: `AGENTS.md`, `.specs/project/STATE.md`
**Depends on**: None
**Reuses**: AD-025, the AD-002 status note already in `STATE.md`
**Requirement**: MAC-01, MAC-02, MAC-04, MAC-05

**Tools**:

- MCP: NONE
- Skill: `tlc-spec-driven`

**Done when**:

- [ ] `AGENTS.md` names both platforms and carries the new commands; no rule is loosened except the expired port rule
- [ ] The iOS counts (Shared, SDK, ObjC, Extension, ExtensionObjC) are written in `STATE.md` from one full run
- [ ] `validate_state.py` reports no new error (the two existing errors listed in the wrapper-support tasks may remain; list them)

**Tests**: none
**Gate**: build
**Commit**: `docs: macOS platform rules in AGENTS.md and baseline counts`

---

### T2: Package manifest declares macOS 12 and the graph guard follows

**What**: `platforms: [.iOS(.v15), .macOS(.v12)]` in `Package.swift`; `scripts/check-package-graph.sh` SPM check expects exactly iOS 15.0 and macOS 12.0 (the podspec check stays until T17, so the script is run with the SPM part updated only).
**Where**: `Package.swift`, `scripts/check-package-graph.sh`
**Depends on**: T1
**Reuses**: the existing platform assertion at line 45 of the script
**Requirement**: MAC-01, MAC-20

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17" CODE_SIGNING_ALLOWED=NO -quiet` passes
- [ ] `xcodebuild build -scheme NottiSDKExtension -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES APPLICATION_EXTENSION_API_ONLY=YES` exits 0 (the design measured it)
- [ ] `scripts/check-package-graph.sh` passes on the tree and fails on a fixture with `.macOS(.v13)` and on one with only `.iOS(.v15)`
- [ ] The macOS build of `NottiSDK-Package` is expected red here (one error, `UIKit` module); the output is saved in the commit message body

**Tests**: script mutation
**Gate**: build
**Commit**: `build(spm): declare macOS 12 and expect it in the graph guard`

---

### T3: `NottiSDKVersion.platform` and per-platform `name`

**What**: `NottiSDKVersion.platform` (`"ios"`, `"macos"` under `#if os(macOS)`) in `NottiShared`; `name` takes the same value; `NottiCore.init(platform:)` defaults to `NottiSDKVersion.platform`; `NottiRuntime.makeCore` passes it explicitly.
**Where**: `Sources/NottiShared/NottiSDKVersion.swift`
**Depends on**: T2
**Reuses**: AD-024 `sdkName` override path
**Requirement**: MAC-07, MAC-08

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `platform` and `name` exist, `package` access, no `public` in `NottiShared`
- [ ] A test asserts the literal `"ios"` on iOS and `"macos"` under `#if os(macOS)`, as literals
- [ ] `NottiCore` default and `makeCore` use the constant; the `NottiRuntimeTests` and `NottiApiClientTests` literals still pass on iOS with no edit
- [ ] Gate passes; Shared count 14 plus the new tests, SDK count not lower than T1

**Tests**: unit
**Gate**: quick (`NottiSharedTests`, `NottiRuntimeTests`, `NottiApiClientTests`)
**Commit**: `feat(core): platform and sdk name per platform`

---

### T4: Guard UIKit imports and compile the In-App UI and image loader out on macOS

**What**: Replace each `import UIKit` outside the UI layer with `#if canImport(UIKit) import UIKit #elseif canImport(AppKit) import AppKit #endif`; wrap the body of the 8 `InApp/UI/*` files (not `NottiInAppStrings.swift`) and `InApp/Image/NottiInAppImageLoader.swift` in a file-level `#if canImport(UIKit)` ... `#endif`, indentation untouched. Mechanical, no logic change.
**Where**: `Sources/NottiSDK/InApp/UI/` and `Sources/NottiSDK/InApp/Image/NottiInAppImageLoader.swift` (file-level wrap), `import` lines of the other UIKit-importing files
**Depends on**: T2
**Reuses**: The Pass 1 and Pass 2 survey of the design
**Requirement**: MAC-01, MAC-21

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `git diff` of each wrapped file shows only the added first and last lines
- [ ] macOS located-error count equals the Pass 2 list of the design (22 or fewer) and is recorded in the commit body
- [ ] The iOS suite passes unchanged: counts equal T1 (full run)
- [ ] SwiftLint strict is clean

**Tests**: build
**Gate**: full (iOS part)
**Commit**: `refactor(inapp): compile the UIKit layer only where UIKit exists`

---

### T5: `NottiLifecycle` seam for lifecycle notification names

**What**: New `Platform/NottiLifecycle.swift` with `didFinishLaunching`, `didBecomeActive`, `didEnterBackground`, `willEnterForeground` (iOS only) and `willTerminate` (macOS only); `NottiCore.observeAppForeground/Background`, `NottiRuntime` (2 observers), `NottiDelegateInstaller` and `NottiFallbackDelegateAssigner` read it; `NottiCore`'s `#if canImport(UIKit)` becomes `#if canImport(UIKit) ... #elseif canImport(AppKit) ... #endif`. Net zero lines in `NottiCore.swift` (design C4).
**Where**: `Sources/NottiSDK/Platform/NottiLifecycle.swift`
**Depends on**: T4
**Reuses**: the observer bodies; `UIApplication` constants on iOS
**Requirement**: MAC-16, MAC-01

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] On iOS the observers register the same names as before (test compares each seam name to the literal `UIApplication` constant)
- [ ] The macOS branch compiles in the located-error count (no new error; count not higher than T4)
- [ ] `NottiCore.swift` line count not above its current value; SwiftLint file-length clean
- [ ] iOS full run: counts not lower than T1, no edited assertion

**Tests**: unit
**Gate**: quick (`NottiLifecycleTests`, `NottiCoreTests`, `NottiRuntimeTests`, `NottiDelegateInstallerTests`) then full at the end of the phase
**Commit**: `refactor(core): lifecycle notification names behind NottiLifecycle`

---

### T6: `NottiPlatformInfo` device OS and model

**What**: New `Platform/NottiPlatformInfo.swift`: the pure `osVersionString(major:minor:patch:)`, `deviceOS()` and `deviceModel()` (iOS closures moved verbatim, macOS `ProcessInfo` and `sysctlbyname("hw.model")`); `NottiPlatformProviders.live()` calls them.
**Where**: `Sources/NottiSDK/Platform/NottiPlatformInfo.swift`
**Depends on**: T4, T3
**Reuses**: the two existing provider closure bodies
**Requirement**: MAC-17, MAC-18

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] The pure helper tests pass on iOS (`14.0.0` to `14.0`, patch kept when non-zero)
- [ ] The iOS closures produce the same strings (test with the injected simulator values is not required: bodies are moved verbatim and the diff shows it)
- [ ] macOS branch has no serial, hardware UUID, user or host name; `hw.model` failure returns nil (code review item)
- [ ] macOS located-error count not higher than T5; iOS counts not lower

**Tests**: unit
**Gate**: quick (`NottiPlatformInfoTests`, `NottiCoreTests`)
**Commit**: `feat(platform): device os and model reads per platform`

---

### T7: Location permission and `.ephemeral` on macOS

**What**: `NottiLocationReader.updatePermission` accepts `.authorizedAlways` on macOS and `.authorizedWhenInUse || .authorizedAlways` on iOS; the `.ephemeral` case of the `permissionStatusProvider` switch and of `NottiPushPermissionAction.State.init` is `#if os(iOS)`.
**Where**: `Sources/NottiSDK/Platform/NottiLocationReader.swift`, `Sources/NottiSDK/Platform/NottiPlatformProviders.swift`, `Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift`
**Depends on**: T4
**Reuses**: existing switches
**Requirement**: MAC-01, MAC-18

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] iOS behavior identical: the `.ephemeral` mapping tests still pass
- [ ] The `authorizedWhenInUse` and `.ephemeral` errors are gone from the macOS count (the number drops by at least 1, and the hidden availability errors are listed in the commit body)
- [ ] The SDK still never requests location permission (code review item, SEGTEL-14)

**Tests**: unit
**Gate**: quick (`NottiPushPermissionActionTests`, `NottiFacadePermissionTests`)
**Commit**: `fix(platform): location and permission status on macOS`

---

### T8: Background activity and terminate flush

**What**: `NottiBackgroundTask`: iOS body unchanged inside `#if canImport(UIKit)`; macOS body with `ProcessInfo.beginActivity([.suddenTerminationDisabled, .automaticTerminationDisabled])` and an idempotent end. New `Core/NottiCore+Terminate.swift` (`#if os(macOS)`): `handleAppWillTerminate` runs the session end and then a bounded wait of `terminateFlushTimeout = 1.5` seconds; registered through `NottiLifecycle.willTerminate`.
**Where**: `Sources/NottiSDK/Platform/NottiBackgroundTask.swift`, `Sources/NottiSDK/Core/NottiCore+Terminate.swift`
**Depends on**: T5
**Reuses**: `TaskBox` pattern, `waitForPendingWork(timeout:)` (its doc comment updated: "also used by the macOS terminate flush")
**Requirement**: MAC-16

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] The five `NottiBackgroundTask` errors leave the macOS count
- [ ] The wait is bounded by a constant, never looped; the constant is one line (design D7)
- [ ] iOS: `NottiBackgroundTask.swift` iOS branch is byte-identical (diff shows only the wrapper), counts not lower
- [ ] No macOS test yet (written in T21); the commit body says so

**Tests**: build
**Gate**: quick (`NottiCoreTests`)
**Commit**: `feat(core): macOS background activity and bounded terminate flush`

---

### T9: Push adapter and manual API return type on macOS

**What**: `NottiPushAdapter.didReceiveRemoteNotification` and `manualDidReceiveRemoteNotification` return `UIBackgroundFetchResult` on iOS and `Void` on macOS; the public `Notti.Notifications.didReceiveRemoteNotification(_:)` and the ObjC `didReceiveRemoteNotification:` do the same (`@discardableResult`, same names and selector); `PUBLIC_SURFACE.txt` regenerated and reviewed.
**Where**: `Sources/NottiSDK/Delegates/NottiPushAdapter.swift`, `Sources/NottiSDK/Public/NottiNotifications+Delegate.swift`, `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `.specs/codebase/PUBLIC_SURFACE.txt`
**Depends on**: T4
**Reuses**: existing adapter logic
**Requirement**: MAC-10, MAC-15, MAC-22

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] iOS signature lines in `PUBLIC_SURFACE.txt` are unchanged; the only diff is the two macOS variant lines, listed in the commit body for the owner (design D4, C5)
- [ ] `scripts/check-public-surface.sh` passes after `--update` and the diff is reviewed
- [ ] The adapter tests pass on iOS unchanged
- [ ] The four `UIBackgroundFetchResult` errors leave the macOS count

**Tests**: unit
**Gate**: quick (`NottiPushAdapterTests`, `NottiPublicApiTests`, `NottiObjCBridgeTests`, `NottiSDKObjCTests`) plus `scripts/check-public-surface.sh`
**Commit**: `feat(api): macOS variant of the remote-notification forwarding call`

---

### T10: App delegate swizzler for `NSApplicationDelegate`

**What**: `NottiAppDelegateSwizzler`: the fetch variant, its typealiases and `swizzleFetchIfSafe` stay under `#if os(iOS)`; macOS swizzles `application:didReceiveRemoteNotification:` (`v@:@@`, no completion), adding it when the host lacks it, and forwards to the original with the same arguments. Token, failure, `setDelegate:` and SwiftUI handling are shared.
**Where**: `Sources/NottiSDK/Delegates/NottiAppDelegateSwizzler.swift`
**Depends on**: T9
**Reuses**: `swizzleToken`, `swizzleFailure`, `observe(delegate:)`
**Requirement**: MAC-09, MAC-11, MAC-15

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] iOS diff shows only `#if` wrappers around the fetch members; `NottiAppDelegateSwizzlerTests` pass unchanged
- [ ] The two swizzler errors leave the macOS count
- [ ] The macOS block calls the adapter once and the host original once (code review item; tested in T20)
- [ ] Doc comments name both delegate protocols

**Tests**: unit
**Gate**: quick (`NottiAppDelegateSwizzlerTests`)
**Commit**: `feat(delegates): swizzle NSApplicationDelegate callbacks on macOS`

---

### T11: Installer production environment and macOS provider wiring

**What**: `NottiDelegateInstaller.Environment.production()`, `currentApplicationDelegate`, `applicationIsActive` and `sharedApplication` use `NSApplication` on macOS (class reference and ObjC-runtime reads, never an instance at `+load`); `NottiPlatformProviders.live()` macOS body: `tokenProvider` calls `NSApp?.registerForRemoteNotifications()` on main, `appStateProvider` reads `NSApp?.isActive`, `beginBackgroundTask` and info closures from T6 and T8.
**Where**: `Sources/NottiSDK/Delegates/NottiDelegateInstaller.swift`, `Sources/NottiSDK/Platform/NottiPlatformProviders.swift`
**Depends on**: T10, T5, T6, T8
**Reuses**: the existing runtime-probe style; `NottiLifecycle`
**Requirement**: MAC-06, MAC-09, MAC-14

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `check-launch-hook-purity.sh` still passes (no instance, no I/O at install)
- [ ] `NSApp` nil does not instantiate an application (code review item; tested in T20)
- [ ] The `NottiDelegateInstaller` and `NottiPlatformProviders` errors leave the macOS count
- [ ] iOS: `NottiDelegateInstallerTests` and the launch hook proof (`check-hook-linked.sh spm`) pass unchanged

**Tests**: unit
**Gate**: quick (`NottiDelegateInstallerTests`) plus `scripts/check-launch-hook-purity.sh`
**Commit**: `feat(delegates): macOS installer environment and push registration`

---

### T12: In-App platform files and engine factory without UIKit types

**What**: `NottiPushPermissionAction` and `NottiInAppURLOpener`: the `.system` members and the `UIApplication` helpers move inside `#if canImport(UIKit)`; the types and pure logic compile on macOS. `NottiInAppEngine.live(defaults:clicks:presenter:)` takes a presenter protocol composition instead of the concrete `NottiInAppPresenter`, assigning `events` through a one-method protocol.
**Where**: `Sources/NottiSDK/InApp/Platform/NottiInAppURLOpener.swift`, `Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift`, `Sources/NottiSDK/InApp/Engine/NottiInAppHooks.swift`
**Depends on**: T4
**Reuses**: existing logic and tests
**Requirement**: MAC-21, MAC-13

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `check-no-url-open.sh` still passes with the two allowlisted files unchanged by path
- [ ] iOS tests (`NottiInAppURLOpenerTests`, `NottiPushPermissionActionTests`, `NottiInAppWiringTests`) pass unchanged
- [ ] The three `UIApplication` errors and the `NottiInAppHooks` error leave the macOS count

**Tests**: unit
**Gate**: quick (`NottiInAppURLOpenerTests`, `NottiPushPermissionActionTests`, `NottiInAppWiringTests`) plus `scripts/check-no-url-open.sh`
**Commit**: `refactor(inapp): platform effects only where UIKit exists`

---

### T13: Runtime for macOS: placeholder presenter, no In-App config

**What**: `NottiRuntime.shared` builds the engine with `NottiInAppPlaceholderPresenter` and passes no `pushPermissionPlatform` and no `urlOpenPlatform` on macOS; `start` skips `inAppEngine.configure` when `NottiPlatformInfo.supportsInApp` is false; the process observers use `NottiLifecycle` and the foreground observer is not registered on macOS.
**Where**: `Sources/NottiSDK/Runtime/NottiRuntime.swift`
**Depends on**: T12, T11, T5
**Reuses**: `NottiInAppPlaceholderPresenter`, `NottiLifecycle`
**Requirement**: MAC-21, MAC-16

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] iOS `shared` still builds the UIKit presenter and both `.system` platforms (code review item)
- [ ] `NottiRuntimeTests` and `NottiInAppWiringTests` pass unchanged on iOS
- [ ] The two `NottiRuntime` errors leave the macOS count; the located-error count is the residual list of T14

**Tests**: unit
**Gate**: quick (`NottiRuntimeTests`, `NottiInAppWiringTests`)
**Commit**: `feat(runtime): inert In-App engine and lifecycle seam on macOS`

---

### T14: macOS compile green, strict, both platforms

**What**: Clear every remaining located error (including the availability errors hidden by the first-order ones) so `NottiShared`, `NottiSDK`, `NottiSDKBootstrap` and `NottiSDKExtension` build for macOS with warnings as errors; confirm the pinned destination strings; build once for Mac Catalyst to record what `os(macOS)` and `canImport(UIKit)` do there. Record the final compile survey (zero) in the commit body and in `design.md`.
**Where**: `Sources/NottiSDK` (residual files named by the compiler)
**Depends on**: T6, T7, T8, T9, T10, T11, T12, T13
**Reuses**: the design survey
**Requirement**: MAC-01, MAC-02

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `xcodebuild build -scheme NottiSDK -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -quiet` exits 0; same for `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES`
- [ ] `grep -rE "import UIKit|UIApplication|UIDevice" Sources/NottiShared Sources/NottiSDKExtension` finds nothing; `grep -rnE "^import UIKit" Sources` finds only guarded imports
- [ ] The strict iOS builds (`generic/platform=iOS`, app and extension) still pass
- [ ] Full iOS run: counts equal T1
- [ ] The macOS destination string that resolves to one device is written in the Defaults table
- [ ] The Catalyst result is written in `design.md` (C-section), no code change for Catalyst

**Tests**: build
**Gate**: full (iOS tests, both strict builds, SwiftLint)
**Commit**: `build: NottiSDK compiles for macOS 12, strict`

---

### T15: Extension-unavailable attribute for macOS and the surface guard

**What**: Add `@available(macOSApplicationExtension, unavailable)` on the line after each of the 56 `@available(iOSApplicationExtension, unavailable)` sites (mechanical, indentation kept); `scripts/check-public-surface.sh` requires both attributes on top-level public types (the `ext_attr` check becomes two checks).
**Where**: `scripts/check-public-surface.sh`, `Sources/NottiSDK` (31 files, mechanical)
**Depends on**: T14
**Reuses**: the existing awk attribute scan
**Requirement**: MAC-05

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `PUBLIC_SURFACE.txt` and `SPI_SURFACE.txt` unchanged (attributes sit on their own lines)
- [ ] Fixtures: a public type with only the iOS attribute fails, with only the macOS attribute fails, with both passes
- [ ] iOS and macOS strict builds pass; counts not lower
- [ ] Gate: SwiftLint clean

**Tests**: script mutation
**Gate**: full
**Commit**: `feat(api): mark app-only API unavailable in macOS extensions`

---

### T16: Extension-safety, no-URL-open and launch-hook guards learn AppKit

**What**: `check-extension-safety.sh` bans `import AppKit`, `NSApplication` and `NSWorkspace` in `NottiShared` and `NottiSDKExtension`; `check-no-url-open.sh` bans `NSWorkspace` opens under `Sources/NottiSDK` and `Sources/NottiSDKBootstrap` (no allowlist entry); `check-launch-hook-purity.sh` bans `NSApplication` instance access (`NSApplication.shared`, `NSApp`) in `NottiBootstrap.m` and `NottiDelegateInstaller.swift`, allowing the class reference `NSApplication.self`.
**Where**: `scripts/check-extension-safety.sh`, `scripts/check-no-url-open.sh`, `scripts/check-launch-hook-purity.sh`
**Depends on**: T14
**Reuses**: existing pattern lists and fixture approach
**Requirement**: MAC-04, MAC-13

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] The three scripts pass on the tree
- [ ] One failing fixture per new token (`import AppKit`, `NSApplication`, `NSWorkspace` in the extension dirs; `NSWorkspace.shared.open(` in the SDK; `NSApplication.shared` in the installer) and one passing fixture for `NSApplication.self`
- [ ] The proofs are recorded in the commit body

**Tests**: script mutation
**Gate**: build
**Commit**: `ci(guards): extension safety, URL opening and launch hook learn AppKit`

---

### T17: Podspecs for macOS, package-graph pod checks, `pod lib lint`

**What**: `s.osx.deployment_target = '12.0'` in both podspecs; `check-package-graph.sh` podspec platforms expect `{"ios": "15.0", "osx": "12.0"}`; run `pod lib lint` for both pods on `ios,osx`, static frameworks, `--use-libraries` and dynamic frameworks.
**Where**: `NottiSDK.podspec`, `NottiSDKExtension.podspec`
**Depends on**: T14
**Reuses**: the design experiment (`NottiSDKExtension` linted for osx)
**Requirement**: MAC-03, MAC-20

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `pod lib lint NottiSDK.podspec --platforms=ios,osx`, `pod lib lint NottiSDKExtension.podspec --platforms=ios,osx` and both with `--use-libraries` pass
- [ ] The static and dynamic framework variants pass for the app pod on osx; the hosted `+load` count is checked in T24
- [ ] `scripts/check-package-graph.sh` passes and fails on a fixture with only `ios`, and on one where the extension pod gains `Sources/NottiSDK`
- [ ] The package name flag in `pod_target_xcconfig` is unchanged

**Tests**: build
**Gate**: build
**Commit**: `build(pods): macOS deployment target for both pods`

---

### T18: Privacy manifests for macOS

**What**: Confirm and edit the two `PrivacyInfo.xcprivacy` files for macOS: the `NottiSDK` manifest keeps UserDefaults `CA92.1` and every collected type (device model and OS are already `OtherDiagnosticData`); the comment block names macOS; add a unit test that parses both manifests on both platforms and asserts no category was added; archive the privacy report of a macOS build in `validation.md` during T27.
**Where**: `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy`
**Depends on**: T14
**Reuses**: `NottiLoggingPrivacyTests` manifest assertions, AD-005
**Requirement**: MAC-23

**Tools**:

- MCP: NONE
- Skill: `lgpd-skills:lgpd-data-mapping` (optional, for the data-flow note)

**Done when**:

- [ ] The manifest lists no new required-reason API and no new collected type; if T27 later finds one needed, this task reopens
- [ ] The comment names the macOS sources of `device_model` (`hw.model`) and `device_os` (`ProcessInfo`)
- [ ] The test passes on iOS now; it is first run on macOS in T19
- [ ] Gate passes

**Tests**: unit
**Gate**: quick (`NottiLoggingPrivacyTests`)
**Commit**: `docs(privacy): manifest comments and test for macOS`

---

### T19: Test target on macOS: gate UIKit-only tests, record the macOS baseline

**What**: Wrap the UIKit-only test files and lines in `#if canImport(UIKit)` (survey list in the design: In-App view, layout, presenter, window, image loader fixtures and tests, `UIBackgroundFetchResult` and `UIApplication` uses in the delegate tests and fixtures, `NottiObjCTests.m`); make `NottiRuntimeTests:128` and the other `"ios"` literals platform-aware; run the whole suite on `platform=macOS,arch=arm64` and record the counts.
**Where**: `Tests/NottiSDKTests` and `Tests/NottiSDKObjCTests` (mechanical gating of the files in the design survey)
**Depends on**: T14
**Reuses**: existing fixtures
**Requirement**: MAC-02, MAC-24

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Full iOS run: every bundle count equals T1 (no test dropped by the gating)
- [ ] Full macOS run passes; Shared, SDK, ObjC, Extension and ExtensionObjC counts recorded in `TESTING.md` as the macOS baseline
- [ ] No assertion edited other than the platform literals (diff reviewed)
- [ ] No test swizzles `NSApplication` or `UNUserNotificationCenter`

**Tests**: unit
**Gate**: full
**Commit**: `test: run the suite on macOS, gate the UIKit-only tests`

---

### T20: macOS delegate, adapter and registration tests

**What**: New macOS-only tests: fake `NSApplicationDelegate` classes for token, failure and remote notification with and without each host original (forwarded once, same arguments), double-swizzle guard, SwiftUI-internal skip and adaptor target; manual API parity and the ignored-while-active warning; `POST /devices` body `platform: "macos"` with the hex token and no web keys; PATCH `sdk_name: "macos"`, wrapper value wins; failure logged as `domain#code` only; `NSApp` nil does not create an application; the cold-start click is held by the buffer and replayed once (`takeInitialClick`).
**Where**: `Tests/NottiSDKTests/NottiAppDelegateSwizzlerMacTests.swift`
**Depends on**: T19, T10, T9
**Reuses**: `DelegateFixtures` pattern, `StubURLProtocol`, `LogSink`
**Requirement**: MAC-06, MAC-07, MAC-08, MAC-09, MAC-10, MAC-11, MAC-12, MAC-13, MAC-14, MAC-15, MAC-18

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [ ] Each listed row has a test; the platform literals are asserted as literals
- [ ] Sentinel sweep: no token, email, phone, external id, country, tag value or URL in any log line at `.verbose`
- [ ] Mutants killed (swizzler forwards zero times, forwards twice, adapter skipped) and recorded in `validation.md`
- [ ] macOS count above T19; iOS count unchanged

**Tests**: unit
**Gate**: macOS quick (`NottiSDKTests/NottiAppDelegateSwizzlerMacTests`, `NottiPushAdapterTests`, `NottiCoreTests`)
**Commit**: `test(macos): delegate integration, registration and click paths`

---

### T21: macOS lifecycle, terminate flush, device info and In-App inert tests

**What**: Tests for the observers (macOS names reach the same core paths; zero observers fails), terminate (ends the session once, bounded wait returns within the constant plus slack with a blocked work queue, resign then terminate is a no-op), background activity (begun once, ended once), device info (`hw.model` shape, OS string, nil on failure through an injected reader), and In-App inert (no request, no `notti_pending_inapp_events` write, `trackEvent` and listener do nothing).
**Where**: `Tests/NottiSDKTests/NottiCoreTerminateTests.swift`
**Depends on**: T19, T8, T13
**Reuses**: `NottiCoreTests` fakes (injected sleeper, HTTP, providers), isolated suites
**Requirement**: MAC-16, MAC-17, MAC-18, MAC-21, MAC-22

**Tools**:

- MCP: NONE
- Skill: `superpowers:test-driven-development`

**Done when**:

- [ ] Each acceptance row has a test; the terminate timing test uses an injected short timeout, not real 1.5 s waits
- [ ] A test fails if `observeAppForeground` or `observeAppBackground` register nothing on macOS (design C2)
- [ ] The In-App test asserts the engine has no config after `start` and no request is stubbed
- [ ] `PUBLIC_SURFACE.txt` regenerated shows only the T9 lines
- [ ] macOS count above T20; iOS unchanged

**Tests**: unit
**Gate**: full
**Commit**: `test(macos): lifecycle, terminate flush, device info and inert In-App`

---

### T22: Notification Service Extension on macOS

**What**: Run the existing 110 extension tests and 3 ObjC tests on the macOS destination; fix test-side platform assumptions only; add a test that `NottiSDKExtension` links no `AppKit` or `UIKit` symbol (`nm` over the built product); confirm the graph guard fails if the extension reaches `NottiSDK` on either platform.
**Where**: `Tests/NottiSDKExtensionTests/`
**Depends on**: T19, T17
**Reuses**: `JobTestCase`, `StubURLProtocol`, `MediaSamples`
**Requirement**: MAC-19, MAC-20, MAC-04

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] Extension 110 and ExtensionObjC 3 pass on macOS; iOS counts unchanged
- [ ] The `nm` check passes and a mutant that imports `AppKit` in the extension fails it
- [ ] `check-package-graph.sh` mutant (extension depends on `NottiSDK`) fails

**Tests**: unit
**Gate**: macOS full for the extension bundles
**Commit**: `test(extension): run the NSE suite on macOS`

---

### T23: CI runs macOS

**What**: `ci.yml`: the `test` job adds a macOS XCTest step (`platform=macOS,arch=arm64`, same retry flags), strict macOS device builds (app and extension API-only), and the `pod-lint` job lints `--platforms=ios,osx` (with and without `--use-libraries`); `checks` is unchanged (scripts are textual). Keep the pinned Xcode and runner notes.
**Where**: `.github/workflows/ci.yml`
**Depends on**: T19, T15, T16, T17
**Reuses**: the existing steps and flags
**Requirement**: MAC-24

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] The same commands run locally in the order of the workflow and pass (the local equivalent is the evidence, hosted CI may be blocked by billing)
- [ ] No step removed; no action version changed
- [ ] The `Flag retried tests` step also covers the macOS log

**Tests**: none
**Gate**: build
**Commit**: `ci: build and test on macOS`

---

### T24: Launch hook proof on macOS

**What**: `scripts/check-hook-linked.sh` gains `spm-macos`: Release build of a macOS consumer (`scripts/hook-consumer` gets a macOS target in its own generated project), run the binary directly, require `loadCount == installCount == 1`; `pod` mode accepts `--platforms=osx`; wire both into `ci.yml`.
**Where**: `scripts/check-hook-linked.sh`
**Depends on**: T14
**Reuses**: the iOS consumer and the `nm` check
**Requirement**: MAC-09, MAC-24

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `scripts/check-hook-linked.sh spm-macos` passes and fails on a consumer built without the SDK
- [ ] `scripts/check-hook-linked.sh pod` for osx finds `NottiBootstrap` in the pod product
- [ ] The iOS modes still pass
- [ ] `ci.yml` has the two steps

**Tests**: script mutation
**Gate**: full
**Commit**: `ci(hook): prove the launch hook runs and links on macOS`

---

### T25: macOS example app

**What**: `Example/project-mac.yml` (XcodeGen, separate from `project.yml`) with `NottiExampleMac` (AppKit, buttons for initialize, permission, login and logout, tag, take initial click, log) and a Notification Service Extension target; xcconfig keys as the iOS example (`NOTTI_APP_ID`, `NOTTI_CLIENT_KEY`, `NOTTI_HOST` from the git-ignored local file); entitlements file with `aps-environment` placeholder and the network client entitlement; generated project stays git-ignored.
**Where**: `Example/project-mac.yml`
**Depends on**: T14
**Reuses**: `Example/Config/Example.xcconfig`, the iOS example structure and log redaction helper
**Requirement**: MAC-25, MAC-26

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `xcodegen generate --spec project-mac.yml` and `xcodebuild build -scheme NottiExampleMac -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` pass
- [ ] No real key, app id or token is committed; the log shows key names only
- [ ] `check-example-config.sh` and `check-example-coverage.sh` still pass (the macOS example is outside their scope)
- [ ] Nothing generated is tracked by git

**Tests**: build
**Gate**: build
**Commit**: `feat(example): macOS example app and extension`

---

### T26: README, device checklist and testing docs for macOS

**What**: README: macOS install (SPM and CocoaPods), requirements, `aps-environment` and provisioning profile, the `NSApplicationDelegate` swizzling opt-out and manual forwarding (with the macOS `Void` return), inert In-App, session semantics (resign active, terminate), the backend minimum version, storage keys unchanged, Catalyst not supported. `docs/DEVICE_CHECKLIST.md`: macOS items D22 onward (signed app, permission prompt, token, push, click, cold-start click, silent push, quit while a session is open, SwiftUI adaptor, NSE image, sandbox and hardened runtime, privacy report). `TESTING.md`: macOS destination, counts, layers. README snippets stay equal to the example sources (`check-readme-snippets.sh`).
**Where**: `README.md`, `docs/DEVICE_CHECKLIST.md`, `.specs/codebase/TESTING.md`
**Depends on**: T25, T18
**Reuses**: existing README sections and checklist format
**Requirement**: MAC-25, MAC-26

**Tools**:

- MCP: NONE
- Skill: `readme-optimization` (optional)

**Done when**:

- [ ] Every MAC-25 item is in the README; every MAC-26 item has a checklist entry with steps and expected result
- [ ] `scripts/check-readme-snippets.sh` passes
- [ ] No claim of a clinical or delivery guarantee; no token, id or key in any example

**Tests**: none
**Gate**: build
**Commit**: `docs: macOS install, session semantics and device checklist`

---

### T27: Real-Mac verification and spike results

**What**: On a real Mac, with a signed `NottiExampleMac` and the backend `macos-platform` deployed to a reachable environment, run the macOS checklist items and spikes S1 to S10. An independent Verifier (a different agent or person than the implementer, with the spec and the checklist only) re-runs each item and records pass or fail with one line of evidence per item, without values.
**Where**: `docs/DEVICE_CHECKLIST.md`, `.specs/features/macos-support/validation.md`
**Depends on**: T20, T21, T22, T23, T24, T26
**Reuses**: the checklist format, `check-hook-linked.sh`
**Requirement**: MAC-06, MAC-09, MAC-11, MAC-13, MAC-14, MAC-15, MAC-16, MAC-19, MAC-23, MAC-26

**Tools**:

- MCP: NONE
- Skill: `tlc-spec-driven` (Validate flow)

**Done when**:

- [ ] The Mac appears in the dashboard as a `macos` Device and receives a push; `opened` and `clicked` are reported
- [ ] S1 (cold-start click) has a recorded result; if the click is lost, plan B of the design becomes a follow-up task before T28
- [ ] S2 (quit latency under 2 s with network down, session counters updated with network up), S3 (SwiftUI adaptor, originals forwarded), S4 (session count after Cmd-Tab), S6 (NSE image), S9 (privacy report) recorded
- [ ] The Verifier verdict (PASS or FAIL with the failing items) is in `validation.md`; a FAIL reopens the named task
- [ ] Owner decisions of the design (D4, C1, D7, D8, D10, D12, S3 method add) are recorded as confirmed or changed

**Tests**: none
**Gate**: full
**Commit**: `docs(validation): macOS device checklist and verifier verdict`

---

### T28: Release 0.3.0

**What**: `NottiSDKVersion.current`, `NottiSDK.podspec` and `NottiSDKExtension.podspec` to `0.3.0`; CHANGELOG `[0.3.0]` (macOS support, platform `macos`, no breaking change, the macOS-only `Void` variant, backend minimum version, Catalyst not supported); `ROADMAP.md` and `STATE.md` closed. Tag `0.3.0`, GitHub Release and `pod trunk push` (`NottiSDK`, then `NottiSDKExtension`) are Julio's, only after the backend `macos-platform` is deployed and T27 passed; after 2026-12-02 follow AD-022 plan B.
**Where**: `Sources/NottiShared/NottiSDKVersion.swift`, `NottiSDK.podspec`, `NottiSDKExtension.podspec`, `CHANGELOG.md`
**Depends on**: T27
**Reuses**: the 0.2.0 release flow, `scripts/check-version.sh`
**Requirement**: MAC-24

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `scripts/check-version.sh` passes with `0.3.0` in the three places
- [ ] Full gate green on both platforms, `pod lib lint` for both pods on `ios,osx`
- [ ] CHANGELOG date is the release date; README pins the minor version
- [ ] The backend deploy is confirmed in the PR description before the tag is proposed
- [ ] Tag and publish are not done by the agent

**Tests**: none
**Gate**: full
**Commit**: `chore: release 0.3.0`
