# Example and Release Traceability

**Spec**: `.specs/features/example-and-release/spec.md` (EXR-01..EXR-24)
**Design**: `.specs/features/example-and-release/design.md`, tasks in `tasks.md`
**Status**: Written in T12 (2026-10-21). **Not verified**: no Verifier pass yet, and CI has not run for any of these changes (GitHub Actions billing, see `STATE.md` Active Blockers).

Test references use `Class.test_name`, all in `Example/Tests` (target `NottiExampleTests`, hosted in the example app) unless noted: `CF` = `ExampleConfigTests`, `LG` = `ExampleLogTests`, `MD` = `ExampleModelTests`, `MF` = `ManualForwardingTests`, `PI` = `ProductIntegrationTests`. Scripts are in `scripts/`.

**Status words.** *Local*: proved on the author's machine (Xcode 27.1, simulator iPhone 18 Pro), not yet in CI. *Device*: only a physical device or App Store Connect can prove it; it is a `docs/DEVICE_CHECKLIST.md` item and stays open until Julio runs it. *Pending*: not done yet.

Hosted tests count 34 per leg (SPM, pods static, libs, dynamic). Mutation evidence for the scripts is in the commit bodies of T5, T6, T8 and T11.

---

## 1. Spec requirement to proof

| ID | Behavior | Files / tests / proof | Status |
| --- | --- | --- | --- |
| EXR-01 | The example builds for the simulator and a generic device with `CODE_SIGNING_ALLOWED=NO`, no SDK warnings | `Example/project.yml`; hosted test run and strict device builds (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, `GCC_TREAT_WARNINGS_AS_ERRORS=YES`) on the four legs; CI job `example` | Local. CI job written, never run |
| EXR-02 | Every public member of `Notti`, `Notti.User`, `Notti.Notifications` and `NottiNotificationServiceExtension` is reachable from a screen | `scripts/check-example-coverage.sh` (32 members derived from `.specs/codebase/PUBLIC_SURFACE.txt`, qualified calls, empty allowlist); `MD.test_everyUserCallIsForwardedOnce`, `MD.test_initializePassesConfigAndReadsTheDeviceId`, `MD.test_permissionBothVariantsUpdateStateAndLog`, `MD.test_listenersLogKeysOnlyAndRemoveCleanly`, `MD.test_takeInitialClickLogsKeysWhenThereIsOne`, `MD.test_logLevelRoundTripsThroughTheSdk`; CI `checks` step "Example coverage (EXR-02)" | Local (script and tests). CI never run |
| EXR-03 | Shows device id, permission result, payload keys only and the log-level control; never displays or logs client key, token, email or phone | `LG.test_everyEventConstructorKeepsTheSentinelOutOfTheRows`, `LG.test_payloadShowsKnownKeysAndCountsTheOthers`, `LG.test_callRowNamesTheCallAndOutcomeOnly`, `MD.test_sentinelEmailPhoneAndKeyReachTheSdkButNeverTheLog`, `CF.test_descriptionNeverPrintsTheClientKeyOrAppId`. `ExampleLog` has no case that carries a free string (`Example/App/ExampleLog.swift`). The Device id row shows the id on screen by design | Local |
| EXR-04 | Swizzling default uses no manual forwarding; a second mode with `NottiDisableSwizzling` exercises the manual forwarding API | `Example/App/ManualForwarding.swift`, `ExampleAppDelegate.swift`; schemes `NottiExample-Manual` and `NottiExample-NoAdaptor`; `MF.test_enabledForwardsTheFiveCallsAndReturnsTheSdkResults`, `MF.test_disabledForwardsNothingAndReturnsNeutralResults`, `MF.test_bundleFlagMustBeABooleanTrue`; `scripts/check-example-config.sh` (plists differ only by the Boolean key) and `--built ... manual|default`; CI SPM leg builds `Debug-Manual` | Local. On-device behavior: Device (D08 to D10) |
| EXR-05 | Without `Example.local.xcconfig` the build uses the sample and shows "not configured" instead of calling the backend | `Example/Config/Example.xcconfig` (`#include?` of the local file); `CF.test_fixtureValuesAreNotConfigured`, `CF.test_emptyValuesAreNotConfigured`, `CF.test_unsubstitutedBuildSettingsAreNotConfigured`, `CF.test_missingInfoPlistKeysDoNotCrashAndAreNotConfigured`, `CF.test_emptyOrUnsubstitutedHostKeepsTheSdkDefault`, `CF.test_bareHostBecomesHttpsUrl`; `MD.test_unconfiguredNeverCallsTheSdkFromAnyAction` | Local |
| EXR-06 | No real app id or key in tracked files | `scripts/check-example-config.sh` (sample holds `fixture`; no `ck_`/`rk_` + 64 hex or UUID in `NOTTI_APP_ID` under `Example/`, `README.md`, `docs/`); `.gitignore` covers `Example.local.xcconfig`; CI `checks` step "Example config" | Local. CI never run |
| EXR-07 | The NSE target holds only the `@objc(NotificationService)` subclass and the two forwarding calls, and links `NottiSDKExtension`, never `NottiSDK` | `Example/NotificationService/NotificationService.swift` (region `nse`, equal to the README snippet by `scripts/check-readme-snippets.sh`); `PI.test_extensionBinariesDoNotLinkAppOnlyCode` (no `NottiBootstrap`, `NottiDelegateInstaller` or `NottiRuntime` in any extension Mach-O) | Local |
| EXR-08 | The NSE compiles with `APPLICATION_EXTENSION_API_ONLY=YES` | `APPLICATION_EXTENSION_API_ONLY: YES` on the `NotificationService` target in `project.yml` and `project-pods.yml`; the strict device build of the app scheme builds the embedded extension | Local. CI never run |
| EXR-09 | A real push with `notti_image_url` shows the image | Not CI-provable. `docs/DEVICE_CHECKLIST.md` D05 (image), D06 (video, audio), D07 (expiry) | Device |
| EXR-10 | README covers requirements, install, capabilities, initialize, permission, identity and tags, listeners, NSE wiring, swizzling opt-out with manual forwarding, Objective-C | `README.md` sections in that order. Reviewed against the spec, no script checks the order or the prose | Local (review only) |
| EXR-11 | Data section lists fields sent, UserDefaults suite and keys, manifest declarations and App Store label guidance, with an LGPD note that does not claim compliance | `README.md` "Data the SDK handles". The 30 `notti_*` keys equal the keys declared in `NottiDeviceStore.swift` and `NottiEventStore.swift` (diff of both lists empty, recorded in the T8 commit). Fields were read from `NottiCore.swift` and `NottiApiClient.swift`. The "Other" manifest categories need privacy or legal review (D18) | Local. Legal confirmation: Device (D18) |
| EXR-12 | Known limitations list the required items | `README.md` "Known limitations" and `CHANGELOG.md` 0.1.0 "Known limitations" | Local (review only) |
| EXR-13 | Every README snippet compiles and cannot drift | `Example/App/IntegrationSnippets.swift` (compiled into the app, never called), region `nse` in `NotificationService.swift`; `scripts/check-readme-snippets.sh` (7 mutations fail it, T8 commit); CI `checks` step "README snippets (EXR-13)". The Objective-C block is **not** compiled and says so | Local. CI never run. ObjC block unproven |
| EXR-14 | Placeholders only; the production default host is stated once | `README.md`; `scripts/check-example-config.sh` scans `README.md` and `docs/`. The host `https://app.zeepnotti.app` appears once in the README | Local |
| EXR-15 | The checklist lists each unproven item with prerequisites, steps, expected result and a pass/fail box | `docs/DEVICE_CHECKLIST.md` D01..D20 (the spec list plus D20, device id continuity from RN 0.6.0) | Written. Passing it: Device |
| EXR-16 | Items carried from `STATE.md` cite their todo; closing it is a post-checklist step | `docs/DEVICE_CHECKLIST.md` (each device todo cited once; list in the T9 commit body); "After the checklist" section | Written |
| EXR-17 | `pod install` with local `:path` pods builds the app and NSE under static frameworks and static libraries (and dynamic frameworks, AD-012) | `Example/Podfile`, `Example/project-pods.yml`; hosted tests and strict device builds passed on the three legs; CI matrix legs `pods-static`, `pods-libs`, `pods-dynamic` | Local. CI never run |
| EXR-18 | A test loads both resource bundles through the CocoaPods branch and finds the privacy manifest in each | `PI.test_appProductHoldsTheSdkPrivacyBundle`, `PI.test_extensionHoldsItsOwnPrivacyBundle`, `PI.test_theTwoProductsDoNotShareABundle` (bundle names chosen by `#if NOTTI_PODS`) | Local |
| EXR-19 | Launch hook present and `loadCount == installCount == 1` in the example, per linkage | `PI.test_launchHookRanOnceAndInstalledOnce` on every leg. Mutation: removing `NottiSDKBootstrap` from the `NottiSDK` target dependencies fails only this test (T6 commit) | Local. Behavior on a device: Device (D12, D13) |
| EXR-20 | `CHANGELOG.md` has a dated 0.1.0 section (Added, Known limitations, Migration notes) and the README banner leaves pre-release | `CHANGELOG.md` `[0.1.0] - TBD` (the date is set on release day); README banner now "release candidate" | Done except the date: set it at release |
| EXR-21 | `check-version.sh` requires `NottiSDKVersion.current`, both `s.version` and the top CHANGELOG section to equal `0.1.0` | `scripts/check-version.sh` (7 mutations fail it, T11 commit); CI `checks` step "Version drift" | Local. CI never run |
| EXR-22 | The release PR text lists the pre-tag gates for Julio | Not written: it is written when the release PR is opened | Pending |
| EXR-23 | CI installs XcodeGen, generates and builds the example for simulator and device, builds the CocoaPods variant, and never runs `xcodebuild` twice at once on a checkout | `.github/workflows/ci.yml` job `example` (matrix of four legs, steps in sequence; step "Nothing generated is tracked"). The SPM leg's shell logic was run locally; the workflow parses as YAML | Written. **Never run**: billing |
| EXR-24 | The public-member check (EXR-02) and the snippet check (EXR-13) run in the `checks` job | `.github/workflows/ci.yml` `checks` job steps "Example coverage (EXR-02)", "Example config (EXR-04, EXR-06)", "README snippets (EXR-13)" | Written. Never run |

---

## 2. Task to commit

| Task | Commit | Notes |
| --- | --- | --- |
| T1 | `847509e` | spike results and the CocoaPods dynamic framework finding; merged earlier |
| T2 | scaffold, PR #10 | merged 2026-10-19 |
| T3 | `66eda5b` | `ExampleConfig`, `ExampleLog` |
| T4 | `b250dea` | model, screens, manual forwarding |
| T5 | `7078243` | the two guards |
| T6 | `43c8ca4` | product integration tests |
| T7 | `1588fb5` | CocoaPods variant |
| T8 | `895c5f4` | README, snippet guard |
| T9 | `b5ae4d5` | device checklist |
| T10 | `e3e3d2d` | CI job `example` (never run) |
| T11 | `c2a8a79` | changelog, version guard |
| T12 | this commit | traceability, state, roadmap |

Branch `feat/example-tests` is PR #12 (T3 to T7). T8 to T12 are on branch `docs/readme-and-checklist`, stacked on it.

---

## 3. Device-only and unproven items

Closing the matching `STATE.md` todo is a post-checklist step (EXR-16). None is closed by this feature.

| Item | Checklist | STATE todo |
| --- | --- | --- |
| APNs registration, permission prompt, geocoder, `UIDevice` fields | D01 to D04 | core-port T8 |
| Rich media image, video, audio, expiry fallback | D05 to D07 | nse-rich-media, device |
| SwiftUI delegate check with and without the adaptor, manual forwarding, CocoaPods static and dynamic | D08 to D10, D12, D13 | delegate-integration, device |
| Late-install launch hook path | D11 | delegate-integration Verifier r1 N5/N7/N9 |
| Cold-start click, silent and background `received` | D14 to D16 | none (new) |
| App Store validation: manifests and C617.1 | D17 | nse-rich-media D9 |
| Privacy labels and legal wording | D18 | core-port Verifier r1 N7 |
| Dynamic-framework layout accepted by the App Store | D19 | example-and-release T1 spike S6 |
| Device id continuity from RN 0.6.0 | D20 | none (new) |

## 4. Known gaps found while writing the docs

- The example has no location usage description and never requests location permission, so checklist item D03 cannot run in it (recorded in `STATE.md`).
- Bundle ids and the team in `Example/project.yml` are placeholders (`invalid.example.notti.app`), so a device run needs a local edit in Xcode that regenerating resets (recorded in `STATE.md`).
