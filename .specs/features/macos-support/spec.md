# macOS Support Specification

## Problem Statement

`NottiSDK` runs on iOS only (`Package.swift` declares `.iOS(.v15)`, 22 files in `Sources/NottiSDK` import UIKit, and `swift test` on macOS does not compile). Native macOS apps cannot receive Notti pushes. A second SDK repo would copy about 9k lines of platform-neutral core (API client, event store, retry/backoff, `notti_prefs` keys), and every core fix (AD-018 style) would then land in four places (RN, iOS, Android, macOS), against AD-001. This feature makes the same package build and run on macOS, with macOS as its own platform value on the wire (`macos`), never `ios`.

The backend side (accept `macos`, send through APNs with the macOS bundle id) is a separate spec in `zeep-notti`: `.specs/features/macos-platform/`. It must be deployed before the first macOS release of this SDK, otherwise device registration answers 422.

## Goals

- [ ] A native AppKit app adds `NottiSDK` through SPM or CocoaPods, calls `Notti.initialize`, accepts the permission prompt and appears in the dashboard as a `macos` Device that receives a push.
- [ ] The iOS behavior, the public API surface and the on-disk keys do not change: every existing iOS test still passes and the test count does not drop.
- [ ] One Swift implementation of the core. The macOS code is limited to the platform seam (delegate integration, lifecycle, permission, device info) and a macOS source set; no copy of core files.
- [ ] The macOS device reports `platform: "macos"` and `sdk_name: "macos"`, so the backend can tell the platforms apart without parsing `device_os`.
- [ ] A Notification Service Extension on macOS attaches `notti_image_url` media, like on iOS.
- [ ] The privacy and logging rules of `AGENTS.md` (LGPD) hold on macOS with no exception.

## Out of Scope

| Feature | Reason |
| --- | --- |
| In-App Messages rendering on macOS (`NSPanel`/AppKit port of the 1.5k-line UIKit layer) | No demand recorded, and the backend v1 never serves In-App to `macos` devices (backend MACBE-19 to MACBE-21). Own spec `macos-in-app` if it is asked for |
| Mac Catalyst | A Catalyst app links the UIKit path and registers like an iOS app, so its platform value is a separate decision. Listed in `ROADMAP.md` Future Considerations; not changed here |
| macOS versions below 12, other Apple platforms (tvOS, watchOS, visionOS) | Not requested. macOS 12 is the pair of the current iOS 15 floor |
| Action buttons, App Group, badge, `received` from the NSE | Same M3 items as iOS (`nse-shared-state`, `notification-action-buttons`) |
| A separate `NottiSDKmacOS` product, pod or repo | The decision of this spec: same products `NottiSDK` and `NottiSDKExtension`, multiplatform |
| Menu bar / LSUIElement apps without a Dock presence beyond what AppKit already delivers | Behavior is whatever `NSApplication` gives; no special handling |
| Sparkle or any updater integration | Host concern |
| Wrapper SDKs on macOS (React Native macOS, Flutter) | `sdk_name` for wrappers stays as in AD-024; no macOS wrapper exists |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| One package, two platforms | `platforms: [.iOS(.v15), .macOS(.v12)]`, same products `NottiSDK` and `NottiSDKExtension`, podspecs get `s.osx.deployment_target = '12.0'`, AD-012 two-pod layout stays | Avoids duplicating the core (AD-001). Source stays one tree, split by `#if os(iOS)` / `#if os(macOS)` and `canImport` | y (Julio, 2026-11-14: macOS in this package, own wire value) |
| Wire value | `platform: "macos"` on `POST /devices`, `sdk_name: "macos"` on the profile PATCH, `NottiSDKVersion.name` becomes platform-dependent (`ios` / `macos`) | Julio, 2026-11-14: a new enum value so macOS is not tied to iOS. Wrappers keep overriding `sdk_name` through `@_spi(Wrapper)` (AD-024) | y |
| Public API | No new public symbol. `Notti`, `Notti.Notifications`, `Notti.User`, the manual forwarding API and the `@objc` facade keep their signatures on both platforms | Cross-platform host code (shared Swift package for iOS and macOS) compiles unchanged. Any addition updates `PUBLIC_SURFACE.txt` in the same commit | y (proposal) |
| In-App API on macOS | The `Notti.InApp` entry points compile and are no-ops (no fetch, no UI, no event queue growth) | `@available(macOS, unavailable)` would break shared host code. The backend does not serve In-App to `macos`, so a no-op is consistent | y (Julio, 2026-11-14: no In-App on macOS for now; the no-op default is kept, `unavailable` stays a later option) |
| Delegate integration | Swizzle `NSApplicationDelegate` token/failure/remote-notification callbacks with the same opt-out key `NottiDisableSwizzling` and the same manual forwarding API; `UNUserNotificationCenterDelegate` swizzle is shared with iOS | Same host contract on both platforms (AD-004). macOS selectors and the missing completion handler on remote notifications differ from UIKit and need their own tests | y (behavior), Design (selectors) |
| Remote-notification registration | `NSApplication.shared.registerForRemoteNotifications()`; token hex-encoded exactly as on iOS | Same APNs token format [Provável]; to prove in the device checklist | y |
| Cold-start click | The click that launched the app is captured before `initialize` and replayed to the first listener, like iOS (DEL cold-start) | Contract parity. How macOS delivers it (`didReceive` after launch vs the launch notification key) is a Design spike [Incerto] | y (behavior), Design spike (how) |
| Session lifecycle | `NSApplication.didBecomeActive` / `didResignActive` / `willTerminate` replace the UIApplication notifications; there is no `beginBackgroundTask`, so the session-end flush on terminate is bounded (no unbounded wait that delays quitting) | macOS has no background-task API. The exact mechanism (`ProcessInfo.performExpiringActivity` vs a short bounded wait) is a Design decision | y (behavior), Design (how) |
| Device info | `device_os` from `ProcessInfo.operatingSystemVersion`; `device_model` from the hardware model identifier (for example `Mac14,2`), nil when unreadable; no serial number, no hardware UUID, no username | AGENTS.md privacy rule: no new identifier. `device_model` is already sent on iOS | y (proposal), Design confirms the source |
| Entitlements and signing | The SDK does not add entitlements. The host needs `com.apple.developer.aps-environment` and a provisioning profile for Developer ID distribution. Documented in README, checked in the device checklist | Cannot be enforced from a library | y |
| Extension on macOS | `NottiSDKExtension` and `NottiShared` compile for macOS and stay free of AppKit and UIKit (`check-extension-safety.sh` bans `AppKit` and `NSApplication` too) | Same extension-safety contract, same `notti_image_url` behavior | y |
| Order of release | Backend `macos-platform` deployed first, then SDK `0.3.0` (minor: new platform, no breaking change) | A registration before the backend knows `macos` answers 422 and the SDK logs and retries | y (Julio, 2026-11-14: `0.3.0`) |
| Test destination | CI adds `platform=macOS` to the XCTest run; the simulator run stays for iOS | After this feature the core is no longer UIKit-bound on macOS | y |

Open questions: none. Julio confirmed on 2026-11-14: `0.3.0` as the first macOS version and no In-App on macOS for now (the entry points stay compiled and inert). The backend also accepts a `.p12` or a `.p8` macOS credential, chosen by the App owner like iOS; that is invisible to the SDK, which only reports `platform: "macos"`.

---

## User Stories

### P1: Build and integrate on macOS ⭐ MVP

**User Story**: As a macOS developer, I want to add `NottiSDK` to an AppKit app so that it compiles and links without UIKit.

**Why P1**: Nothing else is testable until the package builds for macOS.

**Acceptance Criteria**:

1. MAC-01: WHEN the package is built for `platform=macOS` THEN `NottiShared`, `NottiSDK`, `NottiSDKBootstrap` and `NottiSDKExtension` SHALL compile with no UIKit symbol and no warning that `SwiftLint --strict` rejects.
2. MAC-02: WHEN the package is built for an iOS simulator and for an iOS device THEN the result SHALL be unchanged: every existing test passes and the total test count is not lower than before the feature.
3. MAC-03: WHEN a host adds the pod `NottiSDK` or `NottiSDKExtension` on macOS THEN `pod lib lint --platforms=ios,osx` SHALL pass for both pods, static and dynamic linkage.
4. MAC-04: WHEN `NottiShared` or `NottiSDKExtension` is built THEN neither SHALL import `UIKit` or `AppKit`, nor use `UIApplication`, `NSApplication` or `NSWorkspace` (`scripts/check-extension-safety.sh` enforces it for both platforms).
5. MAC-05: WHEN a type or method is app-only THEN it SHALL be marked unavailable in app extensions for both platforms (`iOSApplicationExtension` and `macOSApplicationExtension`), and `check-public-surface.sh` SHALL fail when a top-level public type lacks both.

**Independent Test**: `xcodebuild build -scheme NottiSDK-Package -destination 'platform=macOS'` and the existing iOS test run both pass.

---

### P1: Register the Mac and receive a push ⭐ MVP

**User Story**: As a macOS developer, I want `initialize` plus the permission prompt to register the Mac with Notti so that a push sent from the dashboard shows up on it.

**Why P1**: This is the feature's value.

**Acceptance Criteria**:

1. MAC-06: WHEN `Notti.Notifications.requestPermission` is called on macOS and the user allows THEN the SDK SHALL call `NSApplication.shared.registerForRemoteNotifications()` once on the main thread and report the permission result like iOS.
2. MAC-07: WHEN the system returns an APNs device token THEN the SDK SHALL send it hex-encoded to `POST /devices` with `platform: "macos"`, reusing the iOS retry/backoff and the serial `workQueue`.
3. MAC-08: WHEN the profile is synced THEN `sdk_name` SHALL be `macos` for the native SDK and the wrapper's own value when a wrapper passes one (AD-024), and `sdk_version` SHALL be `NottiSDKVersion.current`.
4. MAC-09: WHEN `NottiDisableSwizzling` is not set THEN the SDK SHALL install its `NSApplicationDelegate` token and failure callbacks and its `UNUserNotificationCenterDelegate` forwarding once (double-swizzle guard), forwarding to the host's originals.
5. MAC-10: WHEN `NottiDisableSwizzling` is `YES` THEN the SDK SHALL install nothing and the manual forwarding API SHALL deliver the same results as the swizzled path.
6. MAC-11: WHEN the host uses SwiftUI `@NSApplicationDelegateAdaptor` THEN the SDK SHALL swizzle the adaptor's delegate, not a placeholder (parity with AD-016).
7. MAC-12: WHEN registration fails (`didFailToRegisterForRemoteNotificationsWithError`) THEN the SDK SHALL log `"\(error.domain)#\(error.code)"` at `.error`, never `localizedDescription`, and retry on the next launch like iOS.

**Independent Test**: A fake `NSApplicationDelegate` class (own `objc_allocateClassPair`, unique name) receives a token; the test asserts the `POST /devices` body has `platform: "macos"`. No unit test swizzles `NSApplication` or `UNUserNotificationCenter`.

---

### P1: Clicks, silent pushes and lifecycle ⭐ MVP

**User Story**: As a macOS developer, I want clicks, silent pushes and sessions to behave like iOS so that metrics and deep links are consistent across platforms.

**Why P1**: Without them the backend funnel (`received`, `opened`, `clicked`) is empty for macOS.

**Acceptance Criteria**:

1. MAC-13: WHEN the user clicks a notification while the app runs THEN the SDK SHALL report `opened`/`clicked` and call the click listeners with the payload untouched; the SDK SHALL NOT open any URL from the payload (`check-no-url-open.sh` covers `NSWorkspace.shared.open`).
2. MAC-14: WHEN the click launched the app THEN the SDK SHALL replay it to the first listener registered after `initialize` (take-then-listen).
3. MAC-15: WHEN a silent push (`content-available`) arrives THEN the SDK SHALL report `received` once and call the host's original handler, with no completion handler assumed (macOS callback has none).
4. MAC-16: WHEN the app becomes active, resigns active or terminates THEN the SDK SHALL start, pause and end the session like iOS, and on terminate SHALL flush with a bounded wait so quitting is never delayed by the network.
5. MAC-17: WHEN `device_os`/`device_model` are read THEN they SHALL come from `ProcessInfo` and the hardware model identifier only, and `device_model` SHALL be omitted when unreadable.
6. MAC-18: WHEN any of the above logs THEN it SHALL go through `NottiLogger` and never include email, phone, token, external user id, country, tag values or a URL.

**Independent Test**: Unit tests drive the macOS adapter with the injected providers (the existing `NottiPlatformProviders` seam); `check-launch-hook-purity.sh` still passes for the `+load` hook.

---

### P2: Rich media in a macOS Notification Service Extension

**User Story**: As a macOS developer, I want the same two-line NSE forwarding so that a push with `notti_image_url` shows its media.

**Why P2**: Pushes work without it; images are the visible polish.

**Acceptance Criteria**:

1. MAC-19: WHEN `NottiNotificationServiceExtension.didReceive` runs in a macOS extension THEN it SHALL behave as NSE-01..NSE-09 of `nse-rich-media`, including the https-only, 10 MiB and 20 s limits, with the same logging rules.
2. MAC-20: WHEN `NottiSDKExtension` is built for macOS THEN `scripts/check-package-graph.sh` SHALL still fail if it reaches `NottiSDK` or `NottiSDKBootstrap`.

**Independent Test**: The existing NSE test suite runs on the macOS destination with the stub session.

---

### P2: In-App entry points are inert on macOS

**User Story**: As a developer of shared iOS and macOS code, I want the In-App API to compile on macOS so that I do not need `#if` around every call.

**Why P2**: Compile parity; the feature itself is out of scope.

**Acceptance Criteria**:

1. MAC-21: WHEN `Notti.InApp.trackEvent` or a click listener is used on macOS THEN the call SHALL compile, SHALL do nothing and SHALL NOT grow the event queue or fetch messages.
2. MAC-22: WHEN `PUBLIC_SURFACE.txt` is regenerated THEN it SHALL show no new public symbol caused by macOS support. The only allowed difference is the return type of `didReceiveRemoteNotification` on macOS (`Void`, because `UIBackgroundFetchResult` does not exist there): two macOS lines in `PUBLIC_SURFACE.txt`, same names as iOS (decision D4, approved by the owner on 2026-11-14).

**Independent Test**: A macOS XCTest calls the In-App entry points and asserts no network request and no stored event.

---

### P2: Docs, privacy manifest and CI

**User Story**: As a maintainer, I want the privacy manifest, README and CI to cover macOS so that release 0.3.0 is shippable.

**Why P2**: Required for the release, not for the code to work.

**Acceptance Criteria**:

1. MAC-23: WHEN a required-reason API or a collected data type is used on macOS THEN the matching `PrivacyInfo.xcprivacy` SHALL declare it in the same change (PKG-13); `device_model` and `device_os` are declared if not already.
2. MAC-24: WHEN CI runs THEN it SHALL build and test on `platform=macOS` besides the iOS simulator, run every `scripts/check-*.sh`, and `pod lib lint` for both platforms.
3. MAC-25: WHEN the README is read THEN it SHALL cover macOS install (SPM and CocoaPods), the `aps-environment` entitlement and provisioning profile, the swizzling opt-out on `NSApplicationDelegate`, the no-op In-App behavior and the backend minimum version.
4. MAC-26: WHEN `docs/DEVICE_CHECKLIST.md` is read THEN it SHALL have a macOS section (signed app, permission prompt, token, push, click, cold-start click, silent push, quit while a session is open).

**Independent Test**: Local equivalent of `ci.yml` is green (GitHub billing may still block the hosted run, as for earlier features).

---

## Edge Cases

- WHEN the app runs unsandboxed or sandboxed THEN the SDK SHALL work in both (`notti_prefs` suite lives in the app's own container) and SHALL NOT require a network or file entitlement beyond the standard client entitlement.
- WHEN `registerForRemoteNotifications` is never answered (no entitlement, no profile) THEN the SDK SHALL NOT crash or block `initialize`; the device stays unregistered and a `.error` line names the domain/code only.
- WHEN the Mac sleeps with a session open THEN the session SHALL end on resign active or terminate only, never on a timer the SDK invents.
- WHEN the same user logs in on an iOS device and a Mac THEN each SHALL be its own Device with its own platform; `logout` unlinks only the current device (AD-015).
- WHEN the host runs the SDK under Rosetta or on Intel THEN behavior SHALL be identical (no architecture branch).
- WHEN the backend does not know `macos` yet (422) THEN the SDK SHALL treat it like any other 4xx registration error: log domain#code, no crash, no infinite tight retry.
- WHEN the token comes from an APNs sandbox build THEN the SDK SHALL send it unchanged; choosing sandbox vs production is a backend per-App setting (backend spec), not an SDK decision.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| MAC-01 | P1: Build and integrate | Design | Pending |
| MAC-02 | P1: Build and integrate | Design | Pending |
| MAC-03 | P1: Build and integrate | Design | Pending |
| MAC-04 | P1: Build and integrate | Design | Pending |
| MAC-05 | P1: Build and integrate | Design | Pending |
| MAC-06 | P1: Register and receive | Design | Pending |
| MAC-07 | P1: Register and receive | Design | Pending |
| MAC-08 | P1: Register and receive | Design | Pending |
| MAC-09 | P1: Register and receive | Design | Pending |
| MAC-10 | P1: Register and receive | Design | Pending |
| MAC-11 | P1: Register and receive | Design | Pending |
| MAC-12 | P1: Register and receive | Design | Pending |
| MAC-13 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-14 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-15 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-16 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-17 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-18 | P1: Clicks, silent, lifecycle | Design | Pending |
| MAC-19 | P2: NSE on macOS | - | Pending |
| MAC-20 | P2: NSE on macOS | - | Pending |
| MAC-21 | P2: In-App inert | - | Pending |
| MAC-22 | P2: In-App inert | - | Pending |
| MAC-23 | P2: Docs, privacy, CI | - | Pending |
| MAC-24 | P2: Docs, privacy, CI | - | Pending |
| MAC-25 | P2: Docs, privacy, CI | - | Pending |
| MAC-26 | P2: Docs, privacy, CI | - | Pending |

**Coverage:** 26 total, 0 mapped to tasks, 26 unmapped (Design and Tasks not written yet)

---

## Success Criteria

- [ ] A signed AppKit example target in `Example/` registers, receives a push sent from the dashboard and reports `opened` and `clicked`, with the backend `macos-platform` deployed.
- [ ] iOS: zero behavior change; test count not lower than the pre-feature count; `scripts/check-*.sh` green.
- [ ] No core file exists twice; the macOS-only code is under a `Platform`/`Delegates` macOS source set and its tests.
- [ ] `PUBLIC_SURFACE.txt` and `SPI_SURFACE.txt` show no new public or SPI symbol, or the diff is reviewed and approved.
- [ ] Release `0.3.0` through the existing flow (version in `NottiSDKVersion.current` and both podspecs, CHANGELOG), tag and `pod trunk push` by Julio.

## Dependencies

- Backend spec `zeep-notti/.specs/features/macos-platform/` (accept `platform: "macos"` and `sdk_name: "macos"`, APNs send with the macOS bundle id). Blocks the release, not the development (the SDK can be built and unit-tested against a stub).
- AD-022 (CocoaPods trunk read-only on 2026-12-02): a macOS release after that date follows plan B.
