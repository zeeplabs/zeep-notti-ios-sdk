# Pre-release Fixes Specification

## Problem Statement

The pre-release review of `main` @ `2a38261` (2026-10-25) found one public-contract defect, two medium defects, four low defects and four documentation nits before `0.1.0` is tagged. The worst one breaks the M2 plan: the Objective-C facade class is registered as `Notti`, the same runtime name as `react-native-notti`'s TurboModule class (`ios/Notti.h`, `@interface Notti`), so an app that links both fails to link (static) or gets an undefined class (dynamic). Julio approved the scope below on 2026-10-25. Each finding was re-checked in the code before it was specified here.

## Goals

- [ ] No Objective-C class of `NottiSDK` shares a runtime name with a class of `react-native-notti` 0.8.0 (`Notti`, `NottiImpl`, `NottiBridge`, `NottiPushDelegate`).
- [ ] No identity call is lost silently: a `login`, tag or subscription call made before `initialize` logs one fixed warning, and the docs say what is dropped.
- [ ] An app delegate that another SDK isa-swizzles (GoogleUtilities, KVO) is observed once per callback, whatever the order of installs and however often `initialize` runs.
- [ ] The four low defects are fixed in new code (facade, runtime, engine, UI, ObjC layer) with a test each; ported core files stay RN 0.8.0-identical (AD-002).

## Out of Scope

| Feature | Reason |
| --- | --- |
| Queuing a pre-`initialize` `login` durably | Core behavior (RN parity, AD-002); needs a post-M1 spec aligned with RN |
| Making `opensInAppURLs` sticky across `initialize` calls | Needs `Bool?` or a new initializer in `Notti.Options` (public API shape change); the rule below keeps the shape |
| The same isa-swizzle handling for the `UNUserNotificationCenter` delegate | No evidence that GoogleUtilities isa-swizzles it (FIRMessaging method-swizzles, which the registry handles); recorded as a todo |
| Image pixel-size cap (review N5), `NSProxy` app delegates (review N6) | Recorded as todos in `STATE.md`, no code |
| The stale device id shared across app ids in the core (review N7, L2 core analogue) | RN parity in ported code (AD-002) |
| Renaming `NottiUser`, `NottiNotifications`, `NottiInAppMessages`, `NottiSubscription`, `NottiLogLevel` | None collides with an RN 0.8.0 ObjC class (checked: RN declares `Notti`, `NottiImpl`, `NottiBridge`, `NottiPushDelegate`; its Swift classes without `@objc(name)` get mangled runtime names) |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| New ObjC name of the facade class | `NottiSDK` (Swift name `NottiObjC` unchanged); the other ObjC names stay | Julio's scope (AD-021). Module and class names are separate namespaces in Objective-C, so `@import NottiSDK;` plus `[NottiSDK login:]` compiles; the ObjC test target proves it under SPM | y (Julio, 2026-10-25) |
| Pre-`initialize` warning text | One fixed `.warn` per dropped call, naming only the method (`login`, `addTags`, `removeTags`, `setSubscription`), never a value | No PII in logs (AGENTS.md); per-method text tells the integrator which call to move | y (scope: "one fixed .warn line, no user values") |
| What counts as "before initialize" for the warning | `NottiFacade.activeConfig == nil` (no valid `initialize` accepted yet) | The core drops the same calls exactly then (`apiClient == nil`) | y |
| Logical class of a delegate | The result of `-class` when it is a proper superclass of the isa class; otherwise the isa class | GoogleUtilities and KVO override `-class` to hide their dynamic subclass; an unrelated answer (an `NSProxy` forwarding `-class`) is ignored | n (proposed; device check with Firebase still open) |
| Which class to swizzle behind a dynamic subclass | Per selector: skip the isa class when the logical class's implementation of that selector is already the SDK's; otherwise swizzle the isa class only, never the logical class too | When the SDK came first, the dynamic subclass captured the SDK's block, so the chain already runs through it. When the dynamic subclass came first, it captured the host original, so only the isa class reaches the callback, and swizzling the logical class too would double a subclass that calls through dynamically | n (proposed) |
| Late observe frequency | The late look at existing delegates runs on the first non-launch-hook install only (the first `initialize`) | The `setDelegate:` hooks see every later assignment; repeating the look on every `initialize` is what reached the dynamic subclass | y (scope: "observe only once") |
| Thread of the late observe (N3) | On the main thread: synchronously when `initialize` runs on main, else one `DispatchQueue.main.async` | `UIApplication.delegate` is main-thread-only; async never blocks a caller that holds the main thread | y (scope: "fix if small and safe") |
| L2 scope of the registration hook | The engine accepts a core's registration only when the In-App config the core was built for equals the engine's current config | Stops a replaced core from marking the new app as registered; the engine already orders `configure` before the new core exists | y |
| L3 rule for `opensInAppURLs` | Unchanged behavior, now documented: every valid `initialize` sets the option to the value it carries, default `true` (Swift `Options()`, ObjC three-argument selector), like `baseUrl` falls back to the default host | Deterministic ("the last valid `initialize` decides"), consistent with `baseUrl`, and no public API shape change; sticky needs `Bool?` (out of scope) | y (scope: pick and document) |
| L4 scene key | The scene captured in the window host's target, `nil` for a scene-less (screen) target | The host already holds the scene strongly; `UIWindow.windowScene` is weak and may be cleared before `didDisconnect` | y |
| N4 wording | "Notti: in-app messages are refused for this session (HTTP 403); queued events are kept" | Matches what the engine does: the fetch gives up for the session, the next foreground session fetches again, events stay queued and are retried at the next flush; no re-registration happens, so "until the next registration" was wrong | y (scope: "rewrite as for this session") |

**Open questions:** none blocking. Device-only: whether GoogleUtilities' dynamic subclass behaves as modelled (todo).

---

## User Stories

### P1: Objective-C names that coexist with react-native-notti ⭐ MVP

**User Story:** As an app team that ships React Native screens with `react-native-notti` and native code with `NottiSDK`, I want both to link into one app, so M2 and brownfield apps work.

**Acceptance Criteria:**

1. PRF-01: The `NottiSDK` module SHALL register its Objective-C facade class under the runtime name `NottiSDK` (Swift name `NottiObjC`), SHALL register no class named `Notti`, and SHALL register none of `Notti`, `NottiImpl`, `NottiBridge` or `NottiPushDelegate`; the Objective-C test target, the README Objective-C block and the CHANGELOG SHALL use `NottiSDK`.

**Independent Test:** `NSClassFromString("NottiSDK") === NottiObjC.self`, `NSClassFromString("Notti") == nil` in the test process; `NottiObjCTests.m` calls every entry point as `[NottiSDK ...]`.

---

### P1: Identity calls before initialize are visible ⭐ MVP

**User Story:** As an integrator who gates `initialize` on consent, I want to see when an identity call is dropped, so I move it after `initialize` instead of shipping devices that are never linked.

**Acceptance Criteria:**

1. PRF-02: WHEN `login`, `addTag`, `addTags`, `removeTag`, `removeTags` or `setSubscription` (Swift or Objective-C) is called while no valid `initialize` was accepted THEN the facade SHALL log exactly one fixed `.warn` line per call naming only the method, SHALL still forward the call to the core unchanged (which drops it, RN parity), and SHALL log no external user id, tag key or value; WHEN the same calls follow a valid `initialize` THEN no such warning SHALL be logged. The doc comment of `Notti`, `README.md` and `CHANGELOG.md` SHALL say that these calls are dropped before `initialize` and that `logout` is the only identity call kept from before `initialize`.

**Independent Test:** facade over an isolated runtime with a log sink at `.verbose`; sentinel values in every argument.

---

### P1: One observation behind isa-swizzling SDKs ⭐ MVP

**User Story:** As an integrator who also uses Firebase, I want each push callback to reach Notti once, so registrations and `received` events are not doubled.

**Acceptance Criteria:**

> **Verification result (T4, 2026-10-25): the double observation does not happen, so PRF-03 and PRF-04 were not implemented as code.** The review assumed `type(of:)` answers the isa class. A probe in the test bundle showed that Swift's `type(of:)` on an Objective-C object answers `-class`: for a GoogleUtilities/KVO-style dynamic subclass it is the host class, which the registry already holds, so a late `observe` is a no-op and each callback reaches the SDK once (`NottiAppDelegateSwizzlerTests.test_aDelegateIsaSwizzledAfterTheSdkIsObservedOncePerCallback`, `test_typeOfAnswersTheClassAnIsaSwizzlingSdkHides`, `test_anIsaSwizzledSwiftUIInternalDelegateStillTakesTheAdaptorPath` pin it). The probe exposed a different gap: when the dynamic subclass exists **before** the SDK swizzles (the proxy captured the host original), the SDK swizzles the host class and never sees the callback. That needs `object_getClass` plus the skip rule below, which swizzles a third-party dynamic class; it is left for Julio's decision (STATE todo). PRF-05 (main thread) is independent and implemented.

1. PRF-03: WHEN `observe(delegate:)` sees a delegate whose isa class is a dynamic subclass of its logical class (`-class`) AND the SDK already swizzled a selector on the logical class THEN the SDK SHALL NOT swizzle that selector on the dynamic subclass, and each callback SHALL reach the adapter once and the host original once.
2. PRF-03 (continued): WHEN the dynamic subclass exists before the SDK swizzled the logical class THEN the SDK SHALL swizzle the dynamic subclass only, and each callback SHALL reach the adapter once and the host original once.
3. PRF-03 (continued): WHEN the logical class is SwiftUI's internal delegate THEN the SDK SHALL take the adaptor path (AD-016) even when the isa class is a dynamic subclass of it.
4. PRF-04: WHEN `ensureInstalled` runs a second or later time THEN the installer SHALL NOT look at the existing app delegate or `UNUserNotificationCenter` delegate again (the fallback evaluation keeps running on every call).
5. PRF-05: WHEN the late look at existing delegates runs from a thread other than main THEN the installer SHALL read the delegates and observe them on the main thread, asynchronously, and SHALL NOT read `UIApplication.delegate` on the calling thread.

**Independent Test:** fake delegate classes and fake dynamic subclasses built with `objc_allocateClassPair` (unique names), a private `NottiMethodSwizzler` per test; an installer environment with an injected main hop.

---

### P2: Low defects in new code

**User Story:** As an integrator, I want edge cases of the ObjC layer, re-initialization and multi-window apps to behave predictably.

**Acceptance Criteria:**

1. PRF-06: WHEN Objective-C calls `+[NottiUser removeTags:]` with an array that mixes strings and non-strings THEN the SDK SHALL NOT crash and SHALL remove only the string keys (non-strings dropped, like `addTags:`).
2. PRF-07: IF a replaced core's device registration succeeds after `initialize` switched to another app id, client key or base URL THEN the In-App engine SHALL NOT mark the new config as registered in this process and SHALL NOT call `eligible` because of it; a registration of the current core SHALL still mark it.
3. PRF-08: WHEN a valid `initialize` carries no explicit `opensInAppURLs` (Swift `Options()` or `initialize(appId:clientKey:)`, ObjC three-argument selector) THEN the SDK SHALL set the option to `true`, and the `Notti.Options` doc, the ObjC doc, the README and AD-020 SHALL state that every valid `initialize` sets the option to the value it carries.
4. PRF-09: WHEN `UIScene.didDisconnectNotification` arrives for the scene the display's window host was created for THEN the presenter SHALL detach the display, using the scene held by the host's target and not `UIWindow.windowScene`; a screen target SHALL report no scene.

**Independent Test:** ObjC test with a mixed `NSArray`; Swift bridge test with the PATCH body; runtime wiring test with a held retry; window host test with an allocated, never-initialized `UIWindowScene` used for identity only.

---

### P3: Accurate docs and log text

**User Story:** As an integrator reading the docs or the logs, I want them to match what the SDK does.

**Acceptance Criteria:**

1. PRF-10: The docs of `takeInitialClick()` and `addClickedListener` (Swift, ObjC, README) SHALL state that a tap reaches a clicked listener when one is attached at that moment (the launch tap included when the listener was added in `didFinishLaunching`) and is otherwise kept for `takeInitialClick()`, which returns the latest kept tap once; the `NottiRuntime.ensureCore` comment SHALL state that an uninitialized core registers the lifecycle observers and can open the session gate but sends nothing.
2. PRF-11: WHEN an In-App route answers `403` THEN the SDK SHALL log the fixed text "Notti: in-app messages are refused for this session (HTTP 403); queued events are kept" once per session and route, with no id or value, and README and CHANGELOG SHALL describe the same behavior (no "until the next registration").
3. PRF-12: `STATE.md` SHALL record AD-021 and todos for the image pixel-size cap (N5), `NSProxy` app delegates (N6) and the UN delegate behind a dynamic subclass.

**Independent Test:** engine and privacy tests assert the literal; docs by review.

---

## Edge Cases

- IF `-class` returns a class that is not a superclass of the isa class THEN the SDK SHALL treat the isa class as the logical class (PRF-03).
- IF the late observe runs on main THEN it SHALL run synchronously, so tests and a main-thread `initialize` behave as before (PRF-05).
- WHEN the ensured (pre-`initialize`) core exists THEN its registration hook carries no In-App config and SHALL NOT mark anything (it never registers) (PRF-07).
- WHEN a mixed tag array holds only non-strings THEN `removeTags:` SHALL forward an empty list (PRF-06).

---

## Design (inline)

- **D1 (PRF-01).** `@objc(Notti)` → `@objc(NottiSDK)` on `NottiObjC`. `PUBLIC_SURFACE.txt` lists Swift declarations only, so it does not change for this rename. CocoaPods' module map and the generated `NottiSDK-Swift.h` are generated; nothing to edit. A unit test pins the runtime names against the RN list.
- **D2 (PRF-02).** `NottiFacade` gets a private `warnIfNotInitialized(_ method: StaticString)` that reads `activeConfig` and logs `"Notti: <method> called before initialize was dropped"`. The core call stays.
- **D3 (PRF-03).** `NottiAppDelegateSwizzler.observe(delegate:)` resolves `isa = type(of:)` and `logical = -class` (validated as a superclass). SwiftUI checks use the logical class. When `logical !== isa`, `swizzle(delegateClass: isa, behind: logical)` skips each selector for which `NottiMethodSwizzler.isSwizzled(logical, selector)` is already true. `swizzle(delegateClass:)` keeps its behavior.
- **D4 (PRF-04, PRF-05).** `NottiDelegateInstaller` gets `lateObserveDone` (under its lock) and `Environment.runOnMain` (default: run now on main, else `DispatchQueue.main.async`). The late look runs once, through `runOnMain`.
- **D5 (PRF-06).** `NottiUserObjC.removeTags(_ keys: [Any])` (`NSArray *` in ObjC) with `compactMap { $0 as? String }`. `PUBLIC_SURFACE.txt` changes (signature).
- **D6 (PRF-07).** `NottiRuntime.makeCore(inAppConfig:)`; `start` passes the normalized config it gave the engine, `ensureCore` passes nil. `NottiInAppHooks.forwarding(to:config:)` calls `NottiInAppEngine.deviceRegistered(for:)`, which ignores a config that is not the current one; a nil config forwards nothing. `deviceRegistered()` stays for direct use.
- **D7 (PRF-08).** No behavior change; docs plus one test through the public `Notti.initialize(appId:clientKey:)`.
- **D8 (PRF-09).** `NottiInAppWindowHost.sceneKey` returns the scene of `.scene(scene)`, nil for `.screen`.
- **D9 (PRF-11).** `NottiInAppEngine.inactiveWarning` text; tests assert the new literal.

## Tasks

See `tasks.md`.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| PRF-01 | P1: ObjC names | Tasks (T2) | Done |
| PRF-02 | P1: Identity calls before initialize | Tasks (T3) | Done |
| PRF-03 | P1: One observation | Tasks (T4) | Not implemented: premise disproved, regression tests only |
| PRF-04 | P1: One observation | Tasks (T5) | Not implemented: premise disproved |
| PRF-05 | P1: One observation | Tasks (T6) | Done |
| PRF-06 | P2: Low defects | Tasks (T7) | Pending |
| PRF-07 | P2: Low defects | Tasks (T8) | Pending |
| PRF-08 | P2: Low defects | Tasks (T9) | Pending |
| PRF-09 | P2: Low defects | Tasks (T10) | Pending |
| PRF-10 | P3: Docs and log text | Tasks (T12) | Pending |
| PRF-11 | P3: Docs and log text | Tasks (T11) | Pending |
| PRF-12 | P3: Docs and log text | Tasks (T1) | Done |

**Coverage:** 12 total, 12 mapped to tasks, 0 unmapped.

## Success Criteria

- [ ] Full `NottiSDK-Package` test run green with no per-target count lower than the baseline (Shared 14, SDK 894, ObjC 7, Extension 110, ExtensionObjC 3).
- [ ] SwiftLint `--strict` 0 violations; every guard script green.
- [ ] Device follow-up recorded: a Firebase app on a device shows one registration POST per token callback.
