# macOS Support Validation (implementer notes, no Verifier verdict yet)

**Spec**: `.specs/features/macos-support/spec.md` (MAC-01..26)
**Branch**: `feat/macos-support` (from `docs/macos-support-spec`)
**Status**: Execute T1-T26 done; T27 and T28 blocked (see Task status). This file is written by the implementer. It is NOT the Verifier report: the Verifier (T27, a different agent or person, on a real Mac) has not run, so no verdict exists and the feature is not done.
**Result**: PENDING, no Verifier verdict yet.

Environment of every run below: Xcode 27.2 (27B52), macOS SDK 27.2, macOS 27.0 on Apple silicon, 2026-11-14. The iOS simulator `iPhone 17` of the spec is not installed here; the only installed simulator is `iPhone Duo` (iOS 27.1), used for every iOS run.

## Test counts

| Bundle | Baseline (main @ 9d82410, T1) | Final iOS (iPhone Duo) | Final macOS (`platform=macOS,arch=arm64`) |
| --- | --- | --- | --- |
| NottiSharedTests | 14 | 15 (+1, T3) | 15 |
| NottiSDKTests | 921 | 935 (+2 T5, +11 T6, +1 T18) | 775 (iOS-only UI and wiring tests are gated; +25 T20, +19 T21 lifecycle, +6 T21 In-App inert) |
| NottiSDKObjCTests | 8 | 8 | 8 |
| NottiSDKExtensionTests | 110 | 110 | 112 (+2 T22 link tests) |
| NottiSDKExtensionObjCTests | 3 | 3 | 3 |

The older note of 907 SDK tests (STATE, design) predates `wrapper-support`; the real baseline on `main` is 921.

## SPEC_DEVIATION

| # | Where | Spec or design said | What was done | Why |
| --- | --- | --- | --- | --- |
| 1 | T1 baseline | SDK 907 | SDK 921 | Measured on `main`; 907 predates `wrapper-support` |
| 2 | every iOS gate | simulator `iPhone 17` | `iPhone Duo` | Only simulator installed on this machine |
| 3 | T5 `NottiCore` | `#if canImport(UIKit) ... #elseif canImport(AppKit)` in the core | `NottiCore` has no platform `#if` at all; both observers read `NottiLifecycle`, and `NottiCore` no longer imports UIKit | The seam already hides the platform; a conditional in the core is what compiled to nothing on macOS (design C2). The "observers register nothing" failure can no longer happen by compilation; T21 still tests that they fire |
| 4 | T5 `NottiLifecycle` | `willEnterForeground` returns nil on macOS and `willTerminate` nil on iOS | The two members exist only on their platform (`#if canImport(UIKit)` / `#else`) | A non-optional `Notification.Name` per platform is simpler and a wrong use fails to compile |
| 5 | T7 `.ephemeral` | `#if os(iOS)` | `#if !os(macOS)` | Mac Catalyst has `.ephemeral` and takes the UIKit path; the iOS result is identical |
| 6 | T8 `NottiBackgroundTask` | iOS body inside `#if canImport(UIKit)` | iOS body unchanged inside the `#else` of `#if os(macOS)` | Same effect, one conditional; the iOS code is byte-identical apart from the wrapper |
| 7 | T8 `NottiCore` | New file holds the terminate hook | Also: `handleAppDidEnterBackground` and `nowMs` lose `private`, one stored property `terminateObserver` is added to `NottiCore`, `observeAppTerminate()` is an empty function on iOS | Swift extensions in another file cannot see `private` members or add stored properties. `NottiCore.swift` stays at 1492 lines (was 1499) |
| 8 | T12 | Not listed | `NottiInAppDisplayEvents` and `extension NottiInAppEngine: NottiInAppDisplayEvents {}` moved from `InApp/UI/NottiInAppPresenter.swift` to `InApp/Engine/NottiInAppHooks.swift`; `NottiInAppEventsReceiving` added | The shared engine implements that protocol and the UI file is compiled out on macOS |
| 9 | T11 `sharedApplication` | `perform(NSSelectorFromString("sharedApplication"))` | Same, and on macOS only when `Bundle.main` is an `.app` | `+[NSApplication sharedApplication]` creates an application when none exists; a library call in a non-app process must not (same guard as `NottiCurrentNotificationCenter`) |
| 10 | T7 commit body | n/a | Commit `d06ebaa` body says "NottiPushAdapter-side NottiPushPermissionAction.State.init"; the file changed is `NottiPushPermissionAction.swift` only | Typo in a published commit message, not amended |
| 11 | T9 commit body | n/a | Says "the four UIBackgroundFetchResult errors are gone"; two of them were in the swizzler and left in T10 | Counting slip in a published commit message, not amended |
| 12 | T19 platform literals | "make `ios` literals platform-aware" | The lifecycle tests keep their `UIApplication.*Notification` spellings on macOS through `Tests/NottiSDKTests/Support/MacLifecycleShim.swift` (a macOS-only enum), `NottiLifecycleTests` pins the seam to the real constants; the `"ios"` assertions are conditional | No iOS assertion edited, and the same tests run on both platforms |
| 13 | T19 gating | Gate UI view, layout, presenter, window, image loader tests | Also gated: `NottiInAppPrivacyTests` (whole file, it drives the UIKit presenter harness), `NottiInAppPublicApiTests` and `NottiInAppWiringTests` (they need a configured engine, which macOS never has), `NottiInAppOpenURLPublicApiTests`, `NottiPushPermissionPortWiringTests`, the objcTrackEvent test, `NottiAppDelegateSwizzlerTests` (iOS fetch variant) | They test iOS-only behavior; the macOS equivalents are the T20 and T21 tests. The macOS SDK count (775) is therefore lower than the iOS count (935) |
| 14 | T16 `check-launch-hook-purity.sh` | Ban "AppKit and NSApplication instances" | `NottiBootstrap.m` bans `AppKit`, `NSApplication`, `NSApp`; the installer bans `NSApplication.shared` and `NSApp`; `NSApplication.self` and the `NSApplication.perform(...)` lookup stay allowed | The installer imports AppKit itself and needs the class reference and the selector lookup |
| 15 | T16 `check-no-url-open.sh` | Ban `NSWorkspace.shared.open` style opens | Any `NSWorkspace` under `Sources/NottiSDK` and `Sources/NottiSDKBootstrap` fails | Simpler and stricter; no macOS allowlist entry |
| 16 | T17 | Podspecs add `osx` | The `NottiSDK` pod summary now says "iOS and macOS" | The old text would be wrong on trunk |
| 17 | T22 `nm` test | An AppKit-importing mutant fails it | A used AppKit reference fails it; an unused `import AppKit` does not (no symbol or load command), and the textual guard catches it | See the T22 mutant table |
| 18 | T24 | `hook-consumer` gets "a macOS target in its own generated project" | The same consumer package gets `.macOS(.v12)` in its `Package.swift` and `spm-macos` builds it with `xcodebuild` | The consumer is a SwiftPM executable, no generated project exists |
| 19 | T25 | Example reuses the iOS helpers | `ExampleConfig.swift` and `ExampleLog.swift` are compiled into the Mac target by path, so the redaction guarantee is shared | No copy of the log or the config reader |
| 20 | Whole run | Branch from `docs/macos-support-spec` | The worktree started on `main`; the branch was created from `docs/macos-support-spec` after that and the worktree branch was left untouched | The brief required the spec to travel with the code |

## Compile survey burndown (macOS located errors, `generic/platform=macOS`)

T2: 1 (the `UIKit` module). T4: 17. T5: 18 (two errors masked by the module error surfaced; none from the seam). T6: 15. T7: 14. T8: 12. T9: 7. T10: 5. T11: 5. T12: 3. T13: 0. The count is a compiler-batch artefact and not monotonic; the end state is what counts.

## Unconfirmed design decisions

Implemented as designed, each isolated so it is cheap to change. The owner approved D4, C1, D7, D8, D10, S3 and D12 as implemented on 2026-11-14 (before any real-Mac run). T27 can still reverse any of them if a real-device result contradicts the assumption; the "What changes it" column stays valid.

| Decision | Where it lives | What changes it |
| --- | --- | --- |
| D4: macOS `didReceiveRemoteNotification` returns `Void` (the only public-surface difference, spec MAC-22 needs amending) | `#if canImport(UIKit)` branches in `NottiPushAdapter.swift`, `NottiNotifications+Delegate.swift`, `ObjC/NottiObjC.swift`; two lines in `PUBLIC_SURFACE.txt` | Delete the `#else` branches and the two lines |
| C1: `didResignActive` ends the session on macOS | One line in `Platform/NottiLifecycle.swift` (`didEnterBackground`) | Point it at `didHide` or window occlusion |
| D7: 1.5 s bounded flush at terminate | `NottiCore.terminateFlushTimeout` in `Core/NottiCore+Terminate.swift` | One constant (or delete the file and `observeAppTerminate`) |
| D8: the In-App engine is never configured on macOS | `NottiPlatformInfo.supportsInApp` (used in `NottiRuntime.start`), the `#else` of `NottiRuntime.shared` | Make `supportsInApp` true and give macOS a real presenter (out of scope) |
| D10: `hw.model` as `device_model` | `NottiPlatformInfo.deviceModel()` macOS branch | One expression |
| S3: add `didReceiveRemoteNotification:` to a host `NSApplicationDelegate` that lacks it | `swizzleRemoteNotification` macOS branch in `NottiAppDelegateSwizzler.swift` | Skip the swizzle when `class_respondsToSelector` is false |
| D12: AD-002 marked expired, `AGENTS.md` reworded | `AGENTS.md`, `STATE.md` | Edit the wording |

## Task status

| Task | Status |
| --- | --- |
| T1-T26 | Done, one commit each, pushed to `origin/feat/macos-support`. Gate evidence is in each commit body |
| T27 | BLOCKED: needs a real Mac with a signed app and an Apple Developer team, the backend `macos-platform` deployed to a reachable environment, a real push, and an independent Verifier. Remaining: run D22 to D33 of `docs/DEVICE_CHECKLIST.md` and spikes S1 to S10, record pass or fail per item, write the Verifier verdict here, record the owner's decision on every unconfirmed decision above, and archive the macOS privacy report (T18 left that part open) |
| T28 | BLOCKED: the version bump to `0.3.0` (`NottiSDKVersion.current`, both podspecs), the CHANGELOG `[0.3.0]`, the README pin to the new minor, the tag, the GitHub Release and `pod trunk push` wait for T27 and the backend deploy, and are Julio's (after 2026-12-02 follow AD-022 plan B). Nothing was bumped: `scripts/check-version.sh` still reports 0.2.0 |

## Final state of the gate (local equivalent of `ci.yml`, 2026-11-14)

- iOS full run and macOS full run: counts above, all green.
- Seven guard scripts, `check-example-config.sh`, `check-example-coverage.sh`, `check-readme-snippets.sh`: ok. `check-public-surface.sh`: 89 declarations, the only diff against `main` is the two macOS `didReceiveRemoteNotification` lines (D4).
- SwiftLint strict (0.65.1 in docker): 0 violations.
- Strict builds (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `GCC_TREAT_WARNINGS_AS_ERRORS`) of `NottiSDK` and `NottiSDKExtension` (API-only) for `generic/platform=iOS` and `generic/platform=macOS`: exit 0 (last full run at T15; sources unchanged since except tests, docs, scripts and the example).
- `pod lib lint` for both podspecs with `--platforms=ios,osx`: default (dynamic frameworks), `--use-libraries` and `--use-static-frameworks` all passed (T17).
- `scripts/check-hook-linked.sh`: `spm` (iPhone Duo), `spm-macos`, `pod`, `pod osx`: ok.
- Mac example: `xcodegen generate --spec project-mac.yml` and a strict build of `NottiExampleMac`: ok.

## Not run

- The hosted GitHub Actions workflow (the local equivalent above is the evidence; billing may block it, design C10).
- Any signed app, real APNs delivery, Notification Center click, quit path, SwiftUI `@NSApplicationDelegateAdaptor`, NSE rendering on macOS, sandbox and hardened runtime, Xcode privacy report of a macOS archive (T27, spikes S1 to S10).
- The iOS Simulator `iPhone 17` of the spec (not installed; `iPhone Duo` was used).
- `validate_state.py` for this feature: it reports "no validation.md verdict" until the T27 Verifier writes one, as designed.
