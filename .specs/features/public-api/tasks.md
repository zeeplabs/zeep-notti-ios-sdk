# Public API Tasks

**Design**: `.specs/features/public-api/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: `core-port` done (runtime, core, event buffer, logger, 252 tests)
**Status**: Draft (2026-10-11, awaiting Julio's approval)

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Generated from codebase, project guidelines and spec. Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: 252 tests (Shared 14, SDK 237, Ext 1). Counts below are minimums per task; the executor records the exact number.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| `NottiRuntime.ensureCore` | unit | Existing core reused, uninitialized core built, `start` after it still rebuilds | `Tests/NottiSDKTests/NottiRuntimeTests.swift` | `xcodebuild test ... -only-testing:NottiSDKTests/NottiRuntimeTests` |
| `NottiListenerHub`, `NottiSubscription` | unit | Attach on 0 to 1, detach on 1 to 0, order, re-entrancy, idempotent remove, main hop, replay to the first listener only | `Tests/NottiSDKTests/NottiListenerHubTests.swift` | same, `NottiListenerHubTests` |
| `NottiNotificationPayload` | unit | Full, partial and malformed core payloads | `Tests/NottiSDKTests/NottiNotificationPayloadTests.swift` | same |
| `NottiFacade` (initialize, profile, permission, listeners, log level) | unit | Each API-xx AC through the facade with an isolated runtime and stubbed HTTP | `Tests/NottiSDKTests/NottiFacade*Tests.swift` | same |
| Public Swift shell (`Notti`, `Notti.User`, `Notti.Notifications`) | unit | One call per public method reaches the facade; F1 test on `shared` | `Tests/NottiSDKTests/NottiPublicApiTests.swift` | same |
| Objective-C layer | unit (ObjC or Swift calling the `@objc` classes) | Every ObjC entry point called once; non-string tags dropped | `Tests/NottiSDKObjCTests/` (or fallback in design) | same, plus build |
| Cross-cutting (PII at `.verbose` through the facade) | unit | Sentinel sweep | `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift` | same |
| Scripts / CI workflow (`check-public-surface.sh`) | none | Verified by running it against a passing and a failing tree (T13) | - | the script itself |
| Docs (`traceability.md`, specs) | none | Every API-xx mapped to a test | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially.

## Gate Check Commands

> Generated from codebase (`.github/workflows/ci.yml`, `.specs/codebase/TESTING.md`). Xcode 27 note: run `xcodebuild test` through the watchdog in the scratchpad (a failing run does not terminate), and do not pipe its output into `grep`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | After T10 and T14 | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh` + `scripts/check-public-surface.sh` (from T13) + `pod lib lint NottiSDK.podspec --platforms=ios` |
| Build | Build-only checks and phase completion | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |

---

## Rules (apply to every task)

1. New code, so `write-swift` and `swift-concurrency` guidance applies, but in Swift 5 mode (AD-002): no actors, no `AsyncStream`, `Sendable` only on pure value types. `async` only where the spec lists it.
2. Do not edit ported core files (`NottiCore`, `NottiApiClient`, `NottiDeviceStore`, `NottiEventStore`, `NottiEventBuffer`). The only existing file that gains code is `NottiRuntime.swift` (T2).
3. Tests use isolated runtimes and UserDefaults suites. The single exception is the F1 test in T10.
4. Test fixtures are synthetic (`example.invalid`, `fixture`). No log message interpolates email, phone, token, external user id, country or tag values.
5. Every public declaration is added together with its entry in `PUBLIC_SURFACE.txt` once T13 exists; before T13, list new public symbols in the commit body.
6. Each task is one commit, conventional style, with no AI attribution.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe).

### Phase 1: Spike and building blocks

```
T1
T2
T3
T4
```

No edges: these four are independent. They run in this order because T1 may change names used later.

### Phase 2: Facade

```
T2 ──→ T5 ──→ T6
T6 ──→ T7
T3 ──→ T8
T4 ──→ T8
T6 ──→ T8
T6 ──→ T9
```

### Phase 3: Public surface

```
T7 ──→ T10
T8 ──→ T10
T9 ──→ T10
T10 ──→ T11
T1 ──→ T12
T10 ──→ T12
```

### Phase 4: Proofs and close

```
T12 ──→ T13
T11 ──→ T14
T13 ──→ T14
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14.

---

## Task Breakdown

### T1: Spike: Objective-C naming, nested `@objc` enum, ObjC test target ✅ (a: coexist OK; b: nested `@objc` enum compiles but is NOT exported to ObjC, use top-level `@objc(NottiLogLevel)` + typealias; c: SPM ObjC test target OK; original ObjC names kept, Julio to confirm)

**What**: Throwaway experiments in a scratch copy of the package (no production code committed). Answer three questions and write the answers into `design.md`: (a) can an `@objc(Notti)` class coexist with a Swift `enum Notti` in one module; (b) can `Notti.LogLevel` be `@objc` when nested in a non-`@objc` enum, otherwise how the ObjC level type is declared; (c) can an SPM ObjC test target import `NottiSDK`.
**Where**: `.specs/features/public-api/design.md` (new "Spike results" section)
**Depends on**: None
**Reuses**: nothing
**Requirement**: API-13

**Done when**:

- [x] Each of (a), (b), (c) has an observed result, not an assumption, with the command or snippet that showed it
- [x] Design records the chosen ObjC class names (original or the fallback `NottiSDKClient`/`NottiSDKUser`/`NottiSDKNotifications`) and the compile-check approach (SPM ObjC test target, or the pod-lint fallback)
- [x] If the fallback names are chosen, Julio confirms them before T12 (they are public)
- [x] No source or `Package.swift` change is committed

**Tests**: none
**Gate**: none (docs only)
**Commit**: `docs(specs): public-api spike results (ObjC naming and compile check)`

---

### T2: `NottiRuntime.ensureCore()` ✅ (NottiRuntimeTests 18 (13 + 5 new); SDK 242, Shared 14, Ext 1, total 257 (derived, confirmed in the T9 full run))

**What**: Add `ensureCore() -> NottiCore` to the runtime: returns the live core, or builds an uninitialized one and stores it as the current core, under `lifecycleLock`. `start` and `stop` are unchanged. Document that `core != nil` no longer implies "initialized".
**Where**: `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiRuntimeTests.swift`
**Depends on**: None
**Reuses**: `makeCore()`, `lifecycleLock`, existing runtime test helpers
**Requirement**: API-05, API-07

**Done when**:

- [x] `ensureCore()` returns the same instance on two calls, and `core` is non-nil afterwards
- [x] After `ensureCore()`, `start(...)` still invalidates that core and installs a new one (existing start-twice tests stay green)
- [x] An uninitialized core registers no `NotificationCenter` observer (asserted by posting `didBecomeActive` and seeing no network request)
- [x] `setEmail` on the ensured core persists the value in the suite
- [x] Test count: SDK +4 minimum (241)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiRuntimeTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(runtime): ensureCore for pre-initialize facade calls`

---

### T3: `NottiListenerHub` and `NottiSubscription` ✅ (NottiListenerHubTests 11 (10 + a second stress test); SDK 253, Shared 14, Ext 1, total 268. SPEC_DEVIATION: the recipient list is snapshotted at reception, not at main-execution time, so the replay inside attach reaches only the first listener even if a second is added before main runs; a removed listener is still skipped at call time. The add/remove stress test kills the missing-attachLock mutant)

**What**: Internal hub that multiplexes many handlers over one source handler, with the `NottiMainDispatcher` typealias, plus the public `NottiSubscription` class (idempotent `remove()`, releases the closure). Behavior as in design: `attachLock`, list updated before `attach`, snapshot at main-execution time, order of registration.
**Where**: `Sources/NottiSDK/Facade/NottiListenerHub.swift` (hub, dispatcher typealias and `NottiSubscription`, kept in one file because they are one mechanism)
**Depends on**: None
**Reuses**: `NottiEventBuffer.setHandler` semantics (as the `attach`/`detach` closures in tests)
**Requirement**: API-10, API-12

**Done when**:

- [x] `attach` is called once on 0 to 1 listeners, `detach` once on 1 to 0, never otherwise
- [x] With a source that replays synchronously inside `attach`, the first listener receives the replay and a second one does not
- [x] Every listener gets each event in registration order, through the injected dispatcher (a recording dispatcher proves the hop; delivery is never inline)
- [x] A listener that adds or removes a listener inside its callback does not deadlock, and the change applies from the next event
- [x] `remove()` twice is safe, and after `remove()` the handler is not called
- [x] A concurrent add/remove stress test never ends with the source attached to an empty list
- [x] Test count: SDK +8 minimum (249)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiListenerHubTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): listener hub and subscription token`

---

### T4: `NottiNotificationPayload` ✅ (NottiNotificationPayloadTests 9; SDK 262, Shared 14, Ext 1, total 277. SPEC_DEVIATION: `NottiPayloadKeys` has no title/body/data constants (`toEventPayload()` hardcodes them), so the payload keeps private key constants; the handler round-trip tests catch drift. Public init omitted on purpose (smaller surface))

**What**: Public `NottiNotificationPayload` (`title: String?`, `body: String?`, `data: [String: String]`, `Equatable`, `Sendable`) with an internal initializer from the core's `[String: Any]` using `NottiPayloadKeys`. Missing `data` gives `[:]`; non-string `data` values are dropped.
**Where**: `Sources/NottiSDK/Facade/NottiNotificationPayload.swift`, `Tests/NottiSDKTests/NottiNotificationPayloadTests.swift`
**Depends on**: None
**Reuses**: `NottiPayloadKeys`, the payload shape built by `NottiNotificationHandler`
**Requirement**: API-10, API-11

**Done when**:

- [x] Full payload, title-only, body-only, no `data`, and mixed-type `data` each map as specified
- [x] A payload built by `NottiNotificationHandler` (not hand-made) round-trips, so the key names cannot drift
- [x] Test count: SDK +5 minimum (254)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiNotificationPayloadTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): typed notification payload`

---

### T5: `NottiFacade` initialize and idempotency ✅ (NottiFacadeInitializeTests 9; SDK 271, Shared 14, Ext 1, total 286. The `http://` case is build-dependent: Debug (tests) accepts it per NottiApiClient A5, so the test asserts the Debug rule under `#if DEBUG` and the rejection otherwise)

**What**: Create `NottiFacade` (`init(runtime:dispatcher:)`) with `initialize(appId:clientKey:baseUrl:)`: default host `https://app.zeepnotti.app` when `baseUrl` is nil, normalization through `NottiApiClient.validatedBaseUrl`, invalid args logged at `.error` without values and ignored (a running core is untouched), same normalized config is a no-op, a different one calls `runtime.start`. Decision and `start` under the facade lock.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadeInitializeTests.swift`
**Depends on**: T2
**Reuses**: `NottiRuntime.start`, `NottiApiClient.validatedBaseUrl`, `StubURLProtocol`, `LogSink`
**Requirement**: API-01, API-02

**Done when**:

- [x] First `initialize` yields exactly one registration request; a second one with the same values yields none; with a different `appId` yields one more
- [x] Equal-after-normalization values (`https://x.example.invalid/` vs `https://x.example.invalid`) count as the same
- [x] Empty `appId`, empty `clientKey`, `http://` (release rule) and a scheme-less host each log one `.error` with no argument values and leave the running core in place
- [x] A nil `baseUrl` sends the request to the default host (asserted on the stubbed request URL)
- [x] Two racing different inits end with one consistent core and no leaked observer
- [x] Test count: SDK +9 minimum (263)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiFacadeInitializeTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): initialize with idempotency and default host`

---

### T6: `NottiFacade` identity and profile forwards ✅ (NottiFacadeProfileTests 14 + 1 new NottiRuntimeTests (19); SDK 286, Shared 14, Ext 1, total 301. SPEC_DEVIATION: the pre-initialize `setEmail` was lost when `start` replaced the ensured core (queued core blocks capture `self` weakly and the old core was released); `NottiRuntime.invalidateCurrentCore` now keeps the replaced core alive until its queue drains (bounded 60 s wait on a utility thread), verified: the new runtime test fails without it. No core file changed)

**What**: Add `login`, `logout`, `addTags`, `removeTags`, `setEmail`, `clearEmail`, `setPhone`, `clearPhone`, `setSubscription`, `setLocationSharingEnabled`, `deviceId`. All go through `runtime.ensureCore()` and forward one-to-one. `setLocationSharingEnabled` runs on the caller's thread.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadeProfileTests.swift`
**Depends on**: T5
**Reuses**: core methods, `StubURLProtocol` request assertions
**Requirement**: API-04, API-05, API-06, API-07, API-08

**Done when**:

- [x] Each method, on an initialized facade, produces the exact PATCH field (`external_user_id`, `tags` add and remove, `email`/`phone` with explicit null on clear, `subscribed` with `last_unsubscribed_at` on true to false)
- [x] Before `initialize`: `setEmail` and `setPhone` are persisted and sent on the next registration; `login`, tags and subscription send nothing and do not crash
- [x] `deviceId` returns a persisted id before `initialize`, `nil` for a never-registered device
- [x] `setLocationSharingEnabled(false)` writes the preference before the call returns (read back synchronously)
- [x] Test count: SDK +13 minimum (276)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiFacadeProfileTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): identity and profile forwarding`

---

### T7: `NottiFacade` permission request ✅ (NottiFacadePermissionTests 6; SDK 292, Shared 14, Ext 1, total 307)

**What**: Add `requestPermission(completion:)` and `requestPermission() async -> Bool`. The completion is wrapped in a once-guard and delivered on main through the dispatcher. Before `initialize` the core answers `false` without a prompt.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadePermissionTests.swift`
**Depends on**: T6
**Reuses**: `core.requestPermission(_:)`, the injected permission requester double
**Requirement**: API-09, API-12

**Done when**:

- [x] Granted and denied OS results come back as `true` and `false`, through the dispatcher
- [x] Before `initialize` the result is `false` and the requester double is never called
- [x] A double that calls the callback twice does not crash the async variant and delivers once
- [x] Two concurrent requests both complete
- [x] Test count: SDK +5 minimum (281)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiFacadePermissionTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): permission request with main-thread completion`

---

### T8: `NottiFacade` listeners and initial click ✅ (NottiFacadeListenerTests 13; SDK 305, Shared 14, Ext 1, total 320)

**What**: Wire three `NottiListenerHub`s: `received` and `clicked` over `eventBuffer.setHandler`, `deviceIdChanged` over `runtime.onDeviceIdChanged`; payloads become `NottiNotificationPayload`. Add `takeInitialClick()`.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadeListenerTests.swift`
**Depends on**: T3, T4, T6
**Reuses**: `NottiEventBuffer`, `NottiListenerHub`, `NottiNotificationPayload`
**Requirement**: API-05, API-10, API-11, API-12

**Done when**:

- [x] Two `received` listeners both get a live event once, in order, on the dispatcher; the first one also gets the buffered replay and the second does not
- [x] Removing the last listener detaches the buffer handler, so a later event is buffered and replayed to the next first listener
- [x] `clicked` is never replayed to listeners; the cold-start click is available once through `takeInitialClick()` and `nil` the second time
- [x] A listener registered before `initialize` receives events
- [x] `deviceIdChanged` fires once per real change and not on a re-registration with the same id
- [x] A removed `deviceIdChanged` listener is not called again
- [x] Test count: SDK +12 minimum (293)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiFacadeListenerTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): multiplexed notification and device-id listeners`

---

### T9: Log level mapping ✅ (NottiFacadeLogLevelTests 5; full run: SDK 310, Shared 14, Ext 1, total 325; SwiftLint 0; guard scripts and `pod lib lint` green. SPEC_DEVIATION: the public level enum is the top-level `@objc(NottiLogLevel) public enum NottiLogLevelObjC` (T1 spike: a nested `@objc` enum is not exported to ObjC); the `Notti.LogLevel` typealias is added with the `Notti` namespace in T10 (this task may not touch Sources/NottiSDK/Public/))

**What**: Public `Notti.LogLevel` (`none`, `error`, `warn`, `info`, `debug`, `verbose`) and facade `logLevel` get/set mapped to `NottiLogger.level`, with a two-way mapping that fails to compile on a new `NottiLogLevel` case.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Tests/NottiSDKTests/NottiFacadeLogLevelTests.swift`
**Depends on**: T6
**Reuses**: `NottiLogger.level`, `NottiLogger.sink`
**Requirement**: API-14

**Done when**:

- [x] Every level round-trips, and a message at a level above the setting is not emitted
- [x] The level seen before any set is `.error` (initial effective level, per lesson L-010: read through the facade, not the constant)
- [x] The test restores the level in `tearDown`
- [x] Test count: SDK +4 minimum (297)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiFacadeLogLevelTests`

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): public log level`

---

### T10: Public Swift shell and F1 test ✅ (NottiPublicApiTests 14; SDK 324, Shared 14, Ext 1, total 339; F1 mutant (suite name in `NottiRuntime.shared`) fails the F1 test, reverted; internal seam `NottiFacade.setSharedForTesting(_:)`; `Notti.LogLevel` is a typealias of `NottiLogLevelObjC`; strict device builds of SDK and NSE, `pod lib lint` all and Extension, SwiftLint 0 and the 3 scripts green)

**What**: Add `Notti`, `Notti.Options`, `Notti.User`, `Notti.Notifications` and the static entry points, forwarding to `NottiFacade.shared` (built on `NottiRuntime.shared`), marked `@available(iOSApplicationExtension, unavailable)`. Add the F1 test: write a device id into the `notti_prefs` suite directly, assert `Notti.deviceId` reads it, remove the key.
**Where**: `Sources/NottiSDK/Public/Notti.swift`, `Tests/NottiSDKTests/NottiPublicApiTests.swift`
**Depends on**: T7, T8, T9
**Reuses**: `NottiFacade`, `NottiRuntime.shared`
**Requirement**: API-01, API-03, API-15

**Done when**:

- [x] Every public method has a test proving it reaches the facade (through an injectable `NottiFacade.shared` seam that exists only for tests, `internal`)
- [x] F1: changing the suite name used by `NottiRuntime.shared` makes the F1 test fail (mutant verified and reverted)
- [x] `NottiSDKExtension` and `NottiShared` expose no new public symbol; `check-extension-safety.sh` and `check-package-graph.sh` pass
- [x] SwiftLint `--strict` clean; strict device build of `NottiSDK` and of the NSE (`APPLICATION_EXTENSION_API_ONLY=YES`) pass
- [x] Test count: SDK +4 minimum (301)
- [x] Gate passes: full

**Tests**: unit
**Gate**: full
**Commit**: `feat(api): public Swift facade (Notti, User, Notifications)`

---

### T11: No PII at `.verbose` through the facade ✅ (NottiLoggingPrivacyTests 6 (4 + 2 facade flows); SDK 326, Shared 14, Ext 1, total 341; mutant `NottiLogger.log(.debug, "... \(externalUserId)")` in `NottiFacade.login` fails both new tests, reverted. The sweep also covers appId, clientKey, baseUrl and the invalid-initialize arguments)

**What**: Extend the sentinel test so a flow driven only through the facade (initialize, login, setEmail, setPhone, tags, location, event flush, a failing registration) runs at `.verbose` and no sentinel appears in the sink.
**Where**: `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`
**Depends on**: T10
**Reuses**: `LogSink`, existing sentinel helpers
**Requirement**: API-14, API-15

**Done when**:

- [x] Sentinels for email, phone, token, external user id, country and a tag value never appear in any emitted line
- [x] A throwaway mutant that interpolates the external id in a facade log line is killed (verified and reverted)
- [x] Test count: SDK +1 minimum (302)
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiLoggingPrivacyTests`

**Tests**: unit
**Gate**: quick
**Commit**: `test(facade): no PII in logs at verbose through the public facade`

---

### T12: Objective-C layer and compile check

**What**: Add the three `@objc` classes with the names chosen in T1 (completion blocks, `NSDictionary` payloads, tags through `sanitizeTags`) and the compile check chosen in T1 (SPM ObjC test target, or the fallback).
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`
**Depends on**: T1, T10
**Reuses**: `NottiFacade`, `NottiRuntime.sanitizeTags`
**Requirement**: API-13

**Done when**:

- [ ] Every P1 capability is callable from Objective-C, and the compile check fails if one entry point is removed (verified by deleting one and reverting)
- [ ] Non-string tag values are dropped through the ObjC path (test)
- [ ] The ObjC layer adds no behavior beyond bridging types
- [ ] `pod lib lint NottiSDK.podspec --platforms=ios` and the Extension subspec lint still pass
- [ ] If the fallback compile check was used, `STATE.md` has a todo for the full ObjC host check in `example-and-release`
- [ ] Test count: +3 minimum in the ObjC check
- [ ] Gate passes: full

**Tests**: unit (ObjC compile check)
**Gate**: full
**Commit**: `feat(api): Objective-C interop layer`

---

### T13: Public surface guard

**What**: Add `scripts/check-public-surface.sh`, the committed `.specs/codebase/PUBLIC_SURFACE.txt`, and a CI step in the `checks` job. The script lists `public`/`open` declarations in `Sources/NottiSDK`, diffs them against the file, fails on any `public` in `Sources/NottiShared`, and prints the diff on failure.
**Where**: `scripts/check-public-surface.sh`
**Depends on**: T12
**Reuses**: the style of `check-extension-safety.sh`
**Requirement**: API-15

**Done when**:

- [ ] Passes on the tree as committed
- [ ] Fails, with the diff, after adding a throwaway `public func` (verified and reverted)
- [ ] Fails after removing a listed public symbol, and after a `public` appears in `NottiShared`
- [ ] Runs on the Linux `checks` job (GNU tools only, no `swift` needed) and the CI step is added in the same commit
- [ ] `AGENTS.md` mentions the script in the commands and rules (rule: new public API updates the surface file)
- [ ] Gate passes: the script on a clean tree, plus the three existing scripts

**Tests**: none (scripts, per the coverage matrix: run against a passing and a failing tree)
**Gate**: build
**Commit**: `ci: guard the public API surface`

---

### T14: Traceability, docs and full gate

**What**: Write `.specs/features/public-api/traceability.md` mapping each API-xx and inherited ID (SDK-17..19, SDKOPEN-10, DPF-17..21 facade part) to its tests. Update `TESTING.md` (new layers and files), `STATE.md` (close F1 and N1, keep N7), `ROADMAP.md` and the spec's traceability statuses. Run the full gate once more on the final tree.
**Where**: `.specs/features/public-api/traceability.md`
**Depends on**: T11, T13
**Reuses**: core-port `traceability.md` layout
**Requirement**: API-01..API-15

**Done when**:

- [ ] Every API-xx has at least one named test, or a stated reason (docs/script requirements point to T13)
- [ ] `validate_tasks.py`, `validate_spec.py` and `validate_state.py` exit 0
- [ ] Full gate green: tests, SwiftLint 0, four scripts, `pod lib lint` (all and Extension), strict device builds; test count at least 252 plus the minimums above
- [ ] `STATE.md` Current Work says Execute done and Verifier pending

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): public-api traceability and gate`

---

## Granularity Check

Each task touches one component and its test file, with these deliberate exceptions: T1 (docs only, spike), T3 (hub, dispatcher typealias and subscription share one file because they are one mechanism), T10 (the public shell is one file plus its test; it carries the F1 test because F1 needs the public entry point), T13 (script plus its committed surface file, CI step and a one-line AGENTS.md note, because a guard without CI wiring is the gap L-004 warns about).

## Diagram-Definition Cross-Check

The diagrams above match the `Depends on` fields. T1 to T4 have no edges. T12 depends on T1 for the names and the compile-check approach, not for code. T13 follows T12 so that the baseline already includes the ObjC layer.

## Test Co-location Validation

Every task that adds code ships its tests in the same commit (AGENTS.md). Tasks with `Tests: none` are docs, the spike, and the guard script, matching the Test Coverage Matrix.

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| API-01 | T5, T10 |
| API-02 | T5 |
| API-03 | T10 |
| API-04 | T6 |
| API-05 | T2, T6, T8 |
| API-06 | T6 |
| API-07 | T2, T6 |
| API-08 | T6 |
| API-09 | T7 |
| API-10 | T3, T4, T8 |
| API-11 | T4, T8 |
| API-12 | T3, T7, T8 |
| API-13 | T1, T12 |
| API-14 | T9, T11 |
| API-15 | T10, T11, T13 |

15 requirements, 15 mapped to tasks.
