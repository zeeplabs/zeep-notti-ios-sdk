# Delegate Integration Specification

## Problem Statement

`NottiSDK` has a verified core and a public facade, but nothing connects it to the OS: the APNs token and the notification callbacks (`willPresent`, `didReceive`) reach the SDK only through internal entry points that the tests call. A host app today would have to forward every callback by hand, and the React Native library does exactly that (`NottiBridge`, `NottiPushDelegate`), which conflicts with other push SDKs that want the same single `UNUserNotificationCenter` delegate. This feature wires the SDK to the OS with swizzling by default (AD-004), an Info.plist opt-out, a manual forwarding API for opted-out or multi-SDK hosts, and capture of the cold-start click before `initialize`.

## Goals

- [ ] A host that only calls `Notti.initialize` gets the APNs token registered, `received` and `clicked` events delivered and reported, and its own delegate methods still called, with no forwarding code.
- [ ] A host that opts out (or runs several push SDKs) reaches the same behavior through a documented manual API, with no swizzling at all.
- [ ] A notification tapped to cold-start the app is not lost when `initialize` runs later than the delegate callback.
- [ ] Swizzling never breaks the host: originals are always called, no callback is called twice, the install is idempotent, and nothing throws or crashes.
- [ ] No PII in any log line produced by this feature (AGENTS.md privacy rules).

## Out of Scope

| Feature | Reason |
| --- | --- |
| `UIScene` / `SceneDelegate` APIs | Not needed: the callbacks used here live on `UIApplicationDelegate` and `UNUserNotificationCenterDelegate` |
| Opening a deep link / URL from the SDK, a typed `url` field on the payload | The SDK never calls `UIApplication.open` (server-controlled URL, host owns routing). The backend contract defines no standard URL key, so none is invented. If the backend defines one, a typed accessor is a later, additive change |
| Background work triggered by a silent push (`BGTaskScheduler`, refresh) | The SDK only observes and reports the push. It does no work of its own in the background |
| Notification categories and action registration | The host registers categories. The SDK only reads `actionIdentifier` (behavior already in `NottiNotificationHandler`) |
| NSE (rich media, `mutable-content`) | `nse-rich-media` |
| Running against Firebase / OneSignal on a real device | Device validation checklist in `example-and-release`. This feature tests the chaining contract with fake delegates |
| Consent gating of event reporting | `privacy-consent` (post-M1) |
| Behavior changes to `NottiNotificationHandler` or the core | The reporting decisions stay as ported (AD-002). This feature only adapts OS callbacks to its plain inputs |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| When the swizzle is installed | At process launch from a small Objective-C target (`+load`), before any host code, in addition to being idempotently ensured by `Notti.initialize`. `+load` only installs swizzles | A pure Swift SDK has no code that runs before `initialize`, so a cold-start click delivered before `initialize` would otherwise reach the host untouched. Julio, 2026-10-11 | y |
| `+load` in a static library | The ObjC object file must not be dead-stripped in SPM and CocoaPods builds | [Incerto]. Design must prove it with a build or test that fails when the hook does not run | open, Design spike |
| Opt-out key | Info.plist `NottiDisableSwizzling` (Boolean). `YES` disables every swizzle and the delegate takeover. Missing or `NO` leaves swizzling on | OneSignal-style opt-out (`OneSignal_disable_swizzling`). Name is proposed here, not from the roadmap | y (inherited from AD-004: opt-out exists), name to confirm |
| Foreground presentation | The host decides. The SDK observes `willPresent`, then forwards to the host's original and its completion handler wins. If the host has no `willPresent`, the SDK calls the completion with `[.banner, .list, .sound, .badge]` for a Notti push (a remote push with a non-empty `notification_id`, RN parity) and with `[]` (the OS default) for any other notification. Julio, 2026-10-11, narrowed 2026-10-11 (design D2) | Does not override another SDK or the host's own rules | y |
| No host `UNUserNotificationCenter` delegate | If `delegate` is `nil` when the hook runs, the SDK installs its own adapter as the delegate. If the host sets one later, the `delegate` setter swizzle keeps the SDK's observation in front of the host's. Julio, 2026-10-11 | Without a delegate, no callback would reach the SDK. One-line integration for simple apps | y |
| Manual call while swizzling is active | Ignored with a `.warn` log, to avoid double-processing (AD-004) | Both paths feed the same handler, and `received`/`opened`/`clicked` would be reported twice | y (inherited from AD-004) |
| Manual API shape | On `Notti.Notifications`: `didRegisterForRemoteNotifications(deviceToken:)`, `didFailToRegisterForRemoteNotifications(error:)`, `didReceiveRemoteNotification(_:) -> UIBackgroundFetchResult`, `willPresent(_:) -> UNNotificationPresentationOptions`, `didReceive(_:)`, taking the OS types the host already has in its delegate methods. `@objc` mirror on the Objective-C `NottiNotifications` | The host already holds `UNNotification` / `UNNotificationResponse`. Plain-input overloads stay internal for tests | y (proposal, Design confirms) |
| Opt-out and the `delegate` takeover | Opt-out also disables the "assume the delegate when nil" rule | Opt-out means "SDK touches nothing". The host forwards manually | y |
| Silent push | `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` is observed and forwarded. A push **without** `aps.alert` is a silent push: it is parsed, emitted as `received` and its `received` report is queued, as `willPresent` does for a visible one. Julio, 2026-10-11 | Silent push should count in delivery metrics. Requires the host's `UIBackgroundModes` `remote-notification` (README) | y |
| Visible push that also has `content-available: 1` | Not handled by the silent-push path. The OS calls both `willPresent` and `didReceiveRemoteNotification:fetchCompletionHandler:` in the foreground, and `willPresent` already reports it, so the silent path SHALL skip any payload that has `aps.alert` | Avoids reporting `received` twice for one delivery | y (proposal) |
| Legacy host method | If the host implements only `application(_:didReceiveRemoteNotification:)` (no `fetchCompletionHandler`), the SDK SHALL NOT add the newer method: adding it would make the OS stop calling the host's legacy one | Swizzling must never shadow a host method | y (proposal) |
| Deep link | The SDK does not interpret links. The payload `data` already carries the host's own link field through `received`, `clicked` and `takeInitialClick()`; this feature proves it arrives intact (including on cold start). Differs from the recommended typed `url` field: the backend defines no URL key, so a typed field would invent a contract. Julio chose "expose the URL, host routes"; this is the contract-safe form of it | Backend contract confirmation needed before any typed field | y (form to confirm) |
| Event buffer before the core | `NottiRuntime.shared.eventBuffer` and `eventStore` exist before `initialize`. A click before `initialize` is held for `takeInitialClick()`, and its offline report stays queued until registration or a later flush | Core buffer semantics and `NottiNotificationHandler` cold-start comment | y (verified in the code) |

Open questions: none. The `+load` / static-library behavior is a Design spike, and the opt-out key name `NottiDisableSwizzling` is a proposal to confirm before v0.1.0 (it is the public contract of the Info.plist).

---

## User Stories

### P1: APNs token capture ⭐ MVP

**User Story**: As an iOS developer, I want the APNs device token to reach Notti without writing code in my `AppDelegate` so that the device registers for push.

**Why P1**: Without the token no notification can be delivered, and the SDK already calls `registerForRemoteNotifications()`.

**Acceptance Criteria**:

1. WHEN the app's `UIApplication.delegate` receives `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` and swizzling is on THEN the SDK SHALL pass the token to `NottiRuntime.onApnsToken` and SHALL then call the host's original with the same arguments (DEL-03).
2. WHEN the delegate receives `application(_:didFailToRegisterForRemoteNotificationsWithError:)` THEN the SDK SHALL call `NottiRuntime.onApnsRegistrationFailed`, logging `domain#code` only, and SHALL call the host's original (DEL-03).
3. WHEN the host's delegate does not implement either method THEN the SDK SHALL add its own implementation so the callback still reaches it, and no crash SHALL occur (DEL-03).
4. WHEN the token arrives before `initialize` has created a core THEN the token SHALL be dropped as the runtime does today (RN parity), with no crash (DEL-03).

**Independent Test**: A fake `UIApplicationDelegate` class gets the swizzle. Calling its token method asserts the runtime received the token exactly once and the fake's original ran exactly once, in both the "host implements" and "host does not implement" variants.

---

### P1: Notification events through the OS delegate ⭐ MVP

**User Story**: As an iOS developer, I want `received` and `clicked` events and their reporting to happen automatically while my own notification handling keeps working.

**Why P1**: It is the second half of the RN push delegate and the source of every delivery/open/click metric.

**Acceptance Criteria**:

1. WHEN `userNotificationCenter(_:willPresent:withCompletionHandler:)` runs on a swizzled delegate THEN the SDK SHALL call `NottiNotificationHandler.handleWillPresent` with the notification's `userInfo` and request identifier, and then forward to the host's original (DEL-04).
2. WHEN the host's delegate implements `willPresent` THEN the host's completion handler SHALL be the one that reaches the OS, and the SDK SHALL NOT call the completion itself. WHEN it does not implement it THEN the SDK SHALL call the completion once with `[.banner, .list, .sound, .badge]` for a Notti push (remote push with non-empty `notification_id`) and with `[]` for any other notification, so a host that never showed foreground notifications still does not (DEL-04).
3. WHEN `userNotificationCenter(_:didReceive:withCompletionHandler:)` runs THEN the SDK SHALL call `NottiNotificationHandler.handleResponse` with the action identifier, `userInfo` and request identifier, then forward to the host's original. The completion SHALL be called exactly once, by the host if it implements the method and by the SDK otherwise (DEL-05).
4. WHEN the notification is local or has no `aps` key (another SDK's or the host's own) THEN the SDK SHALL NOT parse or report it, and SHALL still forward it untouched (DEL-11, inherited from the handler).
5. WHEN a `didReceive` response carries a `delivery_id` that is empty THEN the SDK SHALL NOT enqueue a report for it, covered by a test on the `didReceive` path (closes STATE F7) (DEL-05).
6. WHEN several host delegate instances exist over time THEN the SDK SHALL observe each call once per OS callback, never once per swizzled layer (DEL-07).

**Independent Test**: A fake `UNUserNotificationCenterDelegate` (with and without the methods) gets the swizzle. Driving it with synthetic `userInfo` (`example.invalid`, `fixture`) asserts handler calls, event-store contents, the original's call count and exactly one completion call.

---

### P1: Opt-out and delegate ownership ⭐ MVP

**User Story**: As an iOS developer with another push SDK, I want to turn Notti's swizzling off, or have Notti coexist with my delegate, so that nothing in my app changes behind my back.

**Why P1**: AD-004 makes swizzling the default only because an opt-out exists.

**Acceptance Criteria**:

1. WHEN Info.plist has `NottiDisableSwizzling = YES` THEN the SDK SHALL install no swizzle, SHALL NOT replace or assume any delegate, and SHALL log one `.info` line saying swizzling is disabled (DEL-02).
2. WHEN the key is missing or `NO` THEN swizzling SHALL be on (DEL-02).
3. WHEN `UNUserNotificationCenter.current().delegate` is `nil` at the end of launch (D1) and swizzling is on THEN the SDK SHALL set its own adapter as the delegate (DEL-06).
4. WHEN the host later assigns `UNUserNotificationCenter.current().delegate` THEN the SDK SHALL keep observing callbacks and SHALL forward to the host's delegate, whichever class it is (DEL-06).
5. WHEN `Notti.initialize` runs after the install THEN installing again SHALL be a no-op: each method is swizzled at most once per class, and a second install SHALL NOT change call order or counts (DEL-07).
6. WHEN another SDK swizzles the same selectors before or after Notti THEN the chain SHALL still call every original exactly once. A test with two stacked fake swizzlers SHALL prove it (DEL-07).

**Independent Test**: Tests set the opt-out through an injectable configuration (not the real `Info.plist`) and assert the delegate object, the selector implementations and the log line are untouched. Idempotency tests call install N times and assert one observation per callback.

---

### P1: Cold-start click before `initialize` ⭐ MVP

**User Story**: As an iOS developer, I want the notification that launched my app to be available even if I initialize Notti later, so that I can route the user to the right screen.

**Why P1**: It is a roadmap item and the RN buffer exists for exactly this case (`getInitialNotificationClick`).

**Acceptance Criteria**:

1. WHEN the app is launched by tapping a Notti push and the delegate callback arrives before `Notti.initialize` THEN the click SHALL be buffered, `Notti.Notifications.takeInitialClick()` SHALL return it once and `nil` afterwards (DEL-10).
2. WHEN that same click carries `notification_id` and `delivery_id` THEN its `opened` and `clicked` reports SHALL be queued in the event store and flushed after registration or a later trigger, with no core needed at tap time (DEL-10).
3. WHEN the ObjC hook runs at launch THEN it SHALL only install swizzles: no network, no file or UserDefaults I/O, and no access to `NottiRuntime.shared.core`. The enabled, valid path logs nothing above `.debug`; opt-out `.info`, install failure `.error` and non-Boolean `.warn` are the only lines (DEL-14).
4. WHEN `+load` is linked from SPM or CocoaPods THEN a test or build check SHALL fail if the hook is dead-stripped or never runs (DEL-01).

**Independent Test**: A test drives the handler through the adapter with no initialized core, then calls `takeInitialClick()` twice and asserts the payload then `nil`, and the queued event-store entries. A separate build check proves the `+load` hook runs.

---

### P1: Manual forwarding API

**User Story**: As an iOS developer who opts out or uses several push SDKs, I want public methods to call from my own delegate so that Notti works without swizzling.

**Why P1**: AD-004 requires the manual path to always exist, and the RN SDK only had this path.

**Acceptance Criteria**:

1. WHEN swizzling is off THEN `Notti.Notifications.didRegisterForRemoteNotifications(deviceToken:)`, `didFailToRegisterForRemoteNotifications(error:)`, `didReceiveRemoteNotification(_:)`, `willPresent(_:)` and `didReceive(_:)` SHALL feed the same internal entry points as the swizzled path (DEL-08).
2. WHEN `willPresent(_:)` is called THEN it SHALL return `[.banner, .list, .sound, .badge]` for a Notti push and `[]` otherwise, after reporting, and the host remains free to ignore or combine the value (DEL-08).
3. WHEN swizzling is on and the host calls any of the five methods THEN the SDK SHALL ignore the call, log one `.warn` line per call without payload values, and SHALL NOT process the event twice (DEL-09).
4. WHEN called before `initialize` THEN the manual API SHALL behave like the swizzled path before `initialize` (DEL-08, DEL-10).
5. WHEN Objective-C calls the manual API THEN it SHALL be reachable through `NottiNotifications` with the same semantics (DEL-12).

**Independent Test**: With swizzling disabled in the injected configuration, each manual method drives the same handler and the same assertions as the swizzled tests. With it enabled, the same calls change nothing and log a warning.

---

### P1: Silent push

**User Story**: As an iOS developer, I want silent pushes to be counted and delivered to my `received` listener so that background-only notifications show up in delivery metrics.

**Why P1**: Requested in scope for M1 (Julio, 2026-10-11). RN 0.6.0 has no equivalent, so this is new behavior, not a port.

**Acceptance Criteria**:

1. WHEN `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` runs with a payload that has `aps` and no `aps.alert` THEN the SDK SHALL emit `received` and queue the `received` report (when `notification_id` and `delivery_id` are non-empty), then forward to the host's original (DEL-15).
2. WHEN the host implements that method THEN the host's completion handler SHALL be the one that reaches the OS. WHEN it does not THEN the SDK SHALL call the completion once with `.noData` (DEL-15).
3. WHEN the host implements only the legacy `application(_:didReceiveRemoteNotification:)` THEN the SDK SHALL NOT add the `fetchCompletionHandler` variant, and the host's legacy method SHALL keep being called (DEL-16).
4. WHEN a visible push (`aps.alert` present) arrives with `content-available: 1` THEN `received` SHALL be reported exactly once, by `willPresent`, and never by the silent path (DEL-17).
5. WHEN the payload has no `aps` (not a remote push) THEN the SDK SHALL NOT parse or report it and SHALL forward it untouched (DEL-11, DEL-15).
6. WHEN the callback arrives with the app not running or backgrounded THEN the SDK SHALL NOT touch UIKit or start network work beyond the existing flush trigger (DEL-15).

**Independent Test**: A fake `UIApplicationDelegate` gets the swizzle in three variants (modern method, legacy only, none). Synthetic payloads (silent, visible with `content-available`, no `aps`) assert emission count, event-store contents, original call counts and exactly one completion.

---

### P1: Deep link passthrough

**User Story**: As an iOS developer, I want the link my push carries to reach my code unchanged, on every tap path, so that I can route the user myself.

**Why P1**: Requested in scope for M1. The SDK stays out of routing and never opens a URL.

**Acceptance Criteria**:

1. WHEN a tapped push carries a link in `data` (any host-chosen key) THEN the `clicked` listener and `takeInitialClick()` SHALL return it byte for byte in `data`, on warm and cold start (DEL-18).
2. WHEN the tap carries a link THEN the SDK SHALL still report one `opened` and one `clicked` (opened-event-reporting D1) and SHALL NOT call `UIApplication.open` or any URL-opening API (DEL-18).
3. WHEN a source file under `Sources/NottiSDK` references a URL-opening call (`.open(` on `UIApplication`) THEN a script check SHALL fail (DEL-18).
4. WHEN a link value is logged THEN it SHALL NOT be: no log line contains a `data` value (DEL-13, DEL-18).

**Independent Test**: Warm and cold-start tap tests with a synthetic `data` link (`https://example.invalid/fixture`) assert the exact value, the two reports and zero URL-open calls; a grep guard covers the open-URL ban.

---

### P2: Safety, privacy and surface


**User Story**: As the SDK maintainer, I want the OS wiring to be extension-safe, guarded and free of PII so that it can ship in v0.1.0.

**Why P2**: These are the repo's standing invariants; they gate the Verifier rather than add behavior.

**Acceptance Criteria**:

1. WHEN the package builds THEN every new public symbol SHALL be listed in `PUBLIC_SURFACE.txt` and every new app-only type SHALL carry `@available(iOSApplicationExtension, unavailable)`; `check-extension-safety.sh` and `check-package-graph.sh` SHALL still pass, and `NottiSDKExtension` SHALL NOT depend on the ObjC hook target (DEL-12).
2. WHEN any log line is written by this feature THEN it SHALL NOT contain a token, title, body, `data` value, `notification_id`, `delivery_id` or error `localizedDescription`. The existing sentinel test SHALL cover the new paths at `.verbose` (DEL-13).
3. WHEN a swizzle fails to install (selector missing, class unavailable) THEN the SDK SHALL log at `.error` with no values and SHALL leave the host's behavior unchanged (DEL-13).

**Independent Test**: Surface and graph scripts in CI, and the sentinel test extended with the adapter paths.

---

## Edge Cases

- WHEN `UIApplication.shared.delegate` is `nil` or SwiftUI's internal delegate (no `@UIApplicationDelegateAdaptor`) THEN the SDK SHALL NOT crash, SHALL log one `.warn`, and the token SHALL need the manual API. This limitation SHALL be in the README (example-and-release).
- WHEN the app uses `@UIApplicationDelegateAdaptor` THEN `UIApplication.shared.delegate` is still SwiftUI's internal delegate, which forwards each call to the host's adaptor object through `forwardingTarget(for:)`. The SDK SHALL ask the internal delegate for that forwarding target, SHALL swizzle the target's class (the host delegate) exactly as for a UIKit delegate, SHALL NOT add or replace any method on SwiftUI's internal class and SHALL NOT log the SwiftUI `.warn`. A target that is `nil`, the internal delegate itself or another SwiftUI-internal object means no adaptor (previous edge case) (DEL-19, AD-016).
- WHEN the host swaps `UNUserNotificationCenter.delegate` repeatedly THEN each assignment SHALL be observed without growing the swizzle chain.
- WHEN a delegate class is a subclass of an already swizzled class THEN each callback SHALL still be observed once.
- WHEN the host's `didReceive` never calls its completion THEN that is the host's bug and the SDK SHALL NOT call it a second time.
- WHEN the callback arrives on a background thread THEN the SDK SHALL process it without touching UIKit, and host forwarding SHALL happen on the same thread the OS used.
- WHEN `Notti.initialize` is never called THEN the swizzle (if on) SHALL still observe and buffer events, and SHALL send nothing over the network.
- WHEN `Info.plist` has the key with a non-Boolean value THEN the SDK SHALL treat it as `NO` (swizzling on) and log one `.warn`.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| DEL-01 | P1: Cold-start click (`+load` hook runs, not dead-stripped) | Specify | Verified (round 2 PASS) |
| DEL-02 | P1: Opt-out and delegate ownership (Info.plist key) | Specify | Verified (round 2 PASS) |
| DEL-03 | P1: APNs token capture | Specify | Verified (round 2 PASS) |
| DEL-04 | P1: Notification events (`willPresent`) | Specify | Verified (round 2 PASS) |
| DEL-05 | P1: Notification events (`didReceive`, F7) | Specify | Verified (round 2 PASS) |
| DEL-06 | P1: Opt-out and delegate ownership (assume delegate, setter swizzle) | Specify | Verified (round 2 PASS) |
| DEL-07 | P1: Opt-out and delegate ownership (idempotent, chains with other SDKs) | Specify | Verified (round 2 PASS) |
| DEL-08 | P1: Manual forwarding API | Specify | Verified (round 2 PASS) |
| DEL-09 | P1: Manual forwarding API (ignored while swizzling is on) | Specify | Verified (round 2 PASS) |
| DEL-10 | P1: Cold-start click before `initialize` | Specify | Verified (round 2 PASS) |
| DEL-11 | P1: Notification events (non-Notti notifications untouched) | Specify | Verified (round 2 PASS) |
| DEL-12 | P1: Manual API (`@objc` mirror), P2: surface and extension safety | Specify | Verified (round 2 PASS) |
| DEL-13 | P2: Safety, privacy and surface (no PII, install failures) | Specify | Verified (round 2 PASS) |
| DEL-14 | P1: Cold-start click (`+load` does only swizzling) | Specify | Verified (round 2 PASS) |
| DEL-15 | P1: Silent push (observe, report `received`, forward) | Specify | Verified (round 2 PASS) |
| DEL-16 | P1: Silent push (legacy-only host not shadowed) | Specify | Verified (round 2 PASS) |
| DEL-17 | P1: Silent push (no double `received` for visible push) | Specify | Verified (round 2 PASS) |
| DEL-18 | P1: Deep link passthrough (data intact, no URL opening) | Specify | Verified (round 2 PASS) |
| DEL-19 | Edge case: SwiftUI `@UIApplicationDelegateAdaptor` (swizzle the forwarding target, AD-016) | Specify | Implemented (unit + hosted Example test); device pending (D08) |

Inherited behavior (adapter part only; reporting decisions verified in `core-port`):

- `sdk-core-v1` SDKCTR-04, `opened-event-reporting` SDKOPEN-* (what is reported per action): unchanged, reached through `NottiNotificationHandler`
- `public-api` API-10, API-11 (listener delivery and `takeInitialClick`): unchanged

**Coverage:** 18 total, 18 mapped to a story, 0 mapped to tasks yet.

---

## Success Criteria

- [ ] A host with only `Notti.initialize` gets token registration and both events, proven by tests over fake delegates, and its own delegate methods run exactly once per callback.
- [ ] With `NottiDisableSwizzling = YES` no selector or delegate changes, and the manual API gives the same observable result.
- [ ] A silent push is counted once, a visible push with `content-available` is counted once, and a host with only the legacy method keeps it.
- [ ] A deep link in `data` reaches `clicked` and `takeInitialClick()` unchanged and the SDK never opens a URL.
- [ ] A cold-start click before `initialize` is returned once by `takeInitialClick()`, and its reports are queued.
- [ ] The `+load` hook is proven to run in SPM and CocoaPods builds (Design spike), and `pod lib lint` stays green.
- [ ] Public-surface, extension-safety and package-graph scripts stay green; test count does not drop below 356; SwiftLint `--strict` stays at 0.
