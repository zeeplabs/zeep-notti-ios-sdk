# Core Port Tasks

**Design**: `.specs/features/core-port/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Source baseline**: `../zeep-notti-react-native/ios` at `52e4b55`
**Depends on feature**: `package-foundation` T1–T12 done (targets, `NottiLogger`, `NottiPayloadKeys`, `NottiSDKVersion`, CI)
**Status**: Approved (2026-10-09)

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
C1 ──→ C2 ──→ C3 ──→ C4 ──→ C5 ──→ C6
```

C2..C6 have no code dependency on each other; the arrows only reflect sequential execution (shared build). C1 goes first because it touches `NottiShared`, which every later target imports.

### Phase 2: Engine

```
C2, C3, C5, C6 ──→ C7
```

### Phase 3: Runtime and handler

```
C7 ──→ C8 ──→ C9 ──→ C10
C4 ─────────────────→ C10
```

### Phase 4: Cross-cutting proofs

```
C10 ──→ C11
C9  ──→ C12
C11, C12 ──→ C13
```

Sequential order used in Execute: C1 → C2 → C3 → C4 → C5 → C6 → C7 → C8 → C9 → C10 → C11 → C12 → C13.

---

## Task Breakdown

### C1: Move `NottiNotificationParsing` to `NottiShared`

**What**: Port the parser into `NottiShared` with `package` access, replacing its literal keys with `NottiPayloadKeys`; port its 6 tests.
**Where**: `Sources/NottiShared/NottiNotificationParsing.swift`, `Tests/NottiSharedTests/NottiNotificationParsingTests.swift`
**Depends on**: package-foundation done
**Reuses**: RN `ios/NottiNotificationParsing.swift` (98), `ios/Tests/NottiNotificationParsingTests.swift`
**Requirement**: CORE-01, CORE-06

**Done when**:

- [ ] Behavior unchanged; only access level and key constants differ from RN
- [ ] `scripts/check-extension-safety.sh` still passes
- [ ] Gate passes: quick `-only-testing:NottiSharedTests/NottiNotificationParsingTests`
- [ ] Test count: NottiSharedTests 11 (5 + 6)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(shared): port NottiNotificationParsing from RN`

---

### C2: Port `NottiDeviceStore` + golden key test

**What**: Port the store verbatim (`internal`), its 18 tests, and add `NottiDeviceStoreKeysTests`, which asserts the key constants equal a frozen list copied from RN.
**Where**: `Sources/NottiSDK/Storage/NottiDeviceStore.swift`, `Tests/NottiSDKTests/NottiDeviceStoreTests.swift`, `Tests/NottiSDKTests/NottiDeviceStoreKeysTests.swift`
**Depends on**: C1
**Reuses**: RN `ios/NottiDeviceStore.swift` (450; keys at :88-117), `ios/Tests/NottiDeviceStoreTests.swift`, RN README:532-560
**Requirement**: CORE-01, CORE-02, CORE-06, CORE-09

**Done when**:

- [ ] Every key string and value encoding identical to RN
- [ ] Golden test covers every key, including `notti_session_last_seen_at_ms` and `notti_profile_field_ack_migrated`
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiDeviceStoreTests -only-testing:NottiSDKTests/NottiDeviceStoreKeysTests`
- [ ] Test count: +19 (18 ported + 1 golden)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(storage): port NottiDeviceStore with frozen key test`

---

### C3: Port `NottiEventStore`

**What**: Port the store verbatim and its 6 tests; add a `.warn` log when `notti_pending_events` fails to decode (the queue is still dropped, as in RN), plus 1 test for it.
**Where**: `Sources/NottiSDK/Storage/NottiEventStore.swift`, `Tests/NottiSDKTests/NottiEventStoreTests.swift`
**Depends on**: C2
**Reuses**: RN `ios/NottiEventStore.swift` (138; key at :61), `ios/Tests/NottiEventStoreTests.swift`
**Requirement**: CORE-01, CORE-06, CORE-09, edge case "corrupt queue"

**Done when**:

- [ ] `PendingEvent` Codable field names unchanged
- [ ] New test: corrupt data → empty queue, no crash, one `.warn` reaches `NottiLogger.sink`
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiEventStoreTests`
- [ ] Test count: +7 (6 + 1)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(storage): port NottiEventStore and log corrupt-queue drops`

---

### C4: Port `NottiEventBuffer` without the static

**What**: Port the buffer verbatim minus `static let shared`; port its 12 tests to instances.
**Where**: `Sources/NottiSDK/Events/NottiEventBuffer.swift`, `Tests/NottiSDKTests/NottiEventBufferTests.swift`
**Depends on**: C3
**Reuses**: RN `ios/NottiEventBuffer.swift` (141), `ios/Tests/NottiEventBufferTests.swift`
**Requirement**: CORE-01, CORE-03, CORE-06

**Done when**:

- [ ] No `shared` member; no other diff against RN except access level
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiEventBufferTests`
- [ ] Test count: +12

**Tests**: unit
**Gate**: quick
**Commit**: `feat(events): port NottiEventBuffer as an owned instance`

---

### C5: Port `NottiApiClient` + `StubURLProtocol`

**What**: Port the client verbatim and its 29 tests, plus `StubURLProtocol` into test support. Error logs use `"\(error.domain)#\(error.code)"` instead of `localizedDescription` (NottiApiClient:248-289); add 1 test asserting a `URLError` log line contains no URL.
**Where**: `Sources/NottiSDK/Network/NottiApiClient.swift`, `Tests/NottiSDKTests/NottiApiClientTests.swift`, `Tests/NottiSDKTests/Support/StubURLProtocol.swift`
**Depends on**: C4
**Reuses**: RN `ios/NottiApiClient.swift` (405), `ios/Tests/NottiApiClientTests.swift`, `ios/Tests/StubURLProtocol.swift`
**Requirement**: CORE-01, CORE-02, CORE-06, CORE-12; edge case "http rejected in release"

**Done when**:

- [ ] Endpoints, headers (`Authorization: Bearer`), retry (5 attempts, 2/4/8/16s; 408/429/5xx transient) unchanged
- [ ] Only logging lines differ from RN besides access level
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiApiClientTests`
- [ ] Test count: +30 (29 + 1)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(network): port NottiApiClient and log errors as domain#code`

---

### C6: Port `NottiNetworkObserver` without the static

**What**: Port the observer minus `static let shared`; the "network available" callback is injected (the runtime wires it in C9). Port its 4 tests and add `FakePathMonitor` to test support if RN had it inline.
**Where**: `Sources/NottiSDK/Network/NottiNetworkObserver.swift`, `Tests/NottiSDKTests/NottiNetworkObserverTests.swift`, `Tests/NottiSDKTests/Support/FakePathMonitor.swift`
**Depends on**: C5
**Reuses**: RN `ios/NottiNetworkObserver.swift` (116; static at :58-59), `ios/Tests/NottiNetworkObserverTests.swift`
**Requirement**: CORE-01, CORE-02, CORE-03, CORE-06

**Done when**:

- [ ] No reference to `NottiImpl` or any global; callback injected
- [ ] Gate passes: quick `-only-testing:NottiSDKTests/NottiNetworkObserverTests`
- [ ] Test count: +4

**Tests**: unit
**Gate**: quick
**Commit**: `feat(network): port NottiNetworkObserver with an injected callback`

---

### C7: Port `NottiCore`

**What**: Port `NottiCore.swift` verbatim, change `logger: (String) -> Void` to `logger: (NottiLogLevel, String) -> Void` and give each of the 24 call sites a level (failure/give-up `.error`, retry/degraded `.warn`, lifecycle `.debug`; message text unchanged). Port the 123 tests and the core test doubles (`ThreadProbeApiClient`, `PatchHookApiClient`, `SlowEventApiClient`) to `Support/`.
**Where**: `Sources/NottiSDK/Core/NottiCore.swift`, `Tests/NottiSDKTests/NottiCoreTests.swift`, `Tests/NottiSDKTests/Support/*.swift`
**Depends on**: C2, C3, C5, C6
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

### C8: `NottiPlatformProviders`, location reader, background task

**What**: Move the provider closures from `NottiImpl.init` (:108-233) into `NottiPlatformProviders` with `static func live()` marked `@available(iOSApplicationExtension, unavailable)`; port `NottiLocationReader` (:389-462) and `NottiBackgroundTask` (:274-302). Unit-test the pure parts (e.g. hex/locale/timezone formatting, if any are pure); OS-backed closures are build-verified.
**Where**: `Sources/NottiSDK/Platform/NottiPlatformProviders.swift`, `Sources/NottiSDK/Platform/NottiLocationReader.swift`, `Sources/NottiSDK/Platform/NottiBackgroundTask.swift`, `Tests/NottiSDKTests/NottiPlatformProvidersTests.swift` (only if a pure helper exists)
**Depends on**: C7
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

### C9: `NottiRuntime`

**What**: The container per design: `shared`, injectable `init`, `eventStore`/`eventBuffer`/`sessionGate`, lock-protected `core`, `start` (invalidate old core first; `sdkVersion: NottiSDKVersion.current`), `stop`, `onDeviceIdChanged`, `onNetworkAvailable`, `onApnsToken` (hex), `onApnsRegistrationFailed`, `sanitizeTags` (from NottiImpl:325-341), background observer and network observer started in `init`.
**Where**: `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiRuntimeTests.swift`
**Depends on**: C8
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

### C10: `NottiNotificationHandler`

**What**: Plain-input handler split from `NottiPushDelegate` (:51-138): `handleWillPresent(userInfo:identifier:)`, `handleResponse(actionIdentifier:userInfo:identifier:)`, `enqueueIfReportable` (requires `notification_id` + `delivery_id`, persists to `runtime.eventStore`, calls `runtime.core?.onNetworkAvailable()`). Rewrite the logic assertions of the 15 `NottiPushDelegateTests` against plain inputs.
**Where**: `Sources/NottiSDK/Events/NottiNotificationHandler.swift`, `Tests/NottiSDKTests/NottiNotificationHandlerTests.swift`
**Depends on**: C9, C4
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

### C11: No-PII-in-logs flow test

**What**: One test that runs initialize → token → register → login(sentinel) → setEmail(sentinel) → setPhone(sentinel) → addTags(sentinel) → event flush with injected failures, at `.verbose`, capturing `NottiLogger.sink`, and asserts no sentinel (including the token hex) appears. A second test asserts the default level is `.error` and nothing below it is emitted.
**Where**: `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift`
**Depends on**: C10
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

### C12: RN 0.6.0 continuity fixture

**What**: Hand-author `rn-0.6.0-state.plist` from RN key/encoding definitions with synthetic values (device id, token, tags, external id, subscribed, profile fields + acks + `notti_profile_field_ack_migrated`, session counters + `notti_session_last_seen_at_ms`, two pending events written by hand from `PendingEvent` field names). Add `.copy("Fixtures")` to the test target and a test that loads it into a per-test suite and starts the runtime.
**Where**: `Tests/NottiSDKTests/Fixtures/rn-0.6.0-state.plist`, `Package.swift` (test resources), `Tests/NottiSDKTests/NottiContinuityTests.swift`
**Depends on**: C9
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

### C13: Traceability and parity proof

**What**: Write `traceability.md` mapping every iOS-applicable RN ID (SDK-, SDKCTR-, SDKOPEN-, SEGTEL-, DPF-) to test names here, with N/A rows and reasons (Android-only, `public-api`, `delegate-integration`, `example-and-release`), the RN → here test count table, and the list of renamed/moved/dropped tests. Run the full gate and the RN-symbol grep.
**Where**: `.specs/features/core-port/traceability.md`, `.specs/features/core-port/spec.md` (status column)
**Depends on**: C11, C12
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
| C1–C6 | 1 ported file + its test file (+ 1 test helper in C5/C6) | ✅ |
| C7 | 1 ported file + its test file + test doubles | ⚠️ OK: verbatim port; splitting the file is deferred by design |
| C8 | 3 small files from one RN source (`NottiImpl`) | ⚠️ OK, cohesive (one RN origin, no logic change) |
| C9 | 1 type + tests | ✅ |
| C10 | 1 type + tests | ✅ |
| C11 | 1 test file | ✅ |
| C12 | 1 fixture + 1 test + 1 manifest line | ✅ |
| C13 | 1 doc | ✅ |

## Diagram-Definition Cross-Check

| Task | Depends on (body) | Diagram shows | Status |
| --- | --- | --- | --- |
| C1 | package-foundation | entry | ✅ |
| C2 | C1 | C1 → C2 | ✅ |
| C3 | C2 | C2 → C3 | ✅ |
| C4 | C3 | C3 → C4 | ✅ |
| C5 | C4 | C4 → C5 | ✅ |
| C6 | C5 | C5 → C6 | ✅ |
| C7 | C2, C3, C5, C6 | C2, C3, C5, C6 → C7 | ✅ |
| C8 | C7 | C7 → C8 | ✅ |
| C9 | C8 | C8 → C9 | ✅ |
| C10 | C9, C4 | C9 → C10, C4 → C10 | ✅ |
| C11 | C10 | C10 → C11 | ✅ |
| C12 | C9 | C9 → C12 | ✅ |
| C13 | C11, C12 | C11, C12 → C13 | ✅ |

No `[P]` tasks (TESTING.md: not parallel-safe).

## Test Co-location Validation

| Task | Code layer | Matrix requires | Task says | Status |
| --- | --- | --- | --- | --- |
| C1 | `NottiShared` | unit | unit | ✅ |
| C2 | storage | unit | unit | ✅ |
| C3 | storage | unit | unit | ✅ |
| C4 | events | unit | unit | ✅ |
| C5 | network | unit | unit | ✅ |
| C6 | network | unit | unit | ✅ |
| C7 | core | unit | unit | ✅ |
| C8 | platform providers | build (+ unit for pure helpers) | build + unit | ✅ |
| C9 | runtime | unit | unit | ✅ |
| C10 | events | unit | unit | ✅ |
| C11 | tests only | unit | unit | ✅ |
| C12 | tests + fixture | unit | unit | ✅ |
| C13 | docs | none | none | ✅ |

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| CORE-01 | C1–C8 |
| CORE-02 | C2, C5, C6, C7, C8, C9 |
| CORE-03 | C4, C6, C9 |
| CORE-04 | C10 |
| CORE-05 | C9 |
| CORE-06 | C1–C7, C10, C13 |
| CORE-07 | C13 |
| CORE-08 | C9, C10, C13 |
| CORE-09 | C2, C3, C12 |
| CORE-10 | C12 |
| CORE-11 | C12 |
| CORE-12 | C5, C11 |
| CORE-13 | C11 |

13/13 mapped. Inherited RN IDs are mapped test-by-test in C13.

Expected `NottiSDKTests` total after C13: ≥ 2 (foundation) + 19 + 7 + 12 + 30 + 4 + 123 + 8 + 15 + 2 + 1 = ≥ 223. `NottiSharedTests`: 11.
