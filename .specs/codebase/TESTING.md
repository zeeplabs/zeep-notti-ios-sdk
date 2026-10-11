# Testing

**Status**: Derived from the approved designs of `package-foundation` and `core-port` (2026-10-09), extended by `public-api` (2026-10-11: facade layer, ObjC test target, surface guard) and `delegate-integration` (2026-10-11: swizzling fakes, installer, launch hook proofs, URL-open ban). Update it when a later feature adds a test layer (e.g. the NSE build in `example-and-release`).

---

## Frameworks

| Kind | Tool | Notes |
| --- | --- | --- |
| Unit | XCTest | Run through the SPM scheme `NottiSDK-Package` on an iOS Simulator. `swift test` on macOS is not supported (UIKit / UserNotifications) |
| HTTP stubbing | `StubURLProtocol` (ported from RN) | No network in tests |
| Lint | SwiftLint 0.65.1 (pinned Docker image `ghcr.io/realm/swiftlint:0.65.1`, entrypoint is `swiftlint`) | Not installed locally. Run through Docker. Exits 1 on a tree with no Swift files |
| Packaging | `pod lib lint` (CocoaPods 1.17.0 locally) | Available from package-foundation T8 onward |
| Scripts | `scripts/check-version.sh`, `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh` (needs `swift` + `pod`, macOS), `scripts/check-public-surface.sh` and `scripts/check-no-url-open.sh` and `scripts/check-launch-hook-purity.sh` and `scripts/check-nse-logging.sh` (grep/sed/sort/diff/awk/perl, run on the Linux `checks` job), `scripts/check-hook-linked.sh spm\|pod` (needs Xcode and a simulator / `pod`; runs in the `test` and `pod-lint` jobs) | The graph check was added after the package-foundation Verifier round 2. The surface script compares with `.specs/codebase/PUBLIC_SURFACE.txt`; `--update` rewrites it |
| Objective-C | XCTest in Objective-C (`Tests/NottiSDKObjCTests/*.m`, `@import NottiSDK;`) | SPM test target `NottiSDKObjCTests`, SPM only (not in the podspec). Fails to compile when an `@objc` entry point disappears. Runs in the same `xcodebuild test` as the others (4 bundles) |
| Swizzling fakes | `objc_allocateClassPair` fixture classes with unique names, a private `NottiMethodSwizzler` per test, `DelegateFixtures` (`Tests/NottiSDKTests/Support`: `UNNotification` / `UNNotificationResponse` by KVC, callback senders, `OpenSpy`) | No unit test swizzles `UIApplication` or `UNUserNotificationCenter`. `UNUserNotificationCenter` instances come from `class_createInstance` (`current()` raises without an app bundle). `+load` itself swizzles the real classes in the test process (see `IN.test_theLaunchHookInstalledTheRealSwizzlesInThisProcess`) |

## Test Targets

| Target | Covers |
| --- | --- |
| `NottiSharedTests` | `NottiShared`: version, logger, payload keys, notification parsing |
| `NottiSDKTests` | `NottiSDK`: core, storage, network, events, runtime, providers, privacy manifest, continuity fixture, PII-in-logs, and the public-api layers: `NottiListenerHubTests`, `NottiNotificationPayloadTests`, `NottiFacade{Initialize,Profile,Permission,Listener,LogLevel}Tests`, `NottiPublicApiTests` (public `Notti` shell + the F1 test on the real `notti_prefs` suite + the manual forwarding API), `NottiObjCBridgeTests` (ObjC-facing classes called from Swift), and the delegate-integration layers: `NottiSwizzlingConfigurationTests`, `NottiMethodSwizzlerTests`, `NottiPushAdapterTests`, `NottiAppDelegateSwizzlerTests`, `NottiNotificationCenterSwizzlerTests`, `NottiDelegateInstallerTests`, `NottiDeepLinkTests` |
| `NottiSDKObjCTests` | Objective-C compile check and smoke calls of every `@objc` entry point, including the manual forwarding API (`NottiObjCTests.m`) |
| `NottiSDKExtensionTests` | `NottiSDKExtension`: privacy manifest (NSE behavior in `nse-rich-media`) |

---

## Test Coverage Matrix

| Code layer | Required test type | Notes |
| --- | --- | --- |
| `NottiShared` (version, logger, keys, parsing) | unit | |
| Storage (`NottiDeviceStore`, `NottiEventStore`) | unit | Isolated UserDefaults suite per test, removed in `tearDown` |
| Network (`NottiApiClient`, `NottiNetworkObserver`) | unit | `StubURLProtocol`, `FakePathMonitor` |
| Events (`NottiEventBuffer`, `NottiNotificationHandler`) | unit | Isolated `NottiRuntime` per test, never `.shared` |
| Core (`NottiCore`) | unit | Injected sleeper, HTTP and providers |
| Runtime (`NottiRuntime`) | unit | Isolated instance, `startObservers: false` where observers would leak |
| Platform providers (`live()` OS closures) | build | OS-backed (`UIApplication`, `CLLocationManager`, `UNUserNotificationCenter`). Pure helpers inside them get unit tests |
| Facade (`NottiFacade`, `NottiListenerHub`, `NottiNotificationPayload`) | unit | `NottiFacade(runtime:dispatcher:)` over an isolated runtime and a recording dispatcher, never `.shared` |
| Public Swift shell (`Notti`) | unit | Routed to an isolated facade through the internal `NottiFacade.setSharedForTesting(_:)` seam; the one test on the real shared facade is F1 in `NottiPublicApiTests` (literal `notti_prefs`, restores the previous value) |
| Objective-C layer | unit (Swift bridge tests) + ObjC compile check | `NottiObjCBridgeTests`, `NottiSDKObjCTests`. The ObjC tests use only the public surface (invalid `initialize` values, no network) |
| Delegate integration (adapter, swizzlers, installer, fallback delegate) | unit | Fake classes per test; the installer takes its classes, center, configuration and `NotificationCenter` through `Environment` |
| Launch hook (`NottiSDKBootstrap`) | unit + CI build | `loadCount`/`installCount` asserted in a package test; `check-hook-linked.sh spm` (Release consumer) and `pod` (`nm`) in CI |
| Deep link and PII over the delegate paths | unit | `NottiDeepLinkTests`, the delegate sentinel sweep in `NottiLoggingPrivacyTests` |
| URL-open ban | script | `scripts/check-no-url-open.sh`, proved on a passing and a failing tree |
| Launch hook purity (DEL-14) | script + unit test | `scripts/check-launch-hook-purity.sh` (mutants: `NSLog`, `NSUserDefaults`, `NSFileManager`, `NottiRuntime` in the `.m`; `UserDefaults`, `NottiRuntime`, `FileManager` in the installer); `NottiDelegateInstallerTests.test_theEnabledValidLaunchHookPathLogsNothingAboveDebug` |
| NSE logging (NSE-13) | script | `scripts/check-nse-logging.sh`, proved on a fixture tree per banned token (`NSLog`, `print(`, `debugPrint`, `dump(`, `os_log`, `localizedDescription`) and on a comment-only fixture |
| Public surface | script | `scripts/check-public-surface.sh`, verified by mutation (added, removed, moved symbol; `public` in `NottiShared`) |
| Resources (privacy manifests) | unit | Parse the bundled plist |
| Packaging (`Package.swift`, podspec) | build | `xcodebuild build` + `pod lib lint` |
| Scripts / CI workflow | none | Verified by running the script against a passing and a failing input |
| Repo hygiene files | none | |

## Parallelism Assessment

| Test type | Parallel-Safe | Reason |
| --- | --- | --- |
| unit | No | All tasks build one SPM checkout. Concurrent `xcodebuild` runs contend on the same `.build`/DerivedData and simulator. Tasks run sequentially |
| build | No | Same reason |

Future option: one git worktree plus `-derivedDataPath` per sub-agent would make units parallel-safe. Not used in M1.

---

## Gate Check Commands

`NOTTI_SIM` is the simulator name. Locally it is `iPhone 17 Pro` (Xcode 27.0, verified 2026-10-09). CI pins it in `env:` (package-foundation T12).

| Gate | Command |
| --- | --- |
| build | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` |
| quick | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:<TestTarget>/<TestClass>` |
| full | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` and `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` and, once they exist, `scripts/check-version.sh`, `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh`, `scripts/check-public-surface.sh`, `pod lib lint NottiSDK.podspec --platforms=ios` (and `--subspec=Extension`), plus the strict device builds of `ci.yml` (`xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -quiet`, and `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES`; they catch warnings the test build does not), `scripts/check-no-url-open.sh`, `scripts/check-launch-hook-purity.sh`, `scripts/check-nse-logging.sh`, `scripts/check-hook-linked.sh spm` and `pod` |

Test counts are read from the `Executed N tests` line of each bundle of `xcodebuild test` (four bundles: Shared 14, SDK 444, ObjC 6, Extension 1 = 465 at the end of delegate-integration Execute; 351 at the end of public-api Execute, 356 after its Verifier fixes). A task's expected count is cumulative per target; a lower number means a silently dropped test and fails the task.
