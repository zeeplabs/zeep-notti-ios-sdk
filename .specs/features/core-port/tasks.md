# Core Port Tasks

**Design**: `.specs/features/core-port/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Source baseline**: `../zeep-notti-react-native/ios` at `52e4b55`
**Depends on feature**: `package-foundation` done (all 12 tasks) (targets, `NottiLogger`, `NottiPayloadKeys`, `NottiSDKVersion`, CI)
**Status**: Approved (2026-10-09; reformatted 2026-10-09 to the current `tlc-spec-driven` template: task ids `C1..C13` renamed to `T1..T13`, no task content changed)

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec. Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Parity floor: the RN iOS suite at `52e4b55` (each ported file keeps at least its RN test count).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| `NottiShared` (parsing, keys, logger) | unit | Every RN test ported 1:1; all branches of the moved code | `Tests/NottiSharedTests/*Tests.swift` | `xcodebuild test ... -only-testing:NottiSharedTests/<Class>` |
| Storage (`NottiDeviceStore`, `NottiEventStore`) | unit | RN tests 1:1 + golden key list + corrupt-queue path | `Tests/NottiSDKTests/Notti*StoreTests.swift` | `xcodebuild test ... -only-testing:NottiSDKTests/<Class>` |
| Network (`NottiApiClient`, `NottiNetworkObserver`) | unit | RN tests 1:1 (endpoints, headers, retry/backoff, transient vs terminal) + log redaction | `Tests/NottiSDKTests/NottiApiClientTests.swift`, `NottiNetworkObserverTests.swift` | same |
| Events (`NottiEventBuffer`, `NottiNotificationHandler`) | unit | RN tests 1:1; every PushDelegate test accounted; body tap / custom action / dismiss / non-remote / cold start | `Tests/NottiSDKTests/NottiEvent*Tests.swift`, `NottiNotificationHandlerTests.swift` | same |
| Core (`NottiCore`) | unit | All 123 RN tests; inherited SDK-/SDKCTR-/SDKOPEN-/SEGTEL-/DPF- ACs | `Tests/NottiSDKTests/NottiCoreTests.swift` | same |
| Runtime (`NottiRuntime`) | unit | Every CORE- AC it implements (CORE-02/03/05/08) + SDK-04/12/13 direct tests | `Tests/NottiSDKTests/NottiRuntimeTests.swift` | same |
| Platform providers (`live()` OS closures) | none (build) | Build gate; pure helpers, if any, get unit tests | - | build gate |
| Cross-cutting proofs (PII in logs, RN continuity) | unit | CORE-09..13 each asserted directly | `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`, `NottiContinuityTests.swift` | same |
| Docs (`traceability.md`) | none | Every iOS-applicable RN ID mapped or justified | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially or in separate worktrees.

## Gate Check Commands

> Generated from codebase (`.github/workflows/ci.yml`, `.specs/codebase/TESTING.md`).

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | After T7 (core) and T13 (parity proof) | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh` + `pod lib lint NottiSDK.podspec --platforms=ios` |
| Build | Build-only tasks (T8 providers) and phase completion | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |

---

## Porting rules (apply to every task)

1. Copy the RN file, then change only what the task lists. Every other diff line against RN is a defect.
2. `public` → `internal` in `NottiSDK`; `package` (or `@_spi`, per AD-006) in `NottiShared`.
3. Port the RN test file 1:1. Renaming is allowed only where the name is RN-specific (e.g. "JS click" → "buffered click"). Each rename is listed in `traceability.md`.
4. Tests use isolated UserDefaults suites and isolated `NottiRuntime` instances, never `.shared`.
5. No log message interpolates email, phone, token, external user id, country or tag values.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe).

### Phase 1: Leaf components

```
T1 ──→ T2 ──→ T3 ──→ T4 ──→ T5 ──→ T6
```

T2..T6 have no code dependency on each other; the arrows only reflect sequential execution (shared build). T1 goes first because it touches `NottiShared`, which every later target imports.

### Phase 2: Engine

```
T2 ──→ T7
T3 ──→ T7
T5 ──→ T7
T6 ──→ T7
```

### Phase 3: Runtime and handler

```
T7 ──→ T8 ──→ T9 ──→ T10
T4 ──→ T10
```

### Phase 4: Cross-cutting proofs

```
T10 ──→ T11
T9 ──→ T12
T11 ──→ T13
T12 ──→ T13
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13.

---

## Task Breakdown

### T1: Move `NottiNotificationParsing` to `NottiShared` ✅ (NottiSharedTests 12/12; NottiSDKTests 2, NottiSDKExtensionTests 1, total 15; 4-space reindent + file-scoped lint disables per AD-007)

**What**: Port the parser into `NottiShared` with `package` access, replacing its literal keys with `NottiPayloadKeys`; port its 6 tests.
**Where**: `Sources/NottiShared/NottiNotificationParsing.swift`, `Tests/NottiSharedTests/NottiNotificationParsingTests.swift`
**Depends on**: package-foundation done
**Reuses**: RN `ios/NottiNotificationParsing.swift` (98), `ios/Tests/NottiNotificationParsingTests.swift`
**Requirement**: CORE-01, CORE-06

**Done when**:

- [x] Behavior unchanged; only access level and key constants differ from RN
- [x] `scripts/check-extension-safety.sh` still passes
- [x] Gate passes: quick `-only-testing:NottiSharedTests/NottiNotificationParsingTests`
- [x] Test count: NottiSharedTests 12 (6 + 6)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(shared): port NottiNotificationParsing from RN`

---

### T2: Port `NottiDeviceStore` + golden key test ✅ (NottiSDKTests 21 (2 + 18 ported + 1 golden); Shared 12, Ext 1, total 34. Golden test writes through the store and reads the raw suite (keys are private in RN); a renamed key was verified to fail it)

**What**: Port the store verbatim (`internal`), its 18 tests, and add `NottiDeviceStoreKeysTests`, which asserts the key constants equal a frozen list copied from RN.
**Where**: `Sources/NottiSDK/Storage/NottiDeviceStore.swift`, `Tests/NottiSDKTests/NottiDeviceStoreTests.swift`, `Tests/NottiSDKTests/NottiDeviceStoreKeysTests.swift`
**Depends on**: T1
**Reuses**: RN `ios/NottiDeviceStore.swift` (450; keys at :88-117), `ios/Tests/NottiDeviceStoreTests.swift`, RN README:532-560
**Requirement**: CORE-01, CORE-02, CORE-06, CORE-09

**Done when**:

- [x] Every key string and value encoding identical to RN
- [x] Golden test covers every key, including `notti_session_last_seen_at_ms` and `notti_profile_field_ack_migrated`
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiDeviceStoreTests -only-testing:NottiSDKTests/NottiDeviceStoreKeysTests`
- [x] Test count: +19 (18 ported + 1 golden)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(storage): port NottiDeviceStore with frozen key test`

---

### T3: Port `NottiEventStore` ✅ (NottiSDKTests 28 (21 + 6 ported + 1 corrupt-queue); Shared 12, Ext 1, total 41. The warn fires per read while the corrupt value is stored (RN overwrites it on the next enqueue))

**What**: Port the store verbatim and its 6 tests; add a `.warn` log when `notti_pending_events` fails to decode (the queue is still dropped, as in RN), plus 1 test for it.
**Where**: `Sources/NottiSDK/Storage/NottiEventStore.swift`, `Tests/NottiSDKTests/NottiEventStoreTests.swift`
**Depends on**: T2
**Reuses**: RN `ios/NottiEventStore.swift` (138; key at :61), `ios/Tests/NottiEventStoreTests.swift`
**Requirement**: CORE-01, CORE-06, CORE-09, edge case "corrupt queue"

**Done when**:

- [x] `PendingEvent` Codable field names unchanged
- [x] New test: corrupt data → empty queue, no crash, one `.warn` reaches `NottiLogger.sink`
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiEventStoreTests`
- [x] Test count: +7 (6 + 1)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(storage): port NottiEventStore and log corrupt-queue drops`

---

### T4: Port `NottiEventBuffer` without the static ✅ (NottiSDKTests 40 (28 + 12); Shared 12, Ext 1, total 53)

**What**: Port the buffer verbatim minus `static let shared`; port its 12 tests to instances.
**Where**: `Sources/NottiSDK/Events/NottiEventBuffer.swift`, `Tests/NottiSDKTests/NottiEventBufferTests.swift`
**Depends on**: T3
**Reuses**: RN `ios/NottiEventBuffer.swift` (141), `ios/Tests/NottiEventBufferTests.swift`
**Requirement**: CORE-01, CORE-03, CORE-06

**Done when**:

- [x] No `shared` member; no other diff against RN except access level
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiEventBufferTests`
- [x] Test count: +12

**Tests**: unit
**Gate**: quick
**Commit**: `feat(events): port NottiEventBuffer as an owned instance`

---

### T5: Port `NottiApiClient` + `StubURLProtocol` ✅ (NottiSDKTests 70 (40 + 29 ported + 1 domain#code); Shared 12, Ext 1, total 83. RN's ApiClient has no logger: the change is the failure message (`lastError`) the core logs; the localizedDescription mutant was verified to fail the new test. The semaphore-backstop `NottiApiClientTimeoutError` now reports its Swift-bridged domain instead of 'Notti API request timed out')

**What**: Port the client verbatim and its 29 tests, plus `StubURLProtocol` into test support. Error logs use `"\(error.domain)#\(error.code)"` instead of `localizedDescription` (NottiApiClient:248-289); add 1 test asserting a `URLError` log line contains no URL.
**Where**: `Sources/NottiSDK/Network/NottiApiClient.swift`, `Tests/NottiSDKTests/NottiApiClientTests.swift`, `Tests/NottiSDKTests/Support/StubURLProtocol.swift`
**Depends on**: T4
**Reuses**: RN `ios/NottiApiClient.swift` (405), `ios/Tests/NottiApiClientTests.swift`, `ios/Tests/StubURLProtocol.swift`
**Requirement**: CORE-01, CORE-02, CORE-06, CORE-12; edge case "http rejected in release"

**Done when**:

- [x] Endpoints, headers (`Authorization: Bearer`), retry (5 attempts, 2/4/8/16s; 408/429/5xx transient) unchanged
- [x] Only logging lines differ from RN besides access level
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiApiClientTests`
- [x] Test count: +30 (29 + 1)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(network): port NottiApiClient and log errors as domain#code`

---

### T6: Port `NottiNetworkObserver` without the static ✅ (NottiSDKTests 74 (70 + 4); Shared 12, Ext 1, total 87. RN had FakePathMonitor inline; moved to Support/)

**What**: Port the observer minus `static let shared`; the "network available" callback is injected (the runtime wires it in T9). Port its 4 tests and add `FakePathMonitor` to test support if RN had it inline.
**Where**: `Sources/NottiSDK/Network/NottiNetworkObserver.swift`, `Tests/NottiSDKTests/NottiNetworkObserverTests.swift`, `Tests/NottiSDKTests/Support/FakePathMonitor.swift`
**Depends on**: T5
**Reuses**: RN `ios/NottiNetworkObserver.swift` (116; static at :58-59), `ios/Tests/NottiNetworkObserverTests.swift`
**Requirement**: CORE-01, CORE-02, CORE-03, CORE-06

**Done when**:

- [x] No reference to `NottiImpl` or any global; callback injected
- [x] Gate passes: quick `-only-testing:NottiSDKTests/NottiNetworkObserverTests`
- [x] Test count: +4

**Tests**: unit
**Gate**: quick
**Commit**: `feat(network): port NottiNetworkObserver with an injected callback`

---

### T7: Port `NottiCore`

**What**: Port `NottiCore.swift` verbatim, change `logger: (String) -> Void` to `logger: (NottiLogLevel, String) -> Void` and give each of the 24 call sites a level (failure/give-up `.error`, retry/degraded `.warn`, lifecycle `.debug`; message text unchanged). Port the 123 tests and the core test doubles (`ThreadProbeApiClient`, `PatchHookApiClient`, `SlowEventApiClient`) to `Support/`.
**Where**: `Sources/NottiSDK/Core/NottiCore.swift`, `Tests/NottiSDKTests/NottiCoreTests.swift`, `Tests/NottiSDKTests/Support/*.swift`
**Depends on**: T2, T3, T5, T6
**Reuses**: RN `ios/NottiCore.swift` (1439), `ios/Tests/NottiCoreTests.swift` (2937)
**Requirement**: CORE-01, CORE-02, CORE-06; inherited SDK-, SDKCTR-, SDKOPEN-, SEGTEL-, DPF- behaviors

**Done when**:

- [ ] `diff` against RN shows only: access level, logger signature, the 24 call-site levels
- [ ] Serial queue label `app.notti.sdk.core` and semaphore timeouts unchanged
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiCoreTests`
- [ ] Test count: +123
- [ ] Full gate passes (SwiftLint thresholds hold for the 1439-line file)

**Tests**: unit
**Gate**: full
**Commit**: `feat(core): port NottiCore with leveled logging`

---

### T8: `NottiPlatformProviders`, location reader, background task

**What**: Move the provider closures from `NottiImpl.init` (:108-233) into `NottiPlatformProviders` with `static func live()` marked `@available(iOSApplicationExtension, unavailable)`; port `NottiLocationReader` (:389-462) and `NottiBackgroundTask` (:274-302). Unit-test the pure parts (e.g. hex/locale/timezone formatting, if any are pure); OS-backed closures are build-verified.
**Where**: `Sources/NottiSDK/Platform/NottiPlatformProviders.swift`, `Sources/NottiSDK/Platform/NottiLocationReader.swift`, `Sources/NottiSDK/Platform/NottiBackgroundTask.swift`, `Tests/NottiSDKTests/NottiPlatformProvidersTests.swift` (only if a pure helper exists)
**Depends on**: T7
**Reuses**: RN `ios/NottiImpl.swift` closure bodies verbatim, including main-thread hops (:131, :208, :419-422, :452)
**Requirement**: CORE-01, CORE-02

**Done when**:

- [ ] Every `NottiCore.init` provider parameter has a matching field
- [ ] No `RCT*`/React symbol; `live()` carries the extension-unavailable attribute
- [ ] Gate passes: build (and quick for the providers test file if created)
- [ ] Test count: unchanged or + number of pure-helper tests (stated in the summary)

**Tests**: build (matrix: platform providers) + unit for pure helpers
**Gate**: build
**Commit**: `feat(platform): port OS-backed providers from NottiImpl`

---

### T9: `NottiRuntime`

**What**: The container per design: `shared`, injectable `init`, `eventStore`/`eventBuffer`/`sessionGate`, lock-protected `core`, `start` (invalidate old core first; `sdkVersion: NottiSDKVersion.current`), `stop`, `onDeviceIdChanged`, `onNetworkAvailable`, `onApnsToken` (hex), `onApnsRegistrationFailed`, `sanitizeTags` (from NottiImpl:325-341), background observer and network observer started in `init`.
**Where**: `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiRuntimeTests.swift`
**Depends on**: T8
**Reuses**: RN `NottiImpl` init (:108-233), statics (:25-68), `NottiBridge` hex (PushDelegate:17-26)
**Requirement**: CORE-02, CORE-03, CORE-05; inherited SDK-04, SDK-12, SDK-13 (direct core-layer tests, CORE-08); SEGTEL-08 notes

**Done when**:

- [ ] Tests (isolated runtime, stub HTTP):
  - `start` sends `sdk_version` equal to `NottiSDKVersion.current`; empty constant omits the field (CORE-05)
  - `start` twice: first core invalidated, second adopts the open session, `session_count` unchanged
  - `onApnsToken` converts bytes to lowercase hex and reaches `onTokenRefreshed`
  - `onApnsRegistrationFailed`: `.error` log with domain#code, no crash, no registration, core still usable (SDK-04)
  - `onNetworkAvailable` with no core is a no-op
  - `sanitizeTags` keeps only string values (RN parity)
  - SDK-12 and SDK-13 direct tests at this layer (behavior per RN spec; names recorded in traceability)
- [ ] No mutable static besides `shared`
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiRuntimeTests`
- [ ] Test count: +≥8 (exact number stated in the summary)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(runtime): add NottiRuntime replacing RN process statics`

---

### T10: `NottiNotificationHandler`

**What**: Plain-input handler split from `NottiPushDelegate` (:51-138): `handleWillPresent(userInfo:identifier:)`, `handleResponse(actionIdentifier:userInfo:identifier:)`, `enqueueIfReportable` (requires `notification_id` + `delivery_id`, persists to `runtime.eventStore`, calls `runtime.core?.onNetworkAvailable()`). Rewrite the logic assertions of the 15 `NottiPushDelegateTests` against plain inputs.
**Where**: `Sources/NottiSDK/Events/NottiNotificationHandler.swift`, `Tests/NottiSDKTests/NottiNotificationHandlerTests.swift`
**Depends on**: T9, T4
**Reuses**: RN `ios/NottiPushDelegate.swift` (:51-138), `ios/Tests/NottiPushDelegateTests.swift`
**Requirement**: CORE-04, CORE-06, CORE-08 (SDK-17 core layer); SDKCTR-, SDKOPEN-01..08 (AD-003 option B)

**Done when**:

- [ ] Non-remote (`aps` absent) inputs are ignored in both entry points
- [ ] Body tap: one `opened` + one `clicked` enqueued, one buffered click; custom action: `clicked` only, no buffered click; dismiss: nothing
- [ ] Cold start: handler on a runtime with no core persists the event; a later `start` + successful registration flushes it (CORE-04)
- [ ] Each of the 15 RN tests accounted for: ported here, or moved to `delegate-integration` (UNNotification KVC fixtures), with reason
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiNotificationHandlerTests`
- [ ] Test count: +≥15 (exact number stated in the summary)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(events): add NottiNotificationHandler with plain inputs`

---

### T11: No-PII-in-logs flow test

**What**: One test that runs initialize → token → register → login(sentinel) → setEmail(sentinel) → setPhone(sentinel) → addTags(sentinel) → event flush with injected failures, at `.verbose`, capturing `NottiLogger.sink`, and asserts no sentinel (including the token hex) appears. A second test asserts the default level is `.error` and nothing below it is emitted.
**Where**: `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`
**Depends on**: T10
**Reuses**: `StubURLProtocol`, isolated runtime
**Requirement**: CORE-12, CORE-13

**Done when**:

- [ ] Sentinels are synthetic (`sentinel-email@example.invalid`, etc.)
- [ ] The flow produces at least one log line per level used (proves the sink is wired, not silently empty)
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiLoggingPrivacyTests`
- [ ] Test count: +2

**Tests**: unit
**Gate**: quick
**Commit**: `test(core): assert no PII in logs across a full flow`

---

### T12: RN 0.6.0 continuity fixture

**What**: Hand-author `rn-0.6.0-state.plist` from RN key/encoding definitions with synthetic values (device id, token, tags, external id, subscribed, profile fields + acks + `notti_profile_field_ack_migrated`, session counters + `notti_session_last_seen_at_ms`, two pending events written by hand from `PendingEvent` field names). Add `.copy("Fixtures")` to the test target and a test that loads it into a per-test suite and starts the runtime.
**Where**: `Tests/NottiSDKTests/Fixtures/rn-0.6.0-state.plist`, `Package.swift` (test resources), `Tests/NottiSDKTests/NottiContinuityTests.swift`
**Depends on**: T9
**Reuses**: RN `NottiDeviceStore.swift:88-117`, `NottiEventStore.swift:61`, README:532-560
**Requirement**: CORE-09, CORE-10, CORE-11

**Done when**:

- [ ] No real PII in the fixture (only `example.invalid` / `fixture` values)
- [ ] Test: no `POST /devices` when RN would not re-register; `getDeviceId()` returns the fixture id; the 2 pending events flush with their original `delivery_id`s
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiContinuityTests`
- [ ] Test count: +≥1

**Tests**: unit
**Gate**: quick
**Commit**: `test(storage): add RN 0.6.0 continuity fixture test`

---

### T13: Traceability and parity proof

**What**: Write `traceability.md` mapping every iOS-applicable RN ID (SDK-, SDKCTR-, SDKOPEN-, SEGTEL-, DPF-) to test names here, with N/A rows and reasons (Android-only, `public-api`, `delegate-integration`, `example-and-release`), the RN → here test count table, and the list of renamed/moved/dropped tests. Run the full gate and the RN-symbol grep.
**Where**: `.specs/features/core-port/traceability.md`, `.specs/features/core-port/spec.md` (status column)
**Depends on**: T11, T12
**Reuses**: RN `.specs/features/*/spec.md` requirement tables
**Requirement**: CORE-06, CORE-07, CORE-08

**Done when**:

- [ ] No iOS-applicable RN ID without a test or an explicit move/N/A reason
- [ ] Count table: here ≥ RN per file (Core 123, ApiClient 29, DeviceStore 18, EventBuffer 12, EventStore 6, Parsing 6, NetworkObserver 4; PushDelegate 15 accounted)
- [ ] `grep -rnE "RCT|React" Sources/` is empty
- [ ] Full gate passes; CI green on the PR
- [ ] spec.md requirement statuses updated

**Tests**: none (documentation + gate run)
**Gate**: full
**Commit**: `docs(specs): add core-port traceability and parity proof`

---

## Granularity Check

| Task | Scope | Status |
| --- | --- | --- |
| T1–T6 | 1 ported file + its test file (+ 1 test helper in T5/T6) | ✅ |
| T7 | 1 ported file + its test file + test doubles | ⚠️ OK: verbatim port; splitting the file is deferred by design |
| T8 | 3 small files from one RN source (`NottiImpl`) | ⚠️ OK, cohesive (one RN origin, no logic change) |
| T9 | 1 type + tests | ✅ |
| T10 | 1 type + tests | ✅ |
| T11 | 1 test file | ✅ |
| T12 | 1 fixture + 1 test + 1 manifest line | ✅ |
| T13 | 1 doc | ✅ |

## Diagram-Definition Cross-Check

| Task | Depends on (body) | Diagram shows | Status |
| --- | --- | --- | --- |
| T1 | package-foundation | entry | ✅ |
| T2 | T1 | T1 → T2 | ✅ |
| T3 | T2 | T2 → T3 | ✅ |
| T4 | T3 | T3 → T4 | ✅ |
| T5 | T4 | T4 → T5 | ✅ |
| T6 | T5 | T5 → T6 | ✅ |
| T7 | T2, T3, T5, T6 | T2, T3, T5, T6 → T7 | ✅ |
| T8 | T7 | T7 → T8 | ✅ |
| T9 | T8 | T8 → T9 | ✅ |
| T10 | T9, T4 | T9 → T10, T4 → T10 | ✅ |
| T11 | T10 | T10 → T11 | ✅ |
| T12 | T9 | T9 → T12 | ✅ |
| T13 | T11, T12 | T11, T12 → T13 | ✅ |

No `[P]` tasks (TESTING.md: not parallel-safe).

## Test Co-location Validation

| Task | Code layer | Matrix requires | Task says | Status |
| --- | --- | --- | --- | --- |
| T1 | `NottiShared` | unit | unit | ✅ |
| T2 | storage | unit | unit | ✅ |
| T3 | storage | unit | unit | ✅ |
| T4 | events | unit | unit | ✅ |
| T5 | network | unit | unit | ✅ |
| T6 | network | unit | unit | ✅ |
| T7 | core | unit | unit | ✅ |
| T8 | platform providers | build (+ unit for pure helpers) | build + unit | ✅ |
| T9 | runtime | unit | unit | ✅ |
| T10 | events | unit | unit | ✅ |
| T11 | tests only | unit | unit | ✅ |
| T12 | tests + fixture | unit | unit | ✅ |
| T13 | docs | none | none | ✅ |

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| CORE-01 | T1–T8 |
| CORE-02 | T2, T5, T6, T7, T8, T9 |
| CORE-03 | T4, T6, T9 |
| CORE-04 | T10 |
| CORE-05 | T9 |
| CORE-06 | T1–T7, T10, T13 |
| CORE-07 | T13 |
| CORE-08 | T9, T10, T13 |
| CORE-09 | T2, T3, T12 |
| CORE-10 | T12 |
| CORE-11 | T12 |
| CORE-12 | T5, T11 |
| CORE-13 | T11 |

13/13 mapped. Inherited RN IDs are mapped test-by-test in T13.

Expected `NottiSDKTests` total after T13: ≥ 2 (foundation) + 19 + 7 + 12 + 30 + 4 + 123 + 8 + 15 + 2 + 1 = ≥ 223. `NottiSharedTests`: 12.
