# State

**Last Updated:** 2026-10-09
**Current Work:** `package-foundation` + `core-port` specs written (Specify), approved 2026-10-09. Design approved 2026-10-09. Tasks drafted 2026-10-09 (package-foundation T1-T12, core-port C1-C13, `.specs/codebase/TESTING.md`), approved 2026-10-09. Executing package-foundation: T1–T3 done. Next: T4.

---

## Recent Decisions (Last 60 days)

### AD-001: This SDK is the single source of truth for Notti iOS logic (2026-10-09)

**Decision:** The Swift core currently in `zeep-notti-react-native/ios` is extracted into this repo. In M2, the RN SDK depends on this pod and deletes its own Swift core.
**Reason:** Removes a second Swift implementation (RN's AD-001 already forces Swift + Kotlin duplication). Mirrors OneSignal, where `react-native-onesignal` wraps `OneSignal-iOS-SDK`.
**Trade-off:** RN iOS releases now depend on this SDK's releases. The public API must stay `@objc`-bridgeable for the Turbo Module. Until M2 ships, both copies exist and fixes must be applied twice.
**Impact:** The core port preserves behavior, backend contract and UserDefaults keys exactly. Any behavior change goes through a spec in this repo first.

### AD-002: v1 scope = behavior parity with react-native-notti 0.6.0 (2026-10-09)

**Decision:** M1 ships every iOS behavior RN 0.6.0 has (registration, identity, tags, email/phone, permission, profile fields, session telemetry, received/opened/clicked events, NSE rich media). No new behavior.
**Reason:** Keeps the port verifiable against the existing XCTest suite and spec IDs. New features go in M3.
**Trade-off:** Known RN gaps (no consent API, PII in UserDefaults, no Retry-After) ship in v0.1.0 too.
**Impact:** Feature specs in M1 reference the RN requirement IDs instead of redefining behavior.

### AD-003: Distribution via SPM (source) + CocoaPods (2026-10-09)

**Decision:** Source-based `Package.swift` with two products (app SDK and NSE SDK) plus a podspec.
**Reason:** SPM is the native default; the podspec is required for RN (CocoaPods) consumption in M2. OneSignal's binary-only SPM adds release tooling we don't need yet.
**Trade-off:** Two manifests to keep in sync; CI must build both.
**Impact:** The NSE product must not depend on the app module. Shared code goes in an internal target.

### AD-004: APNs/delegate capture via swizzling with opt-out (2026-10-09)

**Decision:** Swizzling is on by default (OneSignal model). An Info.plist key disables it; a manual forwarding API is always available.
**Reason:** One-line integration for native apps. The RN SDK today requires manual AppDelegate forwarding and taking over `UNUserNotificationCenter.delegate`, which conflicts with other push SDKs.
**Trade-off:** Swizzling is ObjC-runtime work in Swift, fragile across iOS versions and hard to unit test. It must forward to host originals and guard against double-swizzle (OneSignal `SwizzlingForwarder` pattern).
**Impact:** Its own feature (`delegate-integration`) with a dedicated test strategy. Manual calls made while swizzling is active must be ignored with a warning, to avoid double-processing.

### AD-005: Privacy manifest declares more than RN 0.6.0 (2026-10-09)

**Decision:** The `NottiSDK` privacy manifest declares Coarse Location (opt-in country) and Product Interaction (session telemetry), in addition to RN's Email, Phone and UserDefaults `CA92.1`.
**Reason:** These are data the SDK actually collects and links to the device record. Under-declaring them is an App Store review and LGPD transparency risk.
**Trade-off:** Integrators' App Store privacy labels gain two entries compared to RN 0.6.0. The RN manifest should be aligned in M2.
**Impact:** package-foundation PKG-11; README data-collection section in `example-and-release`.

### AD-006: Cross-target sharing uses `package` access + `-package-name NottiSDK` in the podspec (2026-10-09)

**Decision:** Keep the design's primary option. `NottiShared` declarations use `package` access. The podspec sets `pod_target_xcconfig OTHER_SWIFT_FLAGS = '$(inherited) -package-name NottiSDK'`. The `@_spi(NottiInternal)` fallback is not needed.
**Reason:** Spike (package-foundation T1, throwaway in the scratchpad, Xcode 27.0, CocoaPods 1.17.0) with subspecs Shared/Core/Extension and a `package` symbol used from Core and Extension:
- SPM `xcodebuild build -scheme Spike-Package`: BUILD SUCCEEDED.
- `pod lib lint --platforms=ios` (frameworks): passed, 0 warnings.
- `pod lib lint --platforms=ios --use-libraries` (static libraries, the RN default): passed.
- `pod lib lint --platforms=ios --subspec=Extension`: passed.
- Negative control without the flag: fails with `error: the package access level used on 'SharedVersion' requires a package name; set it with the compiler flag -package-name`. So the flag is what makes it work, not a coincidence.
**Trade-off:** Relies on an undocumented-for-CocoaPods compiler flag passed through `OTHER_SWIFT_FLAGS`. The CI `pod-lint` job is the regression guard. Not verified on Xcode 26.x locally; CI (`macos-26`) covers it in T12.
**Impact:** package-foundation T3 onward uses `package`; design.md "Cross-target visibility" stands as written.

---

## Active Blockers

_none_

---

## Lessons Learned

_none yet._ Candidate lessons inherited from the RN repo (`../zeep-notti-react-native/.specs/LESSONS.md`) apply as guidance only:

- L-001: test the layer that implements the acceptance criterion, not just the facade that calls it
- L-002: the Verifier re-derives proof of properties and does not trust task notes

---

## Quick Tasks Completed

| #   | Description | Date | Commit | Status |
| --- | ----------- | ---- | ------ | ------ |

---

## Deferred Ideas

- [ ] NSE reports `received` in the background through an App Group (needs a backend/contract review). Captured during: project init
- [ ] Badge increment in the NSE. Captured during: project init
- [ ] Privacy consent gating API (`setConsentRequired` / `setConsentGiven`) and a local data wipe. Captured during: project init
- [ ] Keychain storage for email/phone (LGPD). Captured during: project init
- [ ] Binary xcframework distribution. Captured during: project init

---

## Todos

- [x] Pod/package name: `NottiSDK` (Julio, 2026-10-09). NSE product `NottiSDKExtension` confirmed (2026-10-09). License MIT.
- [x] `git init` (branch `main`, 2026-10-09).
- [x] GitHub remote `origin` = `git@github.com:zeeplabs/zeep-notti-ios-sdk.git` (2026-10-09).
- [x] Swift 5 language mode for M1; Swift 6 strict concurrency deferred (2026-10-09).
- [x] RN `sdk-core-v1` "Needs Fix" item (native prerequisite path, SDK-04) carried into core-port: CORE-08, task C9.

---

- [x] Privacy manifest scope: see AD-005.
- [x] Spike result: CocoaPods honors `-package-name` via `OTHER_SWIFT_FLAGS`. See AD-006.

## Preferences

**Model Guidance Shown:** never
