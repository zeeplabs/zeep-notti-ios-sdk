# Testing

**Status**: Greenfield. Derived from the approved designs of `package-foundation` and `core-port` (2026-10-09). Update it when a later feature adds a test layer (e.g. swizzling in `delegate-integration`, the NSE build in `example-and-release`).

---

## Frameworks

| Kind | Tool | Notes |
| --- | --- | --- |
| Unit | XCTest | Run through the SPM scheme `NottiSDK-Package` on an iOS Simulator. `swift test` on macOS is not supported (UIKit / UserNotifications) |
| HTTP stubbing | `StubURLProtocol` (ported from RN) | No network in tests |
| Lint | SwiftLint 0.65.1 (pinned Docker image `ghcr.io/realm/swiftlint:0.65.1`, entrypoint is `swiftlint`) | Not installed locally. Run through Docker. Exits 1 on a tree with no Swift files |
| Packaging | `pod lib lint` (CocoaPods 1.17.0 locally) | Available from package-foundation T8 onward |
| Scripts | `scripts/check-version.sh`, `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh` (needs `swift` + `pod`, macOS) | The graph check was added after the package-foundation Verifier round 2 |

## Test Targets

| Target | Covers |
| --- | --- |
| `NottiSharedTests` | `NottiShared`: version, logger, payload keys, notification parsing |
| `NottiSDKTests` | `NottiSDK`: core, storage, network, events, runtime, providers, privacy manifest, continuity fixture, PII-in-logs |
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
| full | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` and `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` and, once they exist, `scripts/check-version.sh`, `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh`, `pod lib lint NottiSDK.podspec --platforms=ios` |

Test counts are read from the `Executed N tests` line of `xcodebuild test`. A task's expected count is cumulative per target; a lower number means a silently dropped test and fails the task.
