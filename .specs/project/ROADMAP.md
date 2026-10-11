# Roadmap

**Current Milestone:** M1 - Native SDK with RN 0.6.0 parity
**Status:** In Progress

---

## M1 - Native SDK with RN 0.6.0 parity (v0.1.0)

**Goal:** A native iOS app can integrate Notti via SPM or CocoaPods and get the same behavior as `react-native-notti` 0.6.0 on iOS.
**Target:** Ported XCTest suite green in CI; example app passes the device checklist; tagged `0.1.0`.

### Features

**package-foundation** - DONE (2026-10-10; PR #1 + PR #2; Verifier PASS round 6)

- Git repo, `Package.swift` (two products: app SDK and NSE SDK) and podspec `NottiSDK` (products `NottiSDK` + `NottiSDKExtension`)
- Module layout, internal shared target for code used by both products (payload parsing, key constants)
- CI workflow (build and test both products on the simulator), SwiftLint, `PrivacyInfo.xcprivacy` skeletons

**core-port** - DONE (2026-10-10; PR #3; Verifier PASS round 3)

- Port `NottiCore`, `NottiApiClient`, `NottiDeviceStore`, `NottiEventStore`, `NottiEventBuffer`, `NottiNetworkObserver` and `NottiNotificationParsing` from the RN repo
- Remove the RN coupling (`Notti.mm`, `@objc` NSDictionary shell); replace the global statics (`NottiImpl.activeCore` / `eventStore`) with an owned dependency graph that stays cold-start safe
- `sdk_version` becomes a native constant
- Port the XCTest suite and keep the counts traceable to the original requirement IDs (SDK-, SDKCTR-, SDKOPEN-, SEGTEL-, DPF-)

**public-api** - DONE (2026-10-11; T1-T14 on branch `feat/public-api`; Verifier PASS round 2; 356 tests)

- Swift-first facade: `Notti.initialize`, `login`/`logout`, `Notti.User` (tags, email, phone, subscription), `Notti.Notifications` (requestPermission, listeners, initial click), device id accessor and observer
- `@objc` interop surface usable by ObjC hosts and the future RN bridge
- Debug log level (off by default in release, no PII)

**delegate-integration** - Execute done (2026-10-11; T1-T14 on branch `feat/delegate-integration`; 465 tests); Verifier pending

- Swizzle `UIApplicationDelegate` APNs callbacks and the `UNUserNotificationCenterDelegate` (`willPresent`, `didReceive`), forwarding to the host's originals, with a double-swizzle guard
- Info.plist opt-out key; manual forwarding API (`didRegisterForRemoteNotifications`, `willPresent`, `didReceive`) for opted-out or multi-SDK hosts
- Cold-start click capture before `initialize`
- Silent-push `received` reporting; deep-link passthrough (no URL opening); ObjC launch hook target `NottiSDKBootstrap`, proved by CI scripts

**nse-rich-media** - Execute done (2026-10-11; T1-T16 on branch `feat/nse-rich-media`; 584 tests); Verifier pending

- NSE product: `didReceive` / `serviceExtensionTimeWillExpire` helpers, `notti_image_url` attachment (https, 10MB cap, jpg/png/gif/mp4/mp3)
- async download within the NSE budget; deliver best attempt on expiry

**example-and-release** - PLANNED

- SwiftUI example app plus an NSE target exercising every public method
- README (setup via SPM/CocoaPods, capabilities, swizzling opt-out, data collection, storage keys, LGPD note, known limitations), CHANGELOG
- Device validation checklist (carried over from RN 0.6.0 open items); tag `0.1.0`

---

## M2 - RN SDK on top of the native SDK

**Goal:** `react-native-notti` uses this SDK as its iOS engine. Only one Swift implementation exists.

### Features

**rn-consumes-native-sdk** - PLANNED (work happens mostly in `zeep-notti-react-native`)

- RN podspec depends on this pod; the Turbo Module bridge maps JS calls and events onto the public `@objc` API
- RN's `ios/*.swift` core and its tests are deleted
- On-device upgrade path verified (same UserDefaults keys, same device id)

---

## M3 - Beyond parity

**Goal:** Close known RN-era gaps and add OneSignal-grade features.

### Features

**privacy-consent** - PLANNED: `setConsentRequired` / `setConsentGiven` gating, local data wipe API
**pii-keychain-storage** - PLANNED: email/phone moved from UserDefaults to Keychain, with migration
**nse-shared-state** - PLANNED: App Group (configurable), `received` reported from the NSE, badge increment
**notification-action-buttons** - PLANNED: parity with the RN `SDKACT-` spec, once that spec is done
**queue-resilience** - PLANNED: per-event TTL, `Retry-After`, no head-of-line blocking

---

## Future Considerations

- Binary xcframework distribution
- Live Activities, In-App Messages
- Mac Catalyst
- Flutter wrapper consuming this SDK (`zeep-notti-flutter`)
