# Wrapper Support (0.2.0) Design

**Spec**: `.specs/features/wrapper-support/spec.md`
**Status**: Approved (Julio, 2026-10-31)

---

## 1. Wrapper `sdk_version` through `@_spi(Wrapper)` (WRAP-01..06)

### Today (read from the code)

- `NottiCore.initialize(appId:clientKey:baseUrl:sdkVersion:)` already stores `sdkVersion` (empty becomes
  nil, so `sdk_version` is omitted) and syncs it as a profile field with its own ack key
  (`notti_last_synced_sdk_version`).
- `NottiRuntime` holds `sdkVersion` as a constructor `let` (default `NottiSDKVersion.current`) and passes it
  in `start(appId:clientKey:baseUrl:)`.
- `NottiFacade.initialize(appId:clientKey:baseUrl:opensInAppURLs:)` builds a `Config(appId, clientKey,
  baseUrl)`; an equal config is a no-op, a different one calls `runtime.start` (new core).

### Change

```swift
// Sources/NottiSDK/Public/Notti+Wrapper.swift
extension Notti {
    /// For wrapper SDKs (react-native-notti, Flutter). Same as `initialize(appId:clientKey:options:)`,
    /// but `sdk_version` reports the wrapper's version instead of the native one. Not public API:
    /// visible only with `@_spi(Wrapper) import NottiSDK`, outside the semver promise.
    @_spi(Wrapper) public static func initialize(appId: String, clientKey: String, options: Options = Options(), sdkVersion: String)
}
```

- `NottiFacade.initialize` gains `sdkVersion: String? = nil`. `Config` gains `sdkVersion: String?`
  (nil = native default). The public entry point passes nil.
- `NottiRuntime.start` gains `sdkVersion: String? = nil` and uses `sdkVersion ?? self.sdkVersion`.
- **WRAP-06 decision**: `sdkVersion` is part of `Config`, so a different value restarts the core, like a
  different app id. Not applied in place like `opensInAppURLs`: a wrapper passes one constant per process,
  so a change only happens in tests or a misconfigured host, and the restart path is the one already
  tested. A restart re-syncs `sdk_version` through the existing ack key.
- Empty `sdkVersion` from a wrapper: passed through, `NottiCore` omits the field (WRAP-02), same as RN 0.8.0
  when JS fails to resolve its version.
- No Obj-C variant: the only wrapper today (RN adapter) is Swift. Add one only if a wrapper needs it.

### Public-surface guard (WRAP-05)

`scripts/check-public-surface.sh` scans declaration lines that start with optional attributes and then
`public`/`open`. Change:

- A declaration whose same-line attributes include `@_spi(` is excluded from `PUBLIC_SURFACE.txt` and
  written to a second committed file, `.specs/codebase/SPI_SURFACE.txt`, checked for drift the same way
  (`--update` rewrites both). SPI changes stay reviewed even though they are outside semver.
- Rule (AGENTS.md): keep `@_spi(...)` on the same line as `public`, like `public` itself.
- Mutation proofs, as for the existing script: an added plain `public` still fails; an added
  `@_spi(Wrapper) public` updates only the SPI file; `@_spi` on a line above `public` fails (the line would
  be read as plain public).

### Tests

| Test | Layer | Proves |
| --- | --- | --- |
| `NottiFacadeInitializeTests.test_wrapperSdkVersionIsSentAsSdkVersion` | facade over isolated runtime, `StubURLProtocol` | WRAP-01 |
| `..._emptyWrapperSdkVersionOmitsTheField` | same | WRAP-02 |
| `..._publicInitializeSendsTheNativeVersion` | same | WRAP-03 |
| `..._aDifferentWrapperSdkVersionRestartsTheCore` | same | WRAP-06 |
| Script mutation runs, recorded in `validation.md` | script | WRAP-05 |
| `NottiSDKTests` uses `@_spi(Wrapper) @testable import`; WRAP-04 relies on the compiler (SPI is invisible without the attribute), proved once by a scratch consumer in `validation.md` | compiler | WRAP-04 |

---

## 2. Obj-C facade renamed to `NottiSDKFacade` (WRAP-14, WRAP-15; G-A decided)

- `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`: `@objc(NottiSDK)` becomes `@objc(NottiSDKFacade)`. Swift
  name `NottiObjC` unchanged. Other Obj-C names (`NottiUser`, `NottiNotifications`, `NottiInAppMessages`,
  `NottiSubscription`, `NottiLogLevel`) unchanged; none clashes with RN (`Notti`, `NottiImpl`,
  `NottiBridge`, `NottiPushDelegate`).
- Update `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `README.md` Obj-C snippets, `PUBLIC_SURFACE.txt` if it
  lists the attribute line, CHANGELOG upgrade note for Obj-C hosts.
- Outside this repo: the `zeep-notti` docs page `sdks/ios` (en + pt-BR) if it shows the Obj-C snippet.
- New decision **AD-023** amends AD-021 (name only; the reason, no clash with RN's `Notti`, still holds).
- **Gate before renaming (repro)**: see section 4.

---

## 3. `NottiCore` drain flake (WRAP-10..13)

_Investigation in progress; filled with evidence before any fix._

Facts so far (code and logs, 2026-10-31):

- Every RN CI failure is a `NottiCoreTests` case failing `drain` (20 s or 25 s), each time a different test.
  One run on CI failed `test_onTokenRefreshedDoesNotBlockTheCallingThread`, which uses
  `ThreadProbeApiClient` and never touches `URLSession`: its own work is two calls of 1 s. So the core's
  serial queue was not starved by its own HTTP; something else delayed it.
- `NottiApiClient` waits for each `URLSession` task on a semaphore with a 20 s backstop
  (`semaphoreTimeoutSeconds`), above the 15 s request timeout. A task that never completes costs 15-20 s
  per attempt, up to 5 attempts.
- In a local RN full-suite run, passing tests took 19.0, 22.7 and 24.5 s
  (`test_aBumpedVersionBetweenTwoRegistrationsResyncsWithTheNewValue`,
  `test_aCoreRecreatedByAJsReloadWhileForegroundAdoptsTheOpenSessionInsteadOfClosingIt`,
  `test_aPermissionFlipQueuedBeforeRegistrationSendsOnlyTheFinalState`), and the failing one 32.4 s with
  `7` recorded requests where `2` were expected. The same failing test alone: 3/3 passes, ~0.85 s each.
  Durations near the 15/20 s timeouts and extra requests in a shared static `StubURLProtocol` point to
  tasks that never complete and to cores outliving their test (tearDown waits at most 20 s, then
  invalidates the sessions under any still-running core; one CI log has
  `Task created in a session that has been invalidated`).
- Hypotheses to test, not conclusions: (H1) one slow test leaks a running core, whose later requests
  consume or record into the next test's stub queue; (H2) blocked GCD threads (cores sleeping on
  semaphores) starve the next test's work queue; (H3) `StubURLProtocol`'s `Thread.sleep` for `delayMs`
  runs on a loader thread shared by all sessions and delays other tasks.

### Result: the flake does not reproduce in this SDK (2026-10-31)

Six consecutive full runs of `NottiSDK-Package` on `main` (`3d1cad6`), detached worktree, iPhone 17
simulator (iOS 27.0), same machine as the RN runs: **907 + 110 + 14 + 8 + 3 tests per run, 0 failures in
all six**, `NottiSDKTests` in 27-68 s. The slowest `NottiCoreTests` case across the six runs took 9.3 s
(`test_aGrantedPermissionResultClearsAStaleUnackedUnsubscribeStamp`, once); no case approached the 15/20 s
timeouts. In the RN full run on the same machine, three passing cases took 19.0-24.5 s and one failed.

Inference [Provável]: the leak lives in what RN has and this SDK replaced in `core-port`: RN's process-wide
statics (`NottiImpl.activeCore`, `NottiEventBuffer.shared`, `NottiNetworkObserver.shared`, the
process-wide In-App coordinator), which keep cores and observers alive across tests, while this SDK's
tests use an isolated `NottiRuntime` per test. Not proven by instrumentation: not worth it, since RN
`ios-native-sdk` T6 deletes those tests and that core.

**Decision proposed for WRAP-10..13**: no code change here. Record the evidence above as a lesson
(WRAP-10), count the six runs toward WRAP-11 and repeat to ten in the release gate, mark WRAP-12 not
applicable (no leak observed), and note in the RN repo that the flake is RN-only and ends with T6
(WRAP-13).

---

## 4. Repro for `NottiSDK.Notti` (gate for section 2)

Run 2026-10-31 (Xcode 27.2, CocoaPods 1.17.0). Consumer code: `NottiSDK.Notti.logout()`.

| Consumer | Obj-C name `NottiSDK` (0.1.0) | Obj-C name `NottiSDKFacade` |
| --- | --- | --- |
| CocoaPods, static libraries | fails: `type 'NottiSDK' has no member 'Notti'` | compiles |
| CocoaPods, `use_frameworks! :linkage => :static` | fails, same error | compiles |
| CocoaPods, `use_frameworks! :linkage => :dynamic` | fails, same error | compiles |
| SPM (scratch executable, `.package(path:)`) | compiles | compiles |

CocoaPods consumers: the RN spike app with `pod 'NottiSDK'`/`'NottiSDKExtension'`, `:path =>` a scratch
worktree with only the `@objc(...)` line changed (the 0.1.0 column is the same app on the trunk pods).
Only CocoaPods is affected, because its module map exposes the generated Obj-C header to Swift clients;
SPM does not. **Gate passed: the rename fixes it.** [Certo]

---

## 5. Release 0.2.0 (WRAP-07..09)

- Bump `NottiSDKVersion.current` and both podspecs to `0.2.0`; `scripts/check-version.sh`.
- `pod lib lint` both podspecs, frameworks and `--use-libraries`.
- CHANGELOG `[0.2.0]`: SPI for wrappers (mentioned for wrapper authors only), Obj-C rename (upgrade note),
  test-harness fix.
- Tag, GitHub Release and `pod trunk push` for both pods by Julio, before the cutoff (AD-022). Check
  `pod trunk info` before retrying a failed push (lesson from 0.1.0).
