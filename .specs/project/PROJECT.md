# zeep-notti-ios-sdk

**Vision:** Native iOS SDK (Swift) for Notti push notifications. It is the single source of truth for Notti's iOS logic, used directly by native apps and, later, by `zeep-notti-react-native` (and Flutter) as their iOS engine.
**For:** iOS developers who integrate Notti into native apps (UIKit/SwiftUI), and the Notti cross-platform SDKs that wrap it.
**Solves:** Today the iOS logic lives only inside `zeep-notti-react-native/ios`, coupled to the Turbo Module. Native apps can't use Notti, and every future wrapper would have to duplicate the Swift core. This follows the OneSignal model, where `react-native-onesignal` depends on `OneSignal-iOS-SDK`.

## Goals

- **Behavior parity with `react-native-notti` 0.8.0 on iOS (AD-017; was 0.6.0 until 2026-10-24).** Same backend contract, same retry/queue/session semantics, In-App Messages included. Success: the ported XCTest suite (~210 tests in the RN repo) passes against the new SDK, and a device-level checklist matches the RN SDK's behavior.
- **One-line integration for native apps.** `Notti.initialize(...)` plus capabilities and entitlement, with no AppDelegate edits (swizzling on by default). Success: the example app receives and clicks a push with only `initialize` called.
- **Consumable by the RN SDK.** Published as a CocoaPod that `react-native-notti` can depend on. Success (Milestone 2): the RN repo deletes its `ios/*.swift` core and keeps only the Turbo Module bridge.

## Tech Stack

**Core:**

- Language: Swift 5.9+ (language mode decided in Design; CI on Xcode 26)
- Platform: iOS 15.0+
- Frameworks: Foundation, UIKit, UserNotifications, Network (`NWPathMonitor`), CoreLocation (opt-in country only)
- Persistence: `UserDefaults` (suite `notti_prefs`, same keys as RN for on-device migration)

**Distribution:** Swift Package Manager (source, primary) and CocoaPods (podspec, required for RN consumption).

**Products:**

- App SDK (main app target)
- Notification Service Extension SDK (NSE target, must not link the app module)

**Testing:** XCTest with injected dependencies (`StubURLProtocol`, fake path monitor, per-test `UserDefaults` suite, injectable sleeper). This is the infrastructure already proven in the RN repo.

**Reference implementations:**

- `../zeep-notti-react-native/ios` (behavior and backend contract source)
- `OneSignal-iOS-SDK` v5 (API shape, swizzling, NSE and distribution patterns; its implementation is mostly ObjC, so it is reference only)

## Scope

**v1 includes (parity with RN 0.8.0, AD-017):**

- `initialize(appId, clientKey, baseUrl?)`; device registration (`POST /v1/apps/{appId}/devices`) and APNs token refresh
- `login` / `logout`, tags (add/remove, merge cache), `setSubscription`, email/phone set/clear
- Permission request plus two-axis `permission_status` and `last_unsubscribed_at`
- Device profile fields: `app_version`, `device_os`, `device_model`, `sdk_version`, `timezone_id`, `language`, with echo-based ack
- Session telemetry: first/last session, count, time, 60s foreground heartbeat, orphan close; opt-in country
- Engagement events `received` / `opened` / `clicked` (AD-003 option B semantics) with an offline queue (cap 32) and network-triggered flush
- Listeners: notification received (foreground), notification clicked, device id changed; cold-start initial click
- Retry policy: 5 attempts, 2/4/8/16s backoff; 408/429/5xx/network errors are transient
- APNs token and `UNUserNotificationCenter` delegate capture via swizzling, with an Info.plist opt-out and a manual forwarding API that coexists with other push SDKs
- NSE rich media (`notti_image_url`, https only, 10MB cap)
- `PrivacyInfo.xcprivacy` for both products
- Swift-first public API with `@objc` interop for ObjC hosts and the RN bridge
- In-App Messages: session fetch, four native layouts, `trackEvent`, click listener, `push_permission` button, own event queue (`in-app-messages`, AD-013, AD-019)
- Example app, CI, README

**Explicitly out of scope (v1):**

- Live Activities, Location tracking beyond the opt-in country
- Android/Flutter (separate repos)
- Backend contract changes (the SDK targets `zeep-notti` as-is: >= v0.11.0 for push, >= v0.23.0 for In-App, >= v0.24.0 for the AD-015/AD-039 logout behavior)
- NSE reporting `received` in the background or App Group shared state (needs contract and design work; deferred)
- Privacy consent gating API, Keychain storage for email/phone, Retry-After support (Milestone 3 candidates)
- Binary xcframework distribution (source-only for v1)

## Constraints

- **Technical:** the backend HTTP contract and UserDefaults keys must stay byte-compatible with RN 0.8.0. A device upgrading from an RN app to its native rewrite (or RN to RN-on-native-SDK) must not re-register as a new device.
- **Technical:** the NSE has a strict memory and time budget, so the extension product has no dependency on the app module.
- **Technical:** swizzling must never break the host's existing delegates. It forwards to the original implementations and guards against double-swizzling.
- **Privacy/LGPD:** email, phone and country are personal data. Nothing beyond what RN 0.8.0 collects; no PII in logs; logs off by default in release.
- **Resources:** solo maintainer (Julio). Behavior must stay in lockstep with the Kotlin implementation (`zeep-notti-react-native/android`, future `zeep-notti-android-sdk`).
