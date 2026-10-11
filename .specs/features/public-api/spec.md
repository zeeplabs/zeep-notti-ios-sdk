# Public API Specification

## Problem Statement

`NottiSDK` has a complete, verified core (`core-port`) but no public symbol: every type is `internal`, and `NottiSDK.swift` is a placeholder. A host app cannot initialize the SDK, identify a user, set tags or read the device id. The React Native library exposes a JS surface (`Notti.initialize`, `Notti.User`, `addEventListener`, `getDeviceId`, ...) over the same engine. This feature gives native hosts the same surface as a Swift-first facade, with an `@objc` layer for Objective-C hosts and the future RN bridge, so that M1 (v0.1.0) is usable from an app.

## Goals

- [ ] Every RN public method that is not a delegate-wiring concern has a documented Swift equivalent, each one covered by at least one passing XCTest that goes through the facade (not through `NottiCore` directly).
- [ ] The facade adds no business logic: it validates nothing the core does not already validate, and it delegates to `NottiRuntime`/`NottiCore` (AD-001, AD-002). New behavior is limited to what only a facade can own: listener multiplexing, main-thread delivery, initialize idempotency, log level.
- [ ] The public surface is explicit and reviewable: a test or CI step fails when a public symbol is added or removed without a spec change.
- [ ] No PII in any log line produced by the facade (AGENTS.md privacy rules).

## Out of Scope

| Feature | Reason |
| --- | --- |
| Swizzling of `UIApplicationDelegate` / `UNUserNotificationCenterDelegate` | `delegate-integration` |
| Manual forwarding API (`didRegisterForRemoteNotifications`, `willPresent`, `didReceive`) | `delegate-integration` (roadmap). Until it ships, the facade is unit-tested through the internal handler and token entry points of `NottiRuntime` |
| NSE rich media | `nse-rich-media` |
| RN bridge calling the facade | `rn-consumes-native-sdk` |
| Consent gating (`setConsentRequired` / `setConsentGiven`), local data wipe | `privacy-consent` (post-M1) |
| Keychain storage for email/phone | `pii-keychain-storage` (post-M1) |
| Swift 6 strict concurrency, actors, `AsyncStream` listeners | Swift 5 mode in M1 (AD-002). The facade uses `async` only where listed below, as new code |
| `isEnabled` / initialized-state accessor, permission-change listener, foreground listener | Not in RN 0.6.0 and not requested. Revisit after M1 |
| Privacy manifest `UserID` / Device ID declaration | Compliance decision (STATE todo N7), tracked in Waiting On. It does not change facade behavior |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Listener model | Multi-listener with a removable subscription token, multiplexed over the single handler per type that the core keeps | RN parity (`EventSubscription`). Safe when several host modules listen. Julio, 2026-10-10 | y |
| Callback thread | Every callback the host gives the SDK (listeners, `requestPermission` completion, device-id observer) runs on the main thread | Predictable for UI and `UNUserNotificationCenter`. The core calls back on its serial `workQueue`. Julio, 2026-10-10 | y |
| `initialize` called again | Same normalized `appId`/`clientKey`/`baseUrl` is a no-op. Different values rebuild the core | Avoids re-registration and session reopen on duplicate init (STATE N1). Julio, 2026-10-10 | y |
| Default `baseUrl` | `https://app.zeepnotti.app` when `options.baseUrl` is omitted (value comes from `RN/src/index.tsx`, today only a TS constant) | RN parity. Julio, 2026-10-10 | y. Backend team should confirm the host is still the production one before v0.1.0 |
| Async API | `requestPermission() async -> Bool` plus a completion-handler variant. The `Bool` is the OS dialog result, not the PATCH result | RN `Promise<boolean>` semantics. Julio, 2026-10-10 | y |
| Before `initialize` | Calls that need a registered device are dropped and logged at `.warn`/`.error` as the core does today. `requestPermission` completes with `false` without showing the prompt. Email/phone are persisted and converge on the next registration (DPF-19) | Preserves core-port behavior, no new rules | y (inherited) |
| Failure model | Nothing in the facade throws or crashes. Invalid input is logged and ignored | Core contract (invalid `baseUrl` disables the SDK instead of throwing) | y (inherited) |
| Log level default | `.error` | CORE-13. The roadmap line "off by default in release" is read as "no verbose output by default", not as `.none` | n - Julio to confirm wording |
| ObjC shape | Swift `enum`/`struct` namespaces are not visible to Objective-C, so the `@objc` layer is a separate set of `NSObject` classes. Class names and prefix are decided in Design | Language constraint | n - Design |
| `getDeviceId()` before `initialize` | Returns `nil`, because the core does not exist yet, even if a device id is persisted | Matches how the core exposes it today. RN behavior with a persisted id before initialize is not verified | n - verify against RN in Design. If RN returns the persisted id, the facade must too (AD-002) |
| Initial click | One-shot: returns the latest click and consumes it | Core `takeInitialClick()` and RN parity | y (inherited) |
| Replay for listeners | The `received` core handler replays buffered events when it is first registered, so only the first listener receives that replay. `clicked` has no replay. Later listeners get new events only | Core buffer semantics (SDKOPEN, core-port). Documented, not changed | n - Design confirms against `NottiEventBuffer` |
| Naming of public types | `Notti` (namespace), `Notti.User`, `Notti.Notifications`, `NottiLogLevel`, `NottiSubscription`, `NottiNotificationPayload` | ROADMAP wording. Final names are frozen in Design | n - Design |

Open questions: the four `n` rows above. Two need an answer from Julio (log level wording) or the backend/RN code (`getDeviceId`, replay); the other two are Design decisions. None blocks moving to Design.

---

## User Stories

### P1: Initialize and identify ⭐ MVP

**User Story**: As an iOS developer, I want to initialize Notti and identify the user with one call each so that the device registers and push targeting works.

**Why P1**: Nothing else works without initialize, and identity is the main reason a host adopts the SDK.

**Acceptance Criteria**:

1. WHEN the host calls `Notti.initialize(appId:clientKey:options:)` THEN the facade SHALL start the shared `NottiRuntime` with those values and with `baseUrl` taken from `options.baseUrl`, or `https://app.zeepnotti.app` if it is omitted or `nil` (API-01).
2. WHEN `initialize` receives an empty `appId`, `clientKey` or an invalid `baseUrl` THEN the facade SHALL NOT throw or crash, SHALL leave the SDK disabled, and SHALL log through `NottiLogger` without any of the three values (API-01).
3. WHEN `initialize` is called again with the same normalized `appId`, `clientKey` and `baseUrl` THEN the facade SHALL NOT rebuild the core and SHALL NOT trigger a second registration. WHEN any of them differs THEN it SHALL stop the old core and start a new one (API-02).
4. WHEN the facade is used in production THEN it SHALL go through `NottiRuntime.shared`, and a test SHALL prove that this runtime reads and writes the `notti_prefs` suite (closes STATE F1) (API-03).
5. WHEN the host calls `Notti.login(_:)` THEN the facade SHALL call `core.login`. WHEN it calls `Notti.logout()` THEN it SHALL call `core.logout`. Persistence, pending-mutation queueing and server-side clearing of email/phone SHALL be exactly the core's (API-04).
6. WHEN the host calls `Notti.deviceId` THEN it SHALL receive the current id synchronously or `nil` (API-05).
7. WHEN the device id changes THEN every registered device-id observer SHALL be called once with the new id, on the main thread. A re-registration with the same id SHALL NOT call them (API-05, API-12).

**Independent Test**: A facade test initializes an isolated runtime with a stubbed HTTP client, asserts one registration request, calls `initialize` again with the same and then different values and asserts 0 and 1 additional registrations, then `login` and asserts the PATCH.

---

### P1: User profile

**User Story**: As an iOS developer, I want to set tags, email, phone and subscription state so that the backend can segment and reach the user.

**Why P1**: It is the rest of the RN `Notti.User` surface and the main targeting input.

**Acceptance Criteria**:

1. WHEN the host calls `Notti.User.addTag(_:value:)`, `addTags(_:)`, `removeTag(_:)` or `removeTags(_:)` THEN the facade SHALL map them to `core.mutateTags(add:remove:)`, keeping the core's merge-at-send behavior. `addTags` SHALL accept `[String: String]` only, so no sanitizing of other types is needed in Swift, and the `@objc` variant SHALL pass through `NottiRuntime.sanitizeTags` (API-06).
2. WHEN the host calls `setEmail`, `clearEmail`, `setPhone` or `clearPhone` THEN the facade SHALL call the matching core method. Persist-before-guard, coalescing and explicit-null clear SHALL stay as in the core (API-07).
3. WHEN the host calls `Notti.User.setSubscription(_:)` THEN the facade SHALL call `core.setSubscription`, including the `last_unsubscribed_at` rule on a true-to-false transition (API-08).
4. WHEN the host calls `Notti.setLocationSharingEnabled(_:)` THEN the facade SHALL call the core on the caller's thread so that the preference is written synchronously (LGPD B1). Default SHALL remain `false`, and the SDK SHALL NOT request location permission (API-08).
5. WHEN any profile call happens before `initialize` THEN the behavior SHALL be the core's (dropped or persisted-and-converged as listed in Assumptions), with no new exception (API-04, API-06..08).

**Independent Test**: Facade tests call each method on an initialized isolated runtime and assert the exact PATCH body fields, and one test per method before `initialize`.

---

### P1: Notifications

**User Story**: As an iOS developer, I want to ask for push permission and receive notification events so that I can drive UI from them.

**Why P1**: Permission and events are the two other pillars of the RN surface.

**Acceptance Criteria**:

1. WHEN the host calls `await Notti.Notifications.requestPermission()` THEN it SHALL return the result of the OS dialog. WHEN called before `initialize` THEN it SHALL return `false` without showing the prompt. The completion-handler variant SHALL behave the same (API-09).
2. WHEN the host calls `Notti.Notifications.addListener(_:handler:)` for `received`, `clicked` or `deviceIdChanged` THEN it SHALL receive a `NottiSubscription`. WHEN `remove()` is called THEN that handler SHALL NOT be called again, and calling it twice SHALL be safe (API-10).
3. WHEN several listeners exist for one event THEN every one SHALL receive each event, in registration order, on the main thread. WHEN the last listener of a type is removed THEN the facade SHALL clear the core handler so that later events are buffered again by the core (API-10, API-12).
4. WHEN a listener is added or removed from inside a callback THEN the facade SHALL NOT deadlock or crash, and the change SHALL apply from the next event (API-10).
5. WHEN a notification event arrives before any listener exists THEN the core buffer SHALL hold it and the first `received` listener SHALL receive the replay, as the core does today (API-10).
6. WHEN the host calls `Notti.Notifications.takeInitialClick()` THEN it SHALL return the cold-start click payload once and `nil` afterwards (API-11).
7. WHEN a payload is delivered THEN it SHALL contain `title: String?`, `body: String?` and `data: [String: String]`, and nothing else (API-10, API-11).

**Independent Test**: Tests drive `NottiRuntime.eventBuffer` with synthetic payloads (`example.invalid`, `fixture`), register two listeners, remove one, and assert delivery counts and thread.

---

### P2: Objective-C interop

**User Story**: As an Objective-C host or the RN bridge, I want the same capabilities through `@objc` so that I do not need Swift-only types.

**Why P2**: Needed for `rn-consumes-native-sdk` and ObjC hosts, but the Swift API has to exist first.

**Acceptance Criteria**:

1. WHEN an Objective-C file imports `NottiSDK` THEN every P1 capability SHALL be callable from it, with completion handlers instead of `async` and `NSDictionary`/`NSString` instead of Swift-only generics (API-13).
2. WHEN the Objective-C layer receives non-string tag values THEN it SHALL drop them through `sanitizeTags`, as RN does (API-13).
3. WHEN the package is built for Objective-C THEN the repo SHALL contain a compile check (a small ObjC test target or a `.m` file in the example build) that fails if the surface stops compiling (API-13).

**Independent Test**: An ObjC test file calls initialize, login, setTags, addListener and requestPermission and runs in CI.

---

### P2: Log level

**User Story**: As an iOS developer, I want to raise the SDK log level while debugging, so that I can see what the SDK is doing without leaking user data.

**Why P2**: The roadmap lists it, but the SDK works without it.

**Acceptance Criteria**:

1. WHEN the host sets `Notti.logLevel` THEN the value SHALL map to `NottiLogger.level` (`none`, `error`, `warn`, `info`, `debug`, `verbose`) and SHALL be readable back (API-14).
2. WHEN the SDK starts THEN the level SHALL be `.error` (CORE-13) (API-14).
3. WHEN any level is set THEN no log line SHALL contain email, phone, push token, external user id, country or tag values. The existing sentinel test SHALL run at the highest level through the facade (API-14, API-15).

**Independent Test**: Set `.verbose`, run a facade flow with sentinel values, and assert none appears in the log sink.

---

### P1: Public surface hygiene

**User Story**: As the SDK maintainer, I want the public surface to be small and guarded so that v0.1.0 does not freeze accidental API.

**Why P1**: Public symbols are a compatibility promise.

**Acceptance Criteria**:

1. WHEN the package builds THEN the only `public` symbols in `NottiSDK` SHALL be the ones this spec lists, and a CI check SHALL fail when the list changes without an update to the committed surface file (API-15).
2. WHEN `NottiSDK` exposes app-only API THEN it SHALL be marked `@available(iOSApplicationExtension, unavailable)`, and `check-extension-safety.sh` and `check-package-graph.sh` SHALL still pass. `NottiSDKExtension` SHALL NOT start depending on `NottiSDK` (API-15).
3. WHEN public types mirror `package` types (`NottiLogLevel`) THEN no `package` symbol SHALL appear in a public signature (API-15).

**Independent Test**: The CI surface check fails on a throwaway added `public func`, and passes after the surface file is updated.

---

## Edge Cases

- WHEN `initialize` is called from a background thread THEN it SHALL behave the same as from main (the core already owns its queue). Main-thread callbacks SHALL still hold.
- WHEN a listener is registered before `initialize` THEN it SHALL work, because the event buffer exists before the core.
- WHEN two `initialize` calls with different values race on different threads THEN the final state SHALL be one consistent core, with no leaked observers (the runtime's `lifecycleLock` serializes this).
- WHEN `requestPermission` is called twice concurrently THEN both calls SHALL complete, each with the OS result.
- WHEN a main-thread hop would reorder events THEN delivery order SHALL still equal emission order for one listener.
- WHEN the host retains a `NottiSubscription` after `remove()` THEN it SHALL hold no strong reference to the handler.
- WHEN the baseUrl is `http://` in a release build THEN it SHALL be rejected, as in the core (A5).

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| API-01 | P1: Initialize and identify (initialize, default baseUrl, no throw) | Design | Pending |
| API-02 | P1: Initialize and identify (idempotency, N1) | Design | Pending |
| API-03 | P1: Initialize and identify (`shared` uses `notti_prefs`, F1) | Design | Pending |
| API-04 | P1: Initialize and identify (login/logout) | Design | Pending |
| API-05 | P1: Initialize and identify (device id accessor and observer) | Design | Pending |
| API-06 | P1: User profile (tags) | Design | Pending |
| API-07 | P1: User profile (email, phone) | Design | Pending |
| API-08 | P1: User profile (subscription, location sharing) | Design | Pending |
| API-09 | P1: Notifications (requestPermission) | Design | Pending |
| API-10 | P1: Notifications (listeners, payload, replay) | Design | Pending |
| API-11 | P1: Notifications (initial click) | Design | Pending |
| API-12 | P1: Initialize and identify, Notifications (main-thread delivery) | Design | Pending |
| API-13 | P2: Objective-C interop | Design | Pending |
| API-14 | P2: Log level | Design | Pending |
| API-15 | P1: Public surface hygiene (+ no-PII at all levels) | Design | Pending |

Inherited behavior (facade part only; core part verified in `core-port`):

- `sdk-core-v1` SDK-17..19 (listener/emitter): API-10, API-11, API-05
- `opened-event-reporting` SDKOPEN-10 (JS events): API-10
- `device-profile-fields` DPF-17..21 (JS-surface wording): API-07

**Coverage:** 15 total, 15 mapped to a story, 0 mapped to tasks yet (tasks are written after Design).

---

## Success Criteria

- [ ] Every RN 0.6.0 public method outside delegate wiring has a facade equivalent, and each one is listed with its test in `traceability.md`.
- [ ] The committed public-surface file matches the build, and CI fails on drift.
- [ ] Objective-C compile check is green in CI.
- [ ] The sentinel PII test passes at `.verbose` through the facade.
- [ ] Test count does not drop below 252, and the full gate (tests, SwiftLint `--strict`, the three scripts, `pod lib lint`, device builds) stays green.
