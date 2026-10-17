# Example App and Release 0.1.0 Specification

## Problem Statement

All SDK code for M1 is merged (`core-port`, `public-api`, `delegate-integration`, `nse-rich-media`), but nothing proves it works inside a real app, and an integrator has no documentation. The README is a stub, the CHANGELOG has one line, and many behaviors are only build-verified or unit-tested: the APNs/permission/location providers, the launch hook in a CocoaPods app, the SwiftUI delegate check, the NSE wiring and the privacy manifest at App Store validation. This feature adds an example app that exercises every public method, writes the integrator docs, records the device checklist, and prepares `0.1.0` so Julio can tag it.

## Goals

- [ ] One example app (SwiftUI, with a Notification Service Extension target) that calls every public API of `NottiSDK` and `NottiSDKExtension`, builds on CI with placeholder config and runs on a device with Julio's real appId.
- [ ] The same example consumes the SDK through SPM and through CocoaPods, so PKG-06 and the CocoaPods resource branch get a real consumer.
- [ ] A README an integrator can follow without reading the specs: install, capabilities, NSE wiring, swizzling opt-out, manual forwarding, data collected, storage keys, LGPD note, known limitations.
- [ ] A device validation checklist that lists every item still unproven, each with the exact steps and the expected result.
- [ ] `0.1.0` ready to tag: CHANGELOG entry, version constants aligned, CI green. No tag, GitHub Release or `pod trunk push` made by the agent.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Creating the git tag, GitHub Release, `pod trunk push` | Julio does them after the device checklist (decided 2026-10-12) |
| Running the device checklist | Needs a physical iPhone, a real APNs push and Julio's appId. The agent prepares it, Julio runs it |
| Publishing the example to TestFlight / App Store | The example is a developer tool, not a product |
| Changing SDK behavior | Findings from the example become todos or a follow-up spec (AD-001). Only a blocking bug fix gets its own commit with a test |
| Committing credentials, appId, client key or push token | LGPD and secret rules; config stays in an untracked xcconfig |
| Backend changes (partial unique index on `received`) | Optional, tracked in `STATE.md` |
| RN bridge | M2 |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Project generation | XcodeGen: `Example/project.yml` versioned, `.xcodeproj` generated and git-ignored. CI installs it with `brew` | `pbxproj` is unreviewable by hand; no tool is installed locally yet | y (Julio, 2026-10-12) |
| Config | `Example/Config/Example.xcconfig.sample` (placeholders `example.invalid`, `fixture`) is versioned. `Example.local.xcconfig` is git-ignored and holds the real appId, client key and host. The app reads them from Info.plist keys fed by the xcconfig | No secret in the repo. CI builds with the sample | y (Julio, 2026-10-12) |
| Release scope | Everything via PR; tag, GitHub Release and `pod trunk push` stay with Julio | Outward-facing and irreversible | y (Julio, 2026-10-12) |
| Example dependency modes | SPM (default) and CocoaPods (separate `Podfile`, same sources), both built in CI | Closes PKG-06 and the CocoaPods `Resources` branch todo | y (Julio, 2026-10-12) |
| Example location | `Example/` at the repo root, outside the SPM package graph (not a target of `Package.swift`) | The package must not ship the example; `check-package-graph.sh` must keep passing | [Provável], confirm in Design |
| Bundle ids / team | `com.example.NottiExample` and `.NotificationService` for CI; the real ids and team come from `Example.local.xcconfig` | Push needs a signed app with the Push capability; CI cannot sign | [Provável] |
| Version | `NottiSDKVersion.current` and `s.version` are already aligned; this feature only changes them if they are not `0.1.0` | `check-version.sh` guards drift | Verify in Design |
| Privacy manifest open items | Device ID decision and the legal confirmation of the UserID text stay open and are listed in the checklist and the README limitations; they gate the tag, not the PR | AD-005, N7 (non-blocking) | Open, Julio / legal |
| Info.plist key `NottiDisableSwizzling` | Documented as a public contract | Confirmed in delegate-integration (2026-10-11) | y |

Open questions: none that block Specify. The two Design spikes are the XcodeGen setup for an app plus NSE sharing the SDK package, and the CocoaPods static/dynamic variants (`use_frameworks!` on and off).

---

## User Stories

### P1: Example app exercises the whole public API ⭐ MVP

**User Story**: As an SDK maintainer, I want an app that calls every public method so that I can see the SDK work on a device and catch integration bugs the unit tests cannot.

**Why P1**: It is the only way to close the device-only todos.

**Acceptance Criteria**:

1. EXR-01: WHEN the example builds with `Example.xcconfig.sample` THEN it SHALL compile for the simulator and for a generic device with `CODE_SIGNING_ALLOWED=NO`, with zero warnings from the SDK targets.
2. EXR-02: WHEN a maintainer opens the app THEN each public member listed in `.specs/codebase/PUBLIC_SURFACE.txt` for `Notti`, `Notti.User`, `Notti.Notifications` and `NottiNotificationServiceExtension` SHALL be reachable from a screen (button, field or visible log row). A script SHALL fail CI when a public member is not referenced by the example (drift guard).
3. EXR-03: WHEN the app runs THEN it SHALL show the device id, the permission result, received/clicked payloads (keys only, never values) and the SDK log level control. It SHALL NOT display or log the client key, push token, email or phone.
4. EXR-04: WHEN the app starts with the swizzling default THEN it SHALL use no manual forwarding; a second launch mode (`NottiDisableSwizzling = YES` build setting) SHALL exercise the manual forwarding API.
5. EXR-05: WHEN `Example.local.xcconfig` is absent THEN the build SHALL use the sample and the app SHALL show a visible "not configured" state instead of calling the backend.
6. EXR-06: WHEN secrets are searched (`git grep` of the real appId and key patterns, and `check-no-secrets` if added) THEN none SHALL be found in tracked files.

**Independent Test**: build the example on the CI runner; on a device with the local xcconfig, tap every control and confirm the matching request in the Notti dashboard.

---

### P1: NSE target and rich media on a device ⭐ MVP

**User Story**: As an SDK maintainer, I want the example's Notification Service Extension to use the two forwarding calls so that I can prove an image push renders end to end.

**Acceptance Criteria**:

1. EXR-07: WHEN the example builds THEN the NSE target SHALL contain only the `@objc(NotificationService)` subclass and the two forwarding calls from the README, and link `NottiSDKExtension` (never `NottiSDK`).
2. EXR-08: WHEN built with `APPLICATION_EXTENSION_API_ONLY=YES` THEN the NSE target SHALL compile.
3. EXR-09: WHEN a real push with `notti_image_url` reaches the device THEN the notification SHALL show the image. This is verified by Julio through the checklist (not by CI).

---

### P1: README for integrators ⭐ MVP

**User Story**: As an iOS developer evaluating Notti, I want a README that takes me from zero to a working push so that I do not read the specs.

**Acceptance Criteria**:

1. EXR-10: WHEN a developer follows the README THEN it SHALL cover, in order: requirements, install by SPM and CocoaPods (app and NSE), capabilities (Push Notifications, Background Modes > Remote notifications), `Notti.initialize`, permission, identity and tags, listeners, the NSE wiring snippet, the swizzling opt-out key plus the manual forwarding calls, and Objective-C usage.
2. EXR-11: WHEN a developer reads the data section THEN it SHALL list every field sent to the backend, the UserDefaults suite and keys, the privacy manifest declarations and what the app owner must declare in App Store privacy labels, with an LGPD note that recommends internal legal review and never claims compliance.
3. EXR-12: WHEN a developer reads known limitations THEN it SHALL list at least: the NSE does not run in the Simulator, double observation with an overriding delegate that calls `super`, no `received` for visible pushes without `notification_id`, no consent API in 0.1.0, PII in UserDefaults, no `Retry-After`, and the unproven items from the checklist.
4. EXR-13: WHEN the README shows code THEN every snippet SHALL compile; a CI step SHALL build the snippets from the example sources (the README snippets are excerpts of files under `Example/`, checked by a script) so they cannot drift.
5. EXR-14: WHEN the README mentions a Notti host or key THEN it SHALL use placeholders only, and the production default host SHALL be stated once.

---

### P1: Device validation checklist ⭐ MVP

**User Story**: As Julio, I want one checklist of everything the CI cannot prove so that I validate `0.1.0` on a device in one sitting.

**Acceptance Criteria**:

1. EXR-15: WHEN the checklist is read THEN `docs/DEVICE_CHECKLIST.md` SHALL list each unproven item with prerequisites, steps and the expected observable result and a pass/fail box. The items SHALL include at least: APNs registration and token delivery, permission prompt states, geocoder and location sharing, `UIDevice` profile fields, the NSE image/video/audio render, NSE expiry fallback, the SwiftUI delegate check with and without `@UIApplicationDelegateAdaptor`, the launch hook in a CocoaPods app (static and dynamic), cold-start click, silent push `received`, background `received`, and an App Store Connect validation upload (C617.1, privacy manifest, UserID/Device ID labels).
2. EXR-16: WHEN an item is carried from `STATE.md` THEN it SHALL cite the todo it closes, and closing it in `STATE.md` SHALL be a post-checklist step.

---

### P2: CocoaPods example and PKG-06

**User Story**: As an SDK maintainer, I want the example built through CocoaPods so that the two pods and their resource bundles have a real consumer.

**Acceptance Criteria**:

1. EXR-17: WHEN `pod install` runs in `Example/` with a local `:path` pod THEN the app and NSE SHALL build with static frameworks (`use_frameworks! :linkage => :static`) and with static libraries, the app on pod `NottiSDK` and the NSE on pod `NottiSDKExtension` only. Dynamic frameworks are included since AD-012 (design S6 fixed by `pod-split`).
2. EXR-18: WHEN the pod build runs THEN a test or runtime assertion SHALL load `NottiSDKResources.bundle` and `NottiSDKExtensionResources.bundle` through the CocoaPods branch and find the privacy manifest in each.
3. EXR-19: WHEN the pod build runs THEN `check-hook-linked.sh pod` semantics (launch hook present, `loadCount == installCount == 1`) SHALL be asserted in the example for each passing linkage.

---

### P2: Release preparation

**User Story**: As Julio, I want `0.1.0` staged so that tagging is a single, safe step.

**Acceptance Criteria**:

1. EXR-20: WHEN the release PR merges THEN `CHANGELOG.md` SHALL have a dated `0.1.0` section (Added, Known limitations, Migration notes from `react-native-notti` 0.6.0 for the storage keys and device id), and the README status banner SHALL change from pre-release.
2. EXR-21: WHEN `scripts/check-version.sh` runs THEN `NottiSDKVersion.current`, `s.version` and the top CHANGELOG section SHALL all equal `0.1.0`.
3. EXR-22: WHEN the release PR is opened THEN its description SHALL list the pre-tag gates for Julio: device checklist passed, Device ID manifest decision, legal confirmation of the UserID text, backend confirmation of the default host (already confirmed 2026-10-11), `pod lib lint` and `pod trunk push` steps.

---

### P2: CI builds the example

**Acceptance Criteria**:

1. EXR-23: WHEN CI runs on a PR THEN it SHALL install XcodeGen, generate the project and build the example (SPM) for the simulator and for a generic device without signing, and build the CocoaPods variant. Added steps SHALL not make `xcodebuild` run twice on one checkout at once.
2. EXR-24: WHEN the example changes THEN the public-member reference check (EXR-02) and the README snippet check (EXR-13) SHALL run in the `checks` job.

---

## Edge Cases

- A maintainer without Julio's xcconfig builds the example: it must compile and show "not configured" (EXR-05), never crash on a missing key.
- Xcode 27 gotchas apply to every build step: use the `scratchpad/run.sh` watchdog locally, no piping of `xcodebuild`.
- XcodeGen output must not be committed, and `project.yml` changes need a regenerated, building project in the same commit.
- The example must not enable swizzling-dependent code paths twice (manual forwarding plus swizzling), or it would hide the double-count limitation.
- A README snippet and the example source diverge: the check must fail, not warn.

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| EXR-01 | Example app | Design | Pending |
| EXR-02 | Example app | Design | Pending |
| EXR-03 | Example app | Design | Pending |
| EXR-04 | Example app | Design | Pending |
| EXR-05 | Example app | Design | Pending |
| EXR-06 | Example app | Design | Pending |
| EXR-07 | NSE target | Design | Pending |
| EXR-08 | NSE target | Design | Pending |
| EXR-09 | NSE target | Design | Pending |
| EXR-10 | README | Design | Pending |
| EXR-11 | README | Design | Pending |
| EXR-12 | README | Design | Pending |
| EXR-13 | README | Design | Pending |
| EXR-14 | README | Design | Pending |
| EXR-15 | Device checklist | Design | Pending |
| EXR-16 | Device checklist | Design | Pending |
| EXR-17 | CocoaPods example | Design | Pending |
| EXR-18 | CocoaPods example | Design | Pending |
| EXR-19 | CocoaPods example | Design | Pending |
| EXR-20 | Release preparation | Design | Pending |
| EXR-21 | Release preparation | Design | Pending |
| EXR-22 | Release preparation | Design | Pending |
| EXR-23 | CI | Design | Pending |
| EXR-24 | CI | Design | Pending |

## Success Criteria

- [ ] CI builds the example through SPM and CocoaPods with placeholder config, and the drift checks pass.
- [ ] Julio can run the checklist top to bottom on one device with only `Example.local.xcconfig` to fill in.
- [ ] The README plus CHANGELOG are enough for a new integrator; no spec is referenced for setup.
- [ ] Nothing tagged, released or pushed to the trunk by the agent.
