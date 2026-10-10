# Package Foundation Specification

## Problem Statement

The repo is empty. Before any Swift code can be ported (`core-port`), the SDK needs a package that native apps can consume through SPM and that `react-native-notti` can later consume through CocoaPods (M2). It also needs separate app and NSE products, a privacy manifest, and CI that builds and tests everything on an iOS simulator. If we get the package/module naming or the target split wrong now, every later feature and the M2 migration inherit the mistake.

## Goals

- [ ] `import NottiSDK` works in an app target via SPM and via CocoaPods, and `import NottiSDKExtension` works in a Notification Service Extension target, with the NSE product linking nothing from the app product.
- [ ] One CI workflow on every PR builds both products, runs the test targets on an iOS simulator, lints the podspec and runs SwiftLint. It is green on an empty-but-real skeleton.
- [ ] The SDK version has one source of truth that the code (`sdk_version` field), the podspec and git tags agree on.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Any SDK behavior (registration, API, delegates) | `core-port`, `public-api`, `delegate-integration` |
| Binary xcframework distribution | AD-003: source-only for v1 |
| Carthage | Not requested; SPM + CocoaPods covers native and RN consumers |
| Publishing to CocoaPods trunk / creating the GitHub remote | External/outward-facing action, done in `example-and-release` after explicit confirmation |
| Mac Catalyst / macOS / tvOS | iOS-only per PROJECT.md |
| Example app | `example-and-release` |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Pod / SPM package name | `NottiSDK` | Avoids collision with RN's existing `Notti` pod (would break M2) | y (Julio, 2026-10-09) |
| NSE product/module name | `NottiSDKExtension` | Same prefix as the app product; mirrors `OneSignalExtension` | y (Julio, 2026-10-09) |
| Public facade type name | `Notti` inside module `NottiSDK` (`import NottiSDK; Notti.initialize(...)`) | Keeps call sites identical to RN docs | n - settled in `public-api` |
| CocoaPods layout | One pod `NottiSDK` with subspecs `Core` (default) and `Extension` | Same shape as RN's `Notti.podspec` (Core + NotificationServiceExtension subspecs); an NSE target can depend on `NottiSDK/Extension` alone | n - confirm at Design |
| Min iOS | 15.0 | OneSignal v5 and the RN example app both target 15.x | y (PROJECT.md) |
| Swift tools / language mode | tools 5.9; Swift 5 language mode for M1 | Core uses a serial queue + semaphore; Swift 6 strict concurrency may force a rewrite beyond a port | y (Julio, 2026-10-09) |
| License | MIT | Same as `zeep-notti-react-native/LICENSE` | y (Julio, 2026-10-09) |
| Test runner | `xcodebuild test` against an iOS Simulator destination (not `swift test` on macOS) | The core imports UIKit/UserNotifications; macOS host tests won't compile | y (technical) |

---

## User Stories

### P1: Consume the SDK through SPM ⭐ MVP

**User Story**: As an iOS developer, I want to add the NottiSDK package by URL in Xcode and pick the app and extension products, so that I can integrate Notti without CocoaPods.

**Why P1**: SPM is the default dependency manager for native iOS. Every later feature ships through this package.

**Acceptance Criteria**:

1. WHEN a consumer resolves the package THEN `Package.swift` SHALL declare platform `.iOS(.v15)` and exactly two library products: `NottiSDK` and `NottiSDKExtension`.
2. WHEN an NSE target links `NottiSDKExtension` THEN the build graph SHALL NOT include the `NottiSDK` target (directly or transitively). Code needed by both products SHALL live in an internal target that is not a product.
3. WHEN `NottiSDKExtension` (and any internal shared target) is built THEN it SHALL compile with `APPLICATION_EXTENSION_API_ONLY` semantics (no `UIApplication.shared` or other extension-unavailable API).
4. WHEN either product is built for an iOS Simulator and an iOS device (arm64) THEN the build SHALL succeed with zero warnings treated as errors in CI.

**Independent Test**: `xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS'` and the same for `NottiSDKExtension` both succeed. Inspecting `swift package describe` / `show-dependencies` shows no edge from the extension target to `NottiSDK`.

---

### P1: Consume the SDK through CocoaPods ⭐ MVP

**User Story**: As a maintainer of `react-native-notti`, I want a `NottiSDK` podspec, so that the RN iOS module can depend on it in M2.

**Why P1**: AD-001/AD-003. Without the podspec, M2 is impossible.

**Acceptance Criteria**:

1. WHEN `pod lib lint NottiSDK.podspec` runs THEN it SHALL pass for both subspecs.
2. WHEN a Podfile depends on `NottiSDK` THEN it SHALL get the `Core` subspec by default. WHEN an NSE target depends on `NottiSDK/Extension` THEN it SHALL get only the extension sources (plus shared internal sources) and no Core sources.
3. WHEN the podspec's source globs are evaluated THEN test sources SHALL be excluded from every subspec (the lesson carried over from the RN podspec: `ios/**/*.swift` swept in XCTest files).

**Independent Test**: `pod lib lint` passes. A throwaway Podfile with an app target + NSE target installs and builds.

---

### P1: CI gate ⭐ MVP

**User Story**: As the maintainer, I want every PR to build and test both products, so that regressions from the port and later features are caught before merge.

**Why P1**: The port moves about 3.3k lines and about 210 tests. Without a gate, parity can't be proven.

**Acceptance Criteria**:

1. WHEN a PR is opened or updated against `main` THEN a GitHub Actions workflow on a macOS runner SHALL: build both products for the iOS Simulator, run all XCTest targets on an iOS Simulator destination, run `pod lib lint`, and run SwiftLint.
2. WHEN any of those steps fails THEN the workflow SHALL fail. Flaky-test retries, if enabled, SHALL be visible in the log (parity with the RN CI's `-retry-tests-on-failure` plus flaky warning).
3. WHEN the repo has only skeleton code THEN at least one smoke test per product SHALL run and pass, so the test pipeline is proven before `core-port` lands.

**Independent Test**: Push a branch with a deliberately failing test: CI is red. Revert it: CI is green.

---

### P1: Privacy manifests ⭐ MVP

**User Story**: As an integrator submitting to the App Store, I want each product to ship its own `PrivacyInfo.xcprivacy`, so that my app's privacy report is accurate without manual work.

**Why P1**: Apple requires privacy manifests for SDKs that use required-reason APIs (UserDefaults, file timestamps).

**Acceptance Criteria**:

1. WHEN `NottiSDK` is consumed via SPM or CocoaPods THEN its bundled privacy manifest SHALL declare at least what RN's Core manifest declares today: `NSPrivacyTracking = false`, UserDefaults accessed API (reason `CA92.1`), and collected data types Email and Phone (not linked to tracking), plus Coarse Location and Product Interaction (AD-005).
2. WHEN `NottiSDKExtension` is consumed THEN its privacy manifest SHALL declare at least what RN's NSE manifest declares today (FileTimestamp accessed API).
3. WHEN a later feature adds a required-reason API or a new collected data type THEN that feature's spec SHALL update the manifest. (This is a process rule; it is verified in each later feature's validation.)

**Independent Test**: Archive a sample app with both products. Xcode's generated privacy report lists NottiSDK's declarations.

---

### P2: Single source of truth for the SDK version

**User Story**: As the maintainer, I want the version string defined once, so that the `sdk_version` profile field (DPF-01..03), the podspec and the git tag never drift.

**Why P2**: In RN, `sdk_version` came from `package.json` through JS. Natively it must be a constant, and drift would corrupt backend analytics.

**Acceptance Criteria**:

1. WHEN the code needs the SDK version THEN it SHALL read a single constant (e.g. `NottiSDKVersion.current`) defined in one file.
2. WHEN CI runs THEN it SHALL fail if the podspec `version` differs from that constant.

**Independent Test**: Bump only the podspec version: CI is red.

---

### P2: Repo hygiene

**User Story**: As a contributor, I want standard repo scaffolding, so that the project is ready for atomic commits from task 1.

**Acceptance Criteria**:

1. WHEN the repo is cloned THEN it SHALL contain `.gitignore` (Xcode/SPM/CocoaPods artifacts, `.build/`, `DerivedData/`, `Pods/`), `LICENSE`, `README.md` (stub: what it is, status, install snippet), `CHANGELOG.md` (`[Unreleased]`) and `.swiftlint.yml`.
2. WHEN SwiftLint runs on the skeleton THEN it SHALL report zero violations.

---

## Edge Cases

- WHEN a consumer adds only `NottiSDKExtension` to an app target (misconfiguration) THEN the build SHALL still succeed; it just has no app API. Documented in the README, not enforced.
- WHEN both products are linked into the same app (app + embedded NSE) THEN there SHALL be no duplicate-symbol errors from the shared internal target (SPM static linking per target, CocoaPods subspec dedupe).
- WHEN the package is resolved by Xcode versions older than the CI version THEN `swift-tools-version` SHALL remain 5.9 so that Xcode 15+ can resolve it.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| PKG-01 | P1: SPM (products + platform) | Execute | Done |
| PKG-02 | P1: SPM (NSE has no edge to app target; shared internal target) | Execute | Done |
| PKG-03 | P1: SPM (extension-API-only) | Execute | Done |
| PKG-04 | P1: SPM (simulator + device builds) | Execute | Done |
| PKG-05 | P1: CocoaPods (`pod lib lint` both subspecs) | Execute | Done |
| PKG-06 | P1: CocoaPods (default Core; NSE-only Extension) | Execute | Done |
| PKG-07 | P1: CocoaPods (tests excluded from globs) | Execute | Done |
| PKG-08 | P1: CI (build + test + lint + SwiftLint) | Execute | Done |
| PKG-09 | P1: CI (fails on failure; flaky visible) | Execute | Done |
| PKG-10 | P1: CI (smoke test per product) | Execute | Done |
| PKG-11 | P1: Privacy manifest (app) | Execute | Done |
| PKG-12 | P1: Privacy manifest (NSE) | Execute | Done |
| PKG-13 | P1: Privacy manifest (update rule) | Execute | Done |
| PKG-14 | P2: Version constant | Execute | Done |
| PKG-15 | P2: Version drift check in CI | Execute | Done |
| PKG-16 | P2: Repo hygiene files | Execute | Done |
| PKG-17 | P2: SwiftLint clean | Execute | Done |

**Coverage:** 17 total, 17 mapped to tasks (see tasks.md), 17 done. PKG-03 also gets a real NSE build in `example-and-release`.

---

## Success Criteria

- [ ] A fresh Xcode project can add the package by local path, link `NottiSDK` to the app and `NottiSDKExtension` to an NSE, and build.
- [ ] CI is green on `main` with the skeleton, and red on a deliberately broken test.
- [ ] `pod lib lint` passes.
