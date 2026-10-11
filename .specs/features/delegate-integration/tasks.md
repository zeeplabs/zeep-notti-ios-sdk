# Delegate Integration Tasks

**Design**: `.specs/features/delegate-integration/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: `public-api` done (facade, runtime, handler, 356 tests)
**Status**: Execute done (T1-T14), Verifier pending

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Generated from codebase, project guidelines and spec. Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: 356 tests (Shared 14, SDK 337, ObjC 4, Ext 1). Counts below are minimums per task; the executor records the exact number.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| `NottiSwizzlingConfiguration` | unit | Missing, `false`, `true`, string and number values; invalid value warns once | `Tests/NottiSDKTests/NottiSwizzlingConfigurationTests.swift` | `xcodebuild test ... -only-testing:NottiSDKTests/NottiSwizzlingConfigurationTests` |
| `NottiMethodSwizzler` | unit | Implemented, inherited and absent methods; repeat install; stacked swizzlers; subclass of a swizzled class; failure path | `Tests/NottiSDKTests/NottiMethodSwizzlerTests.swift` | same, `NottiMethodSwizzlerTests` |
| `NottiNotificationHandler.handleSilentPush` | unit | Silent vs visible vs no `aps`; dedupe by `delivery_id`; report queued | `Tests/NottiSDKTests/NottiNotificationHandlerTests.swift` | same |
| `NottiPushAdapter` | unit | Token, failure, willPresent (D2 options), didReceive (incl. F7), silent path, manual guard | `Tests/NottiSDKTests/NottiPushAdapterTests.swift` | same |
| `NottiAppDelegateSwizzler` | unit | Fake app delegates: modern, legacy only, none; original called once | `Tests/NottiSDKTests/NottiAppDelegateSwizzlerTests.swift` | same |
| `NottiNotificationCenterSwizzler`, fallback delegate | unit | Fake delegates with/without methods; completion exactly once; delegate swap; end-of-launch fallback | `Tests/NottiSDKTests/NottiNotificationCenterSwizzlerTests.swift` | same |
| `NottiDelegateInstaller`, `NottiBootstrap` | unit + CI build | Idempotent install, opt-out, hook ran (`loadCount`, `installCount`) | `Tests/NottiSDKTests/NottiDelegateInstallerTests.swift` | same, plus the CI consumer build (T12) |
| Manual API (Swift + ObjC) | unit | Each method reaches the adapter; ignored while swizzling is active | `Tests/NottiSDKTests/NottiPublicApiTests.swift`, `Tests/NottiSDKObjCTests/` | same, plus build |
| Cross-cutting (PII, deep link, cold start) | unit | Sentinel sweep over the new paths; exact `data` link; `takeInitialClick` once | `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`, `NottiDeepLinkTests.swift` | same |
| Packaging and scripts (`Package.swift`, podspec, `check-package-graph.sh`, `check-no-url-open.sh`, CI) | none | Run each script against a passing and a failing tree | - | the scripts, `pod lib lint` |
| Docs (`traceability.md`, specs) | none | Every DEL-xx mapped to a test | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially.

## Gate Check Commands

> Generated from codebase (`.github/workflows/ci.yml`, `.specs/codebase/TESTING.md`). Xcode 27 note: run `xcodebuild test` through the watchdog in the scratchpad (a failing run does not terminate), and do not pipe `xcodebuild` into `grep`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | After T9, T11 and T14 | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + the guard scripts + `pod lib lint NottiSDK.podspec --platforms=ios` |
| Build | Build-only checks and phase completion | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |

---

## Rules (apply to every task)

1. New code, so `write-swift` and `swift-concurrency` guidance applies, but in Swift 5 mode (AD-002): no actors, no `AsyncStream`.
2. Do not edit ported core files (`NottiCore`, `NottiApiClient`, `NottiDeviceStore`, `NottiEventStore`, `NottiEventBuffer`). `NottiNotificationHandler` gains one method (T3) and existing methods stay untouched.
3. Every new Swift type under `Sources/NottiSDK` that touches UIKit or the OS delegates is `@available(iOSApplicationExtension, unavailable)`.
4. Swizzling mutates global class state: every test builds its own fake class (`objc_allocateClassPair`, unique name) and its own `NottiMethodSwizzler` registry. No unit test swizzles `UIApplication` or `UNUserNotificationCenter` themselves except the installer test in T8, which uses injected targets.
5. Test fixtures are synthetic (`example.invalid`, `fixture`). No log line contains a token, title, body, `data` value, `notification_id`, `delivery_id` or `localizedDescription`.
6. The `+load` hook does no I/O, creates no UIKit object, and does not read `NottiRuntime.shared.core` (DEL-14).
7. Each task is one commit, conventional style, with no AI attribution.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe).

### Phase 1: Building blocks

```
T1
T2
T3
```

No edges: independent. They run in this order.

### Phase 2: Adapter and swizzlers

```
T3 ──→ T4
T2 ──→ T5
T4 ──→ T5
T2 ──→ T6
T4 ──→ T6
T4 ──→ T7
T6 ──→ T7
```

### Phase 3: Installer and packaging

```
T1 ──→ T8
T5 ──→ T8
T6 ──→ T8
T7 ──→ T8
T8 ──→ T9
```

### Phase 4: Public API and proofs

```
T4 ──→ T10
T8 ──→ T10
T10 ──→ T11
T9 ──→ T12
T6 ──→ T13
T8 ──→ T13
T11 ──→ T14
T12 ──→ T14
T13 ──→ T14
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14.

---

## Task Breakdown

### T1: `NottiSwizzlingConfiguration`

**What**: Reads the opt-out from the `Info.plist` key `NottiDisableSwizzling`. `isEnabled` is false only for Boolean `true`. A non-Boolean value means on and sets a warning flag. Takes an injected dictionary; the default is `Bundle.main.infoDictionary`.
**Where**: `Sources/NottiSDK/Delegates/NottiSwizzlingConfiguration.swift`, `Tests/NottiSDKTests/NottiSwizzlingConfigurationTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: DEL-02

**Done when**:

- [x] Missing key, `false`, and `nil` dictionary give `isEnabled == true`
- [x] Boolean `true` gives `isEnabled == false`
- [x] A string or number value gives `isEnabled == true` and the invalid-value flag
- [x] No file I/O beyond reading the injected dictionary
- [x] Test count: SDK +5 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiSwizzlingConfigurationTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): swizzling opt-out configuration`

---

### T2: `NottiMethodSwizzler`

**What**: Replace one instance method and chain to the previous implementation, at most once per (implementing class, selector). Walks the superclass chain with `class_copyMethodList` to find the implementing class, adds the method on the given class when none does, uses `class_replaceMethod` with an `imp_implementationWithBlock` block, and keeps the previous IMP in an instance-owned registry. Returns false and logs at `.error` (no values) on failure.
**Where**: `Sources/NottiSDK/Delegates/NottiMethodSwizzler.swift`, `Tests/NottiSDKTests/NottiMethodSwizzlerTests.swift`
**Depends on**: None
**Reuses**: `NottiLogger`
**Requirement**: DEL-07, DEL-13

**Done when**:

- [x] Implemented method: replacement runs, original runs once per call
- [x] Inherited method: the superclass implementation is swizzled once and a subclass call is observed once, not twice
- [x] Absent method: the SDK implementation is added and the previous IMP passed to the block is nil
- [x] Installing the same (class, selector) twice is a no-op (same counts, same order)
- [x] Two stacked swizzlers (a second one installed after) call every original exactly once
- [x] Failure path returns false and logs one `.error` line with no values
- [x] Test count: SDK +7 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiMethodSwizzlerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): method swizzler with idempotent chaining`

---

### T3: `NottiNotificationHandler.handleSilentPush`

**What**: Add `handleSilentPush(userInfo:)`. A payload is silent when it has `aps` and no `aps.alert`; everything else returns without doing anything. It emits `received` with identifier `delivery_id` when present (the buffer dedupes by `received:<identifier>`), then calls the existing `enqueueIfReportable(..., type: received)`. Existing methods are not edited.
**Where**: `Sources/NottiSDK/Runtime/NottiNotificationHandler.swift`, `Tests/NottiSDKTests/NottiNotificationHandlerTests.swift`
**Depends on**: None
**Reuses**: `NottiPayloadKeys`, `parseUserInfo`, `eventBuffer`, `eventStore`
**Requirement**: DEL-15, DEL-17

**Done when**:

- [x] A silent payload emits one `received` and queues one report when both ids are non-empty
- [x] A payload with `aps.alert` and `content-available: 1` emits nothing and queues nothing
- [x] A payload without `aps` emits nothing and queues nothing
- [x] Two silent pushes with the same `delivery_id` reach a listener once
- [x] Empty `delivery_id` or `notification_id` queues no report
- [x] Existing handler tests are unchanged and green
- [x] Test count: SDK +6 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiNotificationHandlerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(handler): silent push reporting`

---

### T4: `NottiPushAdapter`

**What**: The single place that turns OS inputs into runtime and handler calls: `didRegister(deviceToken:)`, `didFail(error:)`, `willPresent(userInfo:identifier:) -> UNNotificationPresentationOptions` (reports, returns `[.banner, .list, .sound, .badge]` for a Notti push, i.e. a remote push with a non-empty `notification_id`, and `[]` otherwise), `didReceive(actionIdentifier:userInfo:identifier:)`, `didReceiveRemoteNotification(userInfo:) -> UIBackgroundFetchResult` (calls `handleSilentPush`, returns `.noData`). Also holds the manual-call guard: a `swizzlingActive` flag read from `NottiSwizzlingState`; manual entry points log one `.warn` and return when it is set.
**Where**: `Sources/NottiSDK/Delegates/NottiPushAdapter.swift`, `Tests/NottiSDKTests/NottiPushAdapterTests.swift`
**Depends on**: T3
**Reuses**: `NottiRuntime`, `NottiNotificationHandler`, `NottiLogger`
**Requirement**: DEL-03, DEL-04, DEL-05, DEL-08, DEL-09, DEL-11

**Done when**:

- [x] `didRegister` reaches `NottiRuntime.onApnsToken` once; `didFail` reaches `onApnsRegistrationFailed` once and logs `domain#code` only
- [x] `willPresent` returns the D2 options for a Notti push and `[]` for a local or non-Notti notification, and reports only the former
- [x] `didReceive` with an empty `delivery_id` queues no report (closes STATE F7)
- [x] A body tap queues one `opened` and one `clicked`; a dismiss queues none
- [x] A local notification (no `aps`) is neither parsed nor reported
- [x] With the guard set, each manual entry point processes nothing and logs one `.warn` with no payload values
- [x] Test count: SDK +12 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiPushAdapterTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): push adapter for OS callbacks`

---

### T5: `NottiAppDelegateSwizzler`

**What**: Swizzle `UIApplicationDelegate`: `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegisterForRemoteNotificationsWithError` and `didReceiveRemoteNotification:fetchCompletionHandler:`. Swizzles the class of a given delegate and, separately, `UIApplication.setDelegate:` so a later delegate is reached. Never adds the fetch variant when the host implements only the legacy `application:didReceiveRemoteNotification:`. Calls the host original with the same arguments; with no original on the fetch variant, completes once with `.noData`. Skips SwiftUI's internal delegate with one `.warn`.
**Where**: `Sources/NottiSDK/Delegates/NottiAppDelegateSwizzler.swift`, `Tests/NottiSDKTests/NottiAppDelegateSwizzlerTests.swift`
**Depends on**: T2, T4
**Reuses**: `NottiMethodSwizzler`, `NottiPushAdapter`
**Requirement**: DEL-03, DEL-15, DEL-16

**Done when**:

- [x] Fake delegate with all three methods: adapter called once and each original called once per callback
- [x] Fake delegate with none: the SDK implementation is added, the token reaches the adapter, the fetch variant completes once with `.noData`
- [x] Fake delegate with only the legacy method: the fetch variant is not added and the legacy method keeps being called
- [x] A subclass of a swizzled delegate class is observed once per callback
- [x] The SwiftUI-internal delegate case warns once and swizzles nothing (against a fake with that class name check abstracted behind an injected predicate)
- [x] Test count: SDK +9 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiAppDelegateSwizzlerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): app delegate swizzler`

---

### T6: `NottiNotificationCenterSwizzler`

**What**: Swizzle `userNotificationCenter(_:willPresent:withCompletionHandler:)` and `didReceive` on a given delegate class, plus `-[UNUserNotificationCenter setDelegate:]`, so each newly assigned delegate class is swizzled (idempotent) before the original setter runs. `willPresent`: report through the adapter, then call the host original with the host's completion; with no original, call the completion once with the adapter's options. `didReceive`: report, then call the host original (its completion), or complete once when none.
**Where**: `Sources/NottiSDK/Delegates/NottiNotificationCenterSwizzler.swift`, `Tests/NottiSDKTests/NottiNotificationCenterSwizzlerTests.swift`
**Depends on**: T2, T4
**Reuses**: `NottiMethodSwizzler`, `NottiPushAdapter`
**Requirement**: DEL-04, DEL-05, DEL-06, DEL-07, DEL-11

**Done when**:

- [x] Host implements `willPresent`: the host's completion reaches the OS and the SDK never calls it
- [x] Host lacks `willPresent`: exactly one completion; Notti push gets `[.banner, .list, .sound, .badge]`, other notification gets `[]`
- [x] `didReceive` completes exactly once, by the host when it implements it and by the SDK otherwise
- [x] Swapping the delegate repeatedly does not grow the chain: one observation per callback
- [x] Another swizzler stacked on top: every original runs once
- [x] Local notifications are forwarded untouched and not reported
- [x] Test count: SDK +9 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiNotificationCenterSwizzlerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): notification center swizzler`

---

### T7: `NottiNotificationCenterDelegate` fallback

**What**: A small `NSObject` implementing `UNUserNotificationCenterDelegate` through the adapter, assigned as the center's delegate at the end of launch only when `delegate == nil` and swizzling is on. The "end of launch" trigger is `UIApplication.didFinishLaunchingNotification`, observed through an injectable `NotificationCenter` and an injectable center, so the test posts it. A delegate the host sets later goes through the swizzled setter (T6).
**Where**: `Sources/NottiSDK/Delegates/NottiNotificationCenterDelegate.swift`, `Tests/NottiSDKTests/NottiNotificationCenterSwizzlerTests.swift`
**Depends on**: T4, T6
**Reuses**: `NottiPushAdapter`, `NottiNotificationCenterSwizzler`
**Requirement**: DEL-06, DEL-02

**Done when**:

- [x] Fake center with a nil delegate gets the fallback after the launch notification
- [x] A fake center whose delegate was set before the launch notification is left untouched
- [x] Opt-out (disabled configuration) never assigns it
- [x] The fallback calls the adapter and completes once, with the D2 options for `willPresent`
- [x] Test count: SDK +5 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiNotificationCenterSwizzlerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(delegates): fallback notification center delegate`

---

### T8: `NottiDelegateInstaller` and `NottiSwizzlingState`

**What**: `@objc(NottiDelegateInstaller) final class` with `@objc static func install()`, idempotent, that reads the configuration (T1), and when on installs the app-delegate swizzler (T5), the notification-center swizzler (T6) and the fallback observer (T7), then sets `NottiSwizzlingState.isActive`. When off it logs one `.info` line and installs nothing. `Notti.initialize` calls `install()` again. Targets and configuration are injectable; the test uses fakes, never the real `UIApplication`.
**Where**: `Sources/NottiSDK/Delegates/NottiDelegateInstaller.swift`, `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiDelegateInstallerTests.swift`
**Depends on**: T1, T5, T6, T7
**Reuses**: all delegate components
**Requirement**: DEL-01, DEL-02, DEL-06, DEL-07

**Done when**:

- [x] Opt-out: no selector changed, no delegate assigned, one `.info` log line, `isActive == false`
- [x] Enabled: `install()` twice changes nothing the second time (one observation per callback)
- [x] `isActive` becomes true only after a successful install
- [x] `Notti.initialize` triggers `install()` without a second swizzle (existing facade tests stay green)
- [x] The installer does no network, file or UserDefaults I/O (asserted by a stubbed HTTP client and an isolated suite staying empty)
- [x] Test count: SDK +6 minimum
- [x] Gate passes: full

**Tests**: unit
**Gate**: full
**Commit**: `feat(delegates): installer with idempotent install`

---

### T9: `NottiSDKBootstrap` ObjC target and packaging

**What**: Add the ObjC target `NottiSDKBootstrap` (`NottiBootstrap.m`, `include/NottiBootstrap.h`): `+load` looks up `NottiDelegateInstaller` by name and sends `install`, plus read-only `loadCount` and `installCount` class properties. `Package.swift`: new target, a dependency of `NottiSDK` only. Podspec `Core`: `source_files` gains `Sources/NottiSDKBootstrap/**/*.{h,m}` and `public_header_files = Sources/NottiSDKBootstrap/include/*.h`. `check-package-graph.sh`: allowlist updated, plus an assertion that `NottiShared`, `NottiSDKExtension` and the `Extension` subspec never reach the bootstrap target. A Swift reference to `NottiBootstrap` is guarded with `#if canImport(NottiSDKBootstrap)` (the pod is one module).
**Where**: `Sources/NottiSDKBootstrap/`, `Package.swift`, `NottiSDK.podspec`, `scripts/check-package-graph.sh`, `Tests/NottiSDKTests/NottiDelegateInstallerTests.swift`
**Depends on**: T8
**Reuses**: spike result in `design.md`
**Requirement**: DEL-01, DEL-12, DEL-14

**Done when**:

- [x] A package test asserts `NottiBootstrap.loadCount >= 1` and `installCount >= 1` in the test process
- [x] `check-package-graph.sh` passes on the new tree, and fails when the Extension subspec or `NottiSDKExtension` is made to depend on the bootstrap target (verified on a throwaway edit)
- [x] `pod lib lint NottiSDK.podspec --platforms=ios` passes for all subspecs
- [x] The `+load` body contains no UIKit, no I/O and no `NottiRuntime` access (reviewed against DEL-14)
- [x] Strict device builds of SDK and NSE pass (`NottiSDKExtension` is unchanged)
- [x] Test count: SDK +2 minimum
- [x] Gate passes: full

**Tests**: unit
**Gate**: full
**Commit**: `feat(delegates): ObjC launch hook target and packaging`

---

### T10: Manual forwarding API (Swift)

**What**: New extension on `Notti.Notifications`: `didRegisterForRemoteNotifications(deviceToken:)`, `didFailToRegisterForRemoteNotifications(error:)`, `didReceiveRemoteNotification(_:) -> UIBackgroundFetchResult`, `willPresent(_:) -> UNNotificationPresentationOptions`, `didReceive(_:)`. The `UNNotification` / `UNNotificationResponse` overloads extract `userInfo`, `request.identifier` and `actionIdentifier` and call the adapter's manual entry points. Update `PUBLIC_SURFACE.txt` in the same commit.
**Where**: `Sources/NottiSDK/Public/NottiNotifications+Delegate.swift`, `.specs/codebase/PUBLIC_SURFACE.txt`, `Tests/NottiSDKTests/NottiPublicApiTests.swift`
**Depends on**: T4, T8
**Reuses**: `NottiPushAdapter`
**Requirement**: DEL-08, DEL-09, DEL-12

**Done when**:

- [x] With swizzling inactive, each of the five methods reaches the adapter and produces the same observable result as the swizzled path
- [x] With swizzling active, each call is ignored and logs one `.warn`
- [x] Called before `initialize`, the manual API buffers like the swizzled path
- [x] `check-public-surface.sh` passes with the new entries, and new types carry `@available(iOSApplicationExtension, unavailable)`
- [x] Test count: SDK +8 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiPublicApiTests` and `scripts/check-public-surface.sh`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(public-api): manual notification forwarding`

---

### T11: Objective-C mirror of the manual API

**What**: Add the five methods to `NottiNotifications` (ObjC name) in `Public/ObjC/NottiObjC.swift` with `@objc` signatures, and exercise them from the ObjC test target. Update `PUBLIC_SURFACE.txt`.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `.specs/codebase/PUBLIC_SURFACE.txt`
**Depends on**: T10
**Reuses**: existing ObjC layer
**Requirement**: DEL-12

**Done when**:

- [x] An `.m` test calls each of the five methods and compiles in CI
- [x] Surface file updated, script passes
- [x] Test count: ObjC +2 minimum, SDK +2 minimum
- [x] Gate passes: full

**Tests**: unit
**Gate**: full
**Commit**: `feat(public-api): Objective-C manual forwarding`

---

### T12: CI proof of the hook and the URL-open ban

**What**: (a) CI step on the macOS job that builds a scratch SPM consumer (an `executableTarget` depending on the package) in Release for the simulator and asserts `loadCount == 1` and `installCount == 1`; keep the consumer under `scripts/hook-consumer/` so it is versioned. (b) `pod lib lint --no-clean` plus an `nm` check for `_OBJC_CLASS_$_NottiBootstrap` in the built pod product. (c) `scripts/check-no-url-open.sh`: fails when `Sources/NottiSDK` references `UIApplication.shared.open`, `.open(_:options` or `openURL`; wired into the `checks` job. Verify (c) against a passing and a failing tree.
**Where**: `scripts/hook-consumer/`, `scripts/check-hook-linked.sh`, `scripts/check-no-url-open.sh`, `.github/workflows/ci.yml`, `AGENTS.md`
**Depends on**: T9
**Reuses**: the spike consumer approach recorded in `design.md`
**Requirement**: DEL-01, DEL-18

**Done when**:

- [x] The consumer check passes locally in Release and fails when the bootstrap target is removed from `NottiSDK`'s dependencies (throwaway edit)
- [x] The pod `nm` check passes locally
- [x] `check-no-url-open.sh` passes on the tree and fails on a throwaway `UIApplication.shared.open` line
- [ ] CI green on the draft PR for all jobs, including the new steps (pending: CI has not run; the three checks were proved locally only)
- [x] `AGENTS.md` lists the new scripts

**Tests**: none
**Gate**: build
**Commit**: `ci: prove the launch hook is linked and ban URL opening`

---

### T13: Deep link, cold start and PII proofs

**What**: Tests that go through the swizzled path with fakes: (a) a body tap with `https://example.invalid/fixture` in `data` returns it byte for byte through the `clicked` listener and `takeInitialClick()`, queues one `opened` and one `clicked`, and opens no URL; (b) cold start: events delivered with no core, `takeInitialClick()` returns the payload once then `nil`, and the store keeps the queued reports; (c) extend the PII sentinel test over the adapter, the swizzlers and the silent path at `.verbose`.
**Where**: `Tests/NottiSDKTests/NottiDeepLinkTests.swift`, `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`
**Depends on**: T6, T8
**Reuses**: fakes from T5 and T6, existing sentinel helper
**Requirement**: DEL-10, DEL-13, DEL-18

**Done when**:

- [x] Warm and cold-start deep link values match exactly, with no URL-open call recorded by an injected opener spy
- [x] `takeInitialClick()` returns the click once and `nil` afterwards, with no core initialized
- [x] No sentinel (token, title, body, `data` value, ids, error description) appears in any log line, including the install-failure and manual-guard lines
- [x] Test count: SDK +6 minimum
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiDeepLinkTests` and `NottiLoggingPrivacyTests`

**Tests**: unit
**Gate**: quick
**Commit**: `test(delegates): deep link, cold start and PII proofs`

---

### T14: Traceability, docs and full gate

**What**: Write `.specs/features/delegate-integration/traceability.md` mapping each DEL-xx to its tests. Update `TESTING.md` (new layers and files), `STATE.md` (close F7, record the decision for D1, D2 and the opt-out key, keep N7), `ROADMAP.md` and spec statuses. Run the full gate.
**Where**: `.specs/features/delegate-integration/traceability.md`
**Depends on**: T11, T12, T13
**Reuses**: public-api `traceability.md` layout
**Requirement**: DEL-01..DEL-18

**Done when**:

- [x] Every DEL-xx has at least one named test, or a stated reason (CI scripts point to T12)
- [x] `validate_tasks.py`, `validate_spec.py` and `validate_state.py` exit 0 (`validate_state.py` with no argument; with `delegate-integration` it exits 1 until the Verifier writes `validation.md`, which is expected)
- [x] Full gate green: tests, SwiftLint 0, five guard scripts, `pod lib lint` (all and Extension), strict device builds; test count at least 356 plus the minimums above
- [x] `STATE.md` Current Work says Execute done and Verifier pending
- [x] Independent Verifier PASS (`validation.md`, written by the Verifier, not the executor) (round 2 PASS, 2026-10-11)

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): delegate-integration traceability and gate`

---

## Granularity Check

Each task touches one component and its test file, with these deliberate exceptions: T8 (installer plus the one-line `initialize` call, because the call proves idempotency), T9 (ObjC target and the packaging that makes it link, because neither works alone and the graph script must change in the same commit), T12 (three scripts that are all CI proofs, no production code) and T14 (docs).

## Diagram-Definition Cross-Check

The diagrams above match the `Depends on` fields. T1 to T3 have no edges. T7 depends on T6 because the fallback relies on the swizzled setter for later delegates. T13 depends on T6 and T8, not on T12, so a CI problem does not block the proof tests.

## Test Co-location Validation

Every task that adds code ships its tests in the same commit (AGENTS.md). Tasks with `Tests: none` are the CI scripts and docs, matching the Test Coverage Matrix.

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| DEL-01 | T8, T9, T12 |
| DEL-02 | T1, T7, T8 |
| DEL-03 | T4, T5 |
| DEL-04 | T4, T6 |
| DEL-05 | T4, T6 |
| DEL-06 | T6, T7, T8 |
| DEL-07 | T2, T6, T8 |
| DEL-08 | T4, T10 |
| DEL-09 | T4, T10 |
| DEL-10 | T13 |
| DEL-11 | T4, T6 |
| DEL-12 | T9, T10, T11 |
| DEL-13 | T2, T13 |
| DEL-14 | T9 |
| DEL-15 | T3, T4, T5 |
| DEL-16 | T5 |
| DEL-17 | T3 |
| DEL-18 | T12, T13 |

18 requirements, 18 mapped to tasks.
