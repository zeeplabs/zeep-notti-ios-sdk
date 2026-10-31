# Wrapper Support (0.2.0) Specification

## Problem Statement

M2 (`rn-consumes-native-sdk`) has started on the React Native side: `react-native-notti` will depend on
this pod and delete its own Swift core (RN repo, `.specs/features/ios-native-sdk/`, decisions G1-G4 by
Julio on 2026-10-31, RN AD-005). Its spike (2026-10-31, RN branch `spike/ios-native-sdk`) built the RN
example against `NottiSDK` 0.1.0 from the trunk in static libraries and both `use_frameworks!` linkages,
and found three gaps on this side:

1. **No way for a wrapper to report its own `sdk_version`.** `NottiCore.initialize` takes `sdkVersion`,
   and `NottiRuntime` passes `NottiSDKVersion.current`, but the public `Notti.initialize(appId:clientKey:options:)`
   has no parameter. An RN app on this SDK would report the native SDK version (`0.2.0`) instead of the RN
   package version (`0.9.0`), which breaks every backend rule keyed on the RN version.
2. **`NottiSDK.Notti` does not compile for a CocoaPods Swift consumer**: `error: type 'NottiSDK' has no
   member 'Notti'`. The facade's Obj-C class is registered as `NottiSDK` (AD-021), and the Clang importer
   exposes it as a type that shadows the module name. Unqualified `Notti` works.
3. **A recurring `NottiCore` test flake** in the RN repo, whose core and tests were ported here 1:1: a
   random `NottiCoreTests` case fails with `NottiCore work queue did not drain in 20.0s` / `25.0s`
   (RN CI runs 40038503525, 40041506391, 40213024920, 41216666378; one also logged
   `Task created in a session that has been invalidated (NSGenericException)`). The same test passes
   alone in under a second. This repo has the same `setUp`/`tearDown` and `StubURLProtocol` harness;
   whether it flakes here too is not known (CI here is blocked by billing).

Gap 1 blocks RN T3 (`sdk_version`). Gap 2 is worked around in RN (never qualify) but hits any native
CocoaPods consumer. Gap 3 makes CI unreliable in both repos.

Distribution: `NottiSDK` and `NottiSDKExtension` 0.2.0 must reach the CocoaPods trunk before it turns
read-only (about 2026-12-02, third-party sources; read-only test window 2026-11-01..07), per RN context
G3 and AD-022.

## Goals

- [ ] A wrapper SDK sets the `sdk_version` the backend receives, without a public API addition.
- [ ] `NottiSDK.Notti` either compiles for CocoaPods Swift consumers, or the limitation is documented and
      tested (decision G-A below).
- [ ] The `NottiCore` drain flake has a recorded root cause and a fix; the full suite passes repeatedly.
- [ ] 0.2.0 tagged and both pods pushed to the trunk before the cutoff.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Any RN-side change | Lives in `zeep-notti-react-native` (`ios-native-sdk`) |
| Confirming the swizzling opt-out key name (AD-014 D4) | RN chose swizzling (G1); not needed for M2 |
| Own spec repo `zeeplabs/specs` | Only needed for versions after the trunk cutoff (AD-022) |
| Backend change for per-SDK minimum versions | `zeep-notti` repo; recorded as a cross-repo risk below |
| `sdk_type` / wrapper name field | Backend has no such field today; would need a contract change first |

---

## User Stories

### P1: Wrapper reports its own `sdk_version` ⭐ MVP

**User Story**: As the `react-native-notti` maintainer, I want to pass the RN package version to the
native SDK, so that the backend sees the same `sdk_version` an RN 0.8.0 app sent.

**Why P1**: Blocks RN `ios-native-sdk` NSDK-03.

**Acceptance Criteria**:

1. WHEN a caller that imports the module with `@_spi(Wrapper) import NottiSDK` calls the wrapper
   initialize entry point with `sdkVersion: "0.9.0"` THEN the device profile SHALL send
   `sdk_version: "0.9.0"` (same field, same sync and ack rules as today).
2. WHEN the wrapper entry point receives an empty `sdkVersion` THEN the SDK SHALL omit `sdk_version`, as
   `NottiCore` does today for an empty value.
3. WHEN a host calls the public `Notti.initialize(appId:clientKey:options:)` THEN `sdk_version` SHALL stay
   `NottiSDKVersion.current` (no behavior change for native hosts).
4. WHEN a caller imports `NottiSDK` without `@_spi(Wrapper)` THEN the wrapper entry point SHALL NOT be
   visible.
5. WHEN `scripts/check-public-surface.sh` runs THEN SPI declarations SHALL NOT count as public surface, and
   the script SHALL still fail on any other added `public` symbol.
6. WHEN the wrapper entry point is called again with the same app id, client key and base URL but a
   different `sdkVersion` THEN the SDK SHALL behave as decided in Design (apply without restart, like
   `opensInAppURLs`, is the proposed default) and a test SHALL pin it.

**Independent Test**: unit test through an isolated facade/runtime with `StubURLProtocol`: the PATCH body
carries the wrapper's `sdk_version`; a second test with the public initialize carries
`NottiSDKVersion.current`.

---

### P1: Release 0.2.0 on SPM and the trunk ⭐ MVP

**User Story**: As the RN maintainer, I want `NottiSDK ~> 0.2.0` and `NottiSDKExtension ~> 0.2.0`
installable from the CocoaPods trunk, so that `react-native-notti` can declare them as podspec
dependencies.

**Acceptance Criteria**:

1. WHEN the release is cut THEN `NottiSDKVersion.current`, both podspecs and `CHANGELOG.md` SHALL say
   `0.2.0` (`scripts/check-version.sh` green).
2. WHEN `pod trunk push` runs for both pods THEN it SHALL happen before the trunk turns read-only; the push
   itself stays with Julio.
3. WHEN `pod lib lint` runs for both podspecs (frameworks and `--use-libraries`) THEN it SHALL pass.

---

### P2: `NottiCore` drain flake (narrowed by evidence, 2026-10-31)

**User Story**: As a maintainer, I want to know whether the RN core-test flake affects this SDK, so that a
red CI here means a real bug.

**Finding** (design section 3): six consecutive full runs here, 0 failures, slowest `NottiCoreTests` case
9.3 s; the RN suite on the same machine had cases at 19-24.5 s and a failure. The flake is RN-only
[Provável: RN's process-wide statics, which `core-port` replaced with an isolated `NottiRuntime`].

**Acceptance Criteria**:

1. WHEN the investigation ends THEN the evidence SHALL be recorded as a lesson in `STATE.md` (WRAP-10).
2. WHEN 0.2.0 is released THEN the full suite SHALL have passed 10 consecutive runs locally with zero drain
   timeouts (six done on `3d1cad6`; the remaining four on the release commit) (WRAP-11).
3. WRAP-12 (leak fails its own test): not applicable, no leak observed here. Reopen if one appears.
4. WHEN the finding is recorded THEN the RN repo SHALL note that its flake is RN-only and ends with its
   `ios-native-sdk` T6 (WRAP-13).

---

### P3: `NottiSDK.Notti` for CocoaPods Swift consumers

**User Story**: As a native integrator on CocoaPods, I want to qualify the facade with the module name,
so that it does not clash with my own `Notti` symbols.

**Acceptance Criteria** (depend on gray area G-A):

1. WHEN a Swift file in a CocoaPods consumer (static libraries and both frameworks linkages) writes
   `NottiSDK.Notti.initialize(...)` THEN it SHALL compile, OR, if G-A keeps the Obj-C name, the README
   SHALL state that CocoaPods consumers must not module-qualify, and a build check SHALL pin the
   unqualified form.
2. WHEN the Obj-C facade name changes THEN Objective-C hosts SHALL get an upgrade note, and
   `NottiSDKObjCTests` SHALL use the new name.

---

## Edge Cases

- WHEN the wrapper entry point is called before any public call THEN cold-start behavior (ensured core,
  queued identity calls) SHALL be the same as the public initialize.
- WHEN `sdkVersion` contains whitespace or is longer than the backend accepts THEN the SDK SHALL send it
  as given (no validation today); Design confirms the backend limit.
- WHEN the SPM product is used (not CocoaPods) THEN `@_spi(Wrapper)` SHALL work the same way.

---

## Cross-repo risk (not built here)

The backend gates the In-App `push_permission` button on one constant,
`MinSDKVersionPushPermission` (`zeep-notti/internal/inapp/sdkversion.go`, empty today, so no device gets
such a message), compared against `devices.sdk_version` with no SDK type. RN (`0.8.0`) and native iOS
(`0.1.0`) already send versions on different scales into the same field. One minimum cannot cover both.
Once P1 ships, RN apps keep sending RN versions, so the RN scale stays consistent, but native iOS (and
later native Android) devices still collide. Needs a backend decision (per-SDK minimum, or a `sdk_type`
field) before that constant is set. [Certo] on the code read; the fix belongs to `zeep-notti`.

---

## Assumptions & Open Questions

- Assumption: the backend accepts any `sdk_version` string the RN wrapper sends today (RN 0.8.0 already sends
  its own version through the same field). Not re-validated against `zeep-notti` limits.
- Open (cross-repo, not blocking 0.2.0): per-SDK minimum versions in the backend (see Cross-repo risk).
- Resolved: G-A below (rename), P2 scope (narrowed by evidence, design section 3).

## Gray areas (to decide)

**Decided (Julio, 2026-10-31): option (b), rename the Obj-C facade class to `NottiSDKFacade`.** No host
is known to use 0.1.0 yet; only Obj-C hosts break (Swift hosts use `Notti`, and the Swift name
`NottiObjC` stays). `NottiSDKFacade` does not clash with RN's classes (`Notti`, `NottiImpl`,
`NottiBridge`, `NottiPushDelegate`, the AD-021 reason). Amends AD-021 (new AD in Design). Design starts
with the repro to prove the rename makes `NottiSDK.Notti` compile; if it does not, come back before
renaming.

- **G-A, `NottiSDK.Notti` shadowing.** (a) Keep the Obj-C class name `NottiSDK` (AD-021, published in
  0.1.0) and document "do not qualify" for CocoaPods; (b) rename the Obj-C class (for example
  `NottiSDKFacade`), which breaks Obj-C hosts of 0.1.0 (a minor bump in 0.x, five days after release).
  Needs a repro in this repo's Example CocoaPods leg first to confirm which linkages are affected and
  whether SPM is.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| WRAP-01 | P1 wrapper: SPI entry point sends wrapper `sdk_version` | Specify | Pending |
| WRAP-02 | P1 wrapper: empty value omitted | Specify | Pending |
| WRAP-03 | P1 wrapper: public initialize unchanged | Specify | Pending |
| WRAP-04 | P1 wrapper: invisible without `@_spi(Wrapper)` | Specify | Pending |
| WRAP-05 | P1 wrapper: surface script ignores SPI, still guards public | Specify | Pending |
| WRAP-06 | P1 wrapper: re-initialize with a different `sdkVersion` | Specify | Pending |
| WRAP-07 | P1 release: version 0.2.0 everywhere | Specify | Pending |
| WRAP-08 | P1 release: trunk push before the cutoff | Specify | Pending |
| WRAP-09 | P1 release: `pod lib lint` both pods, both modes | Specify | Pending |
| WRAP-10 | P2 flake: root cause recorded | Specify | Pending |
| WRAP-11 | P2 flake: 10 consecutive green full runs (6 done) | Specify | Pending |
| WRAP-12 | P2 flake: leak fails its own test | - | Not applicable (no leak here) |
| WRAP-13 | P2 flake: RN repo notified | Specify | Pending |
| WRAP-14 | P3 qualification: `NottiSDK.Notti` compiles after renaming the Obj-C class to `NottiSDKFacade` (G-A) | Specify | Pending |
| WRAP-15 | P3 qualification: Obj-C upgrade note if renamed | Specify | Pending |

**Coverage:** 15 total, 0 mapped to tasks.

---

## Success Criteria

- [ ] RN `ios-native-sdk` T3 can pass `sdkVersion` through `@_spi(Wrapper) import NottiSDK`.
- [ ] `NottiSDK` and `NottiSDKExtension` 0.2.0 resolve from the trunk in a clean `pod install`.
- [ ] 10 consecutive green full-suite runs.
