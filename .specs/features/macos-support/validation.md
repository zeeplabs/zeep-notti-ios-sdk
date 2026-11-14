# macOS Support Validation (implementer notes, no Verifier verdict yet)

**Spec**: `.specs/features/macos-support/spec.md` (MAC-01..26)
**Branch**: `feat/macos-support` (from `docs/macos-support-spec`)
**Status**: Execute in progress. This file is written by the implementer. It is NOT the Verifier report: the Verifier (T27, a different agent or person, on a real Mac) has not run, so there is no PASS or FAIL verdict here and the feature is not done.

Environment of every run below: Xcode 27.2 (27B52), macOS SDK 27.2, macOS 27.0 on Apple silicon, 2026-11-14. The iOS simulator `iPhone 17` of the spec is not installed here; the only installed simulator is `iPhone Duo` (iOS 27.1), used for every iOS run.

## Test counts

| Bundle | Baseline (main @ 9d82410, T1) | After T14 (iOS) | After T14 (macOS) |
| --- | --- | --- | --- |
| NottiSharedTests | 14 | 15 (+1, T3) | not run yet (T19) |
| NottiSDKTests | 921 | 934 (+2 T5, +11 T6) | not run yet (T19) |
| NottiSDKObjCTests | 8 | 8 | not run yet (T19) |
| NottiSDKExtensionTests | 110 | 110 | not run yet (T19) |
| NottiSDKExtensionObjCTests | 3 | 3 | not run yet (T19) |

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

## Compile survey burndown (macOS located errors, `generic/platform=macOS`)

T2: 1 (the `UIKit` module). T4: 17. T5: 18 (two errors masked by the module error surfaced; none from the seam). T6: 15. T7: 14. T8: 12. T9: 7. T10: 5. T11: 5. T12: 3. T13: 0. The count is a compiler-batch artefact and not monotonic; the end state is what counts.

## Unconfirmed design decisions

Implemented as designed, each isolated so it is cheap to change. The owner has not confirmed any of them.

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
| T1-T14 | Done, committed and pushed. See the commit bodies for gate evidence |
| T15-T26 | Pending in this run, see the tail of this file as they complete |
| T27 | BLOCKED: needs a real Mac with a signed app, an Apple Developer team, the backend `macos-platform` deployed and an independent Verifier |
| T28 | BLOCKED: release, tag, GitHub Release and `pod trunk push` wait for T27 and the backend deploy, and are Julio's |

## Mutants (T20, macOS, `NottiAppDelegateSwizzlerMacTests` and `NottiSDKVersionTests`)

Each mutant was applied to the source, the macOS tests were run, and the source was restored with a checkout.

| Mutant | Edit | Result |
| --- | --- | --- |
| M1 swizzler forwards zero times | The macOS block no longer calls the host original | Killed: 7 failures (order, all-three, same-arguments, subclass, double swizzle) |
| M2 swizzler forwards twice | The original is called twice | Killed: 4 failures |
| M3 adapter skipped | The macOS block no longer calls `adapter.didReceiveRemoteNotification` | Killed: 6 failures |
| M4 wrong platform constant | `NottiSDKVersion.platform` is `"ios"` under `os(macOS)` | Killed: the registration body test, the `sdk_name` PATCH test and the `NottiSharedTests` literal test |

Mutants of T21 (applied to the source, macOS tests run, source restored by checkout):

| Mutant | Edit | Result |
| --- | --- | --- |
| M5 foreground observer registers nothing | `NottiCore.observeAppForeground` listens to a name nobody posts | Killed (`NottiCoreTerminateTests`) |
| M6 background observer registers nothing | `observeAppBackground` listens to a name nobody posts | Killed |
| M7 terminate observer registers nothing | `observeAppTerminate` listens to a name nobody posts | Killed (4 failures) |
| M8 the flush does not wait | `handleAppWillTerminate` drops `waitForPendingWork` | Killed (the bounded-wait test) |
| M9 In-App enabled on macOS | `NottiPlatformInfo.supportsInApp` is true on macOS | Killed (the inert tests) |

Mutants of T22 (macOS):

| Mutant | Edit | Result |
| --- | --- | --- |
| M10 the extension imports AppKit and references `NSApplication` | A function in `NottiRichMediaLimits.swift` | Killed: the `otool -L` and the `nm -u` tests |
| M11 the extension has an unused `import AppKit` | One line | NOT killed by the link tests (an unused import adds no load command or symbol); the textual guard `check-extension-safety.sh` bans the line (proved in T16) |
| M12 the extension SPM target depends on `NottiSDK`; each podspec without `osx`; the extension pod gaining `Sources/NottiSDK` | Fixtures on a temp copy | Killed by `check-package-graph.sh` (T17) |
