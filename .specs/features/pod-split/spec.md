# Pod Split Specification

## Problem Statement

The CocoaPods layout is one pod `NottiSDK` with subspecs `Shared`, `Core` (default) and `Extension`, all compiled into the module `NottiSDK` (AD-006). With dynamic frameworks (`use_frameworks!`), an app on `pod 'NottiSDK'` and a Notification Service Extension on `pod 'NottiSDK/Extension'` makes CocoaPods build two pod targets, both producing `NottiSDK.framework` with module `NottiSDK`. The app's framework search paths list the extension one first, so `import NottiSDK` finds the wrong framework and the app fails to compile (`cannot find 'Notti' in scope`). Found by the example-and-release spike S6 (2026-10-12); `pod lib lint` does not catch it. Dynamic frameworks are common in React Native apps that also use Firebase, and M2 puts `react-native-notti` on this pod. Static frameworks and static libraries are not affected. A two-pod layout (`NottiSDK`, `NottiSDKExtension`) was prototyped in a scratch directory and passes under dynamic frameworks (design S6b).

## Goals

- [ ] An app plus NSE builds with CocoaPods under dynamic frameworks, static frameworks and static libraries, with the app on `NottiSDK` and the NSE on `NottiSDKExtension`.
- [ ] Two root pods with no subspecs: `NottiSDK` (app SDK, launch hook) and `NottiSDKExtension` (extension product). The extension pod never contains app code or the launch hook.
- [ ] SPM is untouched. Public API surface is untouched.
- [ ] The repo guards (`check-package-graph.sh`, `check-version.sh`, `check-hook-linked.sh pod`, CI `pod lib lint`) cover both pods.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Publishing either pod (`pod trunk push`) | Julio does it at release |
| The permanent app+NSE consumer test in CI | `example-and-release` T7 (hosted tests, three linkages). This feature proves it once with a scratch consumer |
| Renaming SPM products or modules | SPM already has `NottiSDK` and `NottiSDKExtension` as separate modules |
| Behavior changes in the SDK | Packaging only (AD-002) |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Layout | Two root podspecs, no subspecs. `NottiSDK.podspec`: `Sources/NottiShared`, `Sources/NottiSDK`, `Sources/NottiSDKBootstrap`. `NottiSDKExtension.podspec`: `Sources/NottiShared`, `Sources/NottiSDKExtension`. Same `-package-name NottiSDK` flag in both | Prototype passes under dynamic frameworks | y (Julio, 2026-10-12: "já vamos seguir assim") |
| `NottiShared` compiled into both pods | Accepted. No ObjC types in `NottiShared`, Swift symbols are module-qualified, and an app links only `NottiSDK` (the appex links only `NottiSDKExtension`) | Avoids a third pod and a version-matching problem | y (same decision) [Certo: `grep @objc\|NSObject` is empty in `Sources/NottiShared`] |
| Old names | `NottiSDK/Core`, `NottiSDK/Extension`, `NottiSDK/Shared` disappear. Nothing is published yet, so no migration | Pre-release | y |
| NSE import under CocoaPods | `import NottiSDKExtension`, same line as SPM | Module is now distinct | y |
| Version | Both podspecs carry the same version as `NottiSDKVersion.current` | One release, two pods | y |
| Linking the extension pod into an app | Still builds and exposes no app API, as in SPM | Same rule as before | y |

Open questions: none.

---

## User Stories

### P1: App plus NSE builds under every CocoaPods linkage ⭐ MVP

**Acceptance Criteria**:

1. PODS-01: WHEN an app target uses `pod 'NottiSDK'` and an NSE target uses `pod 'NottiSDKExtension'` THEN `pod install` and a simulator build SHALL succeed with `use_frameworks!` dynamic, `use_frameworks! :linkage => :static` and static libraries (`use_modular_headers!`).
2. PODS-02: WHEN the app builds THEN `import NottiSDK` SHALL resolve `Notti` and the NSE SHALL resolve `NottiNotificationServiceExtension` through `import NottiSDKExtension`.
3. PODS-03: WHEN the built products are inspected THEN the app SHALL contain `NottiSDK_Privacy.bundle` and the appex `NottiSDKExtension_Privacy.bundle`, and `NottiBootstrap` SHALL be loaded once (`loadCount == installCount == 1`) in each linkage.

### P1: Pod shapes are guarded

1. PODS-04: WHEN `scripts/check-package-graph.sh` runs THEN it SHALL require both podspecs to equal their expected shape (no subspecs, no test or app specs, own source globs, own resource bundle, bootstrap glob only in `NottiSDK`, no `NottiSDK` dependency in `NottiSDKExtension`) and fail on any other key.
2. PODS-05: WHEN `scripts/check-version.sh` runs THEN it SHALL fail if either podspec version differs from `NottiSDKVersion.current` (and from the tag on tag builds).
3. PODS-06: WHEN `scripts/check-hook-linked.sh pod` runs THEN it SHALL lint `NottiSDK.podspec` and require `NottiBootstrap` in the product.
4. PODS-07: WHEN CI runs THEN `pod lib lint` SHALL run for `NottiSDK.podspec` and for `NottiSDKExtension.podspec`, each also with `--use-libraries`.

### P2: Docs follow the layout

1. PODS-08: WHEN a developer reads `README.md` and `AGENTS.md` THEN installation SHALL show `pod 'NottiSDK'` and `pod 'NottiSDKExtension'`, and `AGENTS.md`, `TESTING.md` and `STATE.md` SHALL describe two pods (new AD-012, AD-006 amended).

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| PODS-01 | App plus NSE builds | Verify | Done |
| PODS-02 | App plus NSE builds | Verify | Done |
| PODS-03 | App plus NSE builds | Verify | Done |
| PODS-04 | Guards | Verify | Done |
| PODS-05 | Guards | Verify | Done |
| PODS-06 | Guards | Verify | Done |
| PODS-07 | Guards | Verify | Done |
| PODS-08 | Docs | Verify | Done |

## Success Criteria

- [ ] The scratch consumer (app plus NSE) passes hosted tests under the three linkages with the real podspecs.
- [ ] CI is green with both pods linted.
