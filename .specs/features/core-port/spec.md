# Core Port Specification

## Problem Statement

All of Notti's iOS behavior (registration, identity, tags, profile fields, session telemetry, engagement events, retry and offline queue) lives in `zeep-notti-react-native/ios`. It is about 3.3k lines of mostly pure Swift, wired to the app through a Turbo Module shim and global statics (`NottiImpl.activeCore`, `NottiImpl.eventStore`). AD-001 makes this repo the single source of truth. The core has to move here unchanged in behavior, decoupled from React Native, with its XCTest suite, so that later features (`public-api`, `delegate-integration`) build on a proven engine and M2 can delete the RN copy.

## Goals

- [ ] Behavior parity: every iOS-applicable requirement from the RN specs (`SDK-`, `SDKCTR-`, `SDKOPEN-`, `SEGTEL-`, `DPF-`) is preserved, and each one has at least one passing XCTest in this repo that exercises the layer implementing it (L-001).
- [ ] Zero React Native symbols or concepts in the ported code (no `RCT*`, no Turbo Module, no `NSDictionary` bridging shell, no JS lifecycle assumptions in the core API).
- [ ] On-device continuity: the same UserDefaults suite and keys as RN 0.6.0, so an app moving from `react-native-notti` 0.6.0 to a build on this SDK keeps its device id, tags, session counters, pending queue and acks.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Public Swift/ObjC facade (`Notti.initialize`, `Notti.User`, listeners) | `public-api`. This feature exposes an internal (`@testable`) core API only |
| APNs token capture / `UNUserNotificationCenterDelegate` wiring (swizzling or manual) | `delegate-integration`. This feature ports the core's entry points (`onTokenRefreshed`, notification handling functions), not who calls them |
| NSE rich media | `nse-rich-media` |
| Any behavior change (Retry-After, queue TTL, Keychain, consent, App Group) | AD-002: parity only; M3 |
| Backend contract changes | Contract is fixed at `zeep-notti` >= v0.11.0 |
| Swift 6 concurrency rewrite | Only if Design chooses Swift 6 mode. A port must not silently change threading semantics |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Source of truth for behavior | RN `main` at release `v0.6.0` (`35823eb`) plus the commits after it (docs only) | Last released, device-validated state | y |
| Requirement IDs | Reuse the RN IDs as the behavior spec. This spec adds only `CORE-` IDs for port-specific concerns | AD-002. Avoids re-specifying 80+ behaviors | y |
| Global statics | Replaced by an SDK-owned container (one per process) that the delegate/NSE-facing entry points reach. Cold-start safety is preserved (an event that arrives before `initialize` is still persisted) | Statics are the main RN coupling the explore pass found | n - shape decided in Design |
| `NottiEventBuffer` (pre-listener buffer) | Ported as is; its JS-lifecycle naming is adapted in `public-api` | Listener semantics belong to the facade | y |
| Threading | Keep the serial `workQueue` + bounded semaphore HTTP client (Swift 5 mode in M1) | Port, not rewrite | y (Julio, 2026-10-09) |
| Location (country) | Ported, still opt-in and off by default | Parity (SEGTEL-10..15) | y |
| Logging | RN logs via `NSLog`/`print` (to be confirmed in Design). The port routes through one internal logger with no PII; level control is exposed in `public-api` | LGPD constraint in PROJECT.md | n - Design |

Open questions: none (the two `n - Design` rows were resolved in `design.md`, approved 2026-10-09).

---

## User Stories

### P1: Core engine runs without React Native ⭐ MVP

**User Story**: As the SDK maintainer, I want the Notti core to compile and run inside `NottiSDK` with no RN dependency, so that native apps and future wrappers share one engine.

**Why P1**: Everything else in M1 depends on it.

**Acceptance Criteria**:

1. WHEN `NottiSDK` is built THEN it SHALL contain the ported `NottiCore`, `NottiApiClient`, `NottiDeviceStore`, `NottiEventStore`, `NottiEventBuffer`, `NottiNetworkObserver`, `NottiNotificationParsing` and the concrete provider wiring from `NottiImpl` (token, permission, device info, location reader, background task), and SHALL NOT reference any `RCT*`/React symbol.
2. WHEN the core is constructed THEN all of its dependencies (HTTP session, sleeper, UserDefaults suite, path monitor, providers) SHALL be injectable, the same as in RN, so that tests run hostless.
3. WHEN code outside the core (delegate entry points, network observer) needs the active core or the event store THEN it SHALL reach them through the SDK-owned container, not through mutable global statics scattered across types.
4. WHEN a notification event (received/opened/clicked) is handled before the core is initialized THEN the event SHALL be persisted to the event store and flushed after registration, as RN does today (SDKCTR-02, SDKCTR-12).
5. WHEN `sdk_version` is sent THEN its value SHALL come from the native version constant (PKG-14), never from a caller parameter. An empty or unavailable value SHALL omit the field, as RN does today.

**Independent Test**: The `NottiSDK` unit-test target builds and runs hostless, and `grep -r "RCT\|React" Sources/` is empty.

---

### P1: Behavior parity proven by tests ⭐ MVP

**User Story**: As the maintainer, I want the RN XCTest suite ported and green, so that I can prove the port changed no behavior.

**Why P1**: Parity is the definition of done for M1 (AD-002).

**Acceptance Criteria**:

1. WHEN the ported test suite runs THEN every RN iOS test that targets a ported component SHALL exist here (renamed only where RN-specific) and pass. The count SHALL be at least the RN iOS count for the same files (Core 123, ApiClient 29, DeviceStore 18, PushDelegate core-logic portion, EventBuffer 12, EventStore 6, Parsing 6, NetworkObserver 4). Tests dropped as RN-only SHALL be listed with a reason.
2. WHEN the traceability table is complete THEN every iOS-applicable RN requirement ID SHALL map to at least one test in this repo (Android-only IDs such as SDK-11 are marked N/A with a reason).
3. WHEN an RN requirement was flagged on iOS as "indirect evidence only" or "Needs Fix" (SDK-04, SDK-12, SDK-13, SDK-17) THEN this port SHALL add a direct test for its core-layer portion, or record why it belongs to `delegate-integration`/`public-api`.

**Independent Test**: CI runs the suite. A traceability script/table lists RN ID → test name with no gaps.

---

### P1: On-device continuity with RN 0.6.0 ⭐ MVP

**User Story**: As an app team migrating from `react-native-notti` 0.6.0 (or, in M2, upgrading RN onto this SDK), I want the device's persisted Notti state preserved, so that users are not duplicated as new devices and pending events are not lost.

**Why P1**: Without it, M2 creates duplicate device rows for every user and breaks session/CTR analytics.

**Acceptance Criteria**:

1. WHEN the core reads or writes persisted state THEN it SHALL use the UserDefaults suite `notti_prefs` and exactly the RN 0.6.0 key names and value encodings (`NottiDeviceStore` keys, `notti_pending_events` Codable format, session keys such as `notti_session_last_seen_at_ms`, `notti_profile_field_ack_migrated`).
2. WHEN a UserDefaults suite pre-populated with RN 0.6.0 state (device id, tags, session counters, pending events, profile acks) is loaded THEN the core SHALL start with that device id and SHALL NOT `POST` a new registration unless RN 0.6.0 would also have done so in that state.
3. WHEN a fixture of RN 0.6.0 persisted state is checked in (synthetic values only, no real PII) THEN a test SHALL load it and assert the above.

**Independent Test**: The fixture-based test passes. Manually: install the RN example at 0.6.0, register, then install a native build with the same bundle id; the backend shows the same device id.

---

### P2: No PII in logs

**User Story**: As a privacy-conscious integrator (LGPD), I want the SDK's logs never to contain email, phone, push token, country or external user id values, so that device logs and crash reports don't leak personal data.

**Why P2**: The RN README already claims this posture. The port must not regress it, and the new single logger makes it enforceable.

**Acceptance Criteria**:

1. WHEN the core logs anything THEN it SHALL go through one internal logger. Values of `email`, `phone`, `token`, `external_user_id`, `country` and tag values SHALL never be interpolated into log messages.
2. WHEN the logger is in its default release configuration THEN it SHALL emit only errors (final level API in `public-api`).

**Independent Test**: A test captures logger output across a full register → login → setEmail → event-flush flow with sentinel values, and asserts that no sentinel appears.

---

## Edge Cases

- WHEN the UserDefaults suite has partial or corrupt RN state (e.g. undecodable `notti_pending_events`) THEN the core SHALL behave as RN 0.6.0 does (verify in Design: drop the corrupt queue, no crash).
- WHEN `initialize` runs twice in one process THEN the behavior SHALL match RN's process session gate and core adoption (SEGTEL-08 notes: adopt the open session, `session_count` unchanged).
- WHEN the network is unavailable at init THEN the registration retry and network-triggered flush SHALL behave as SDK-05/06 and SDKCTR-13.
- WHEN the baseUrl is `http://` in a release build THEN it SHALL be rejected, as RN does (http only in DEBUG).

---

## Requirement Traceability

Port-specific requirements:

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| CORE-01 | P1: Core without RN (components ported, no RN symbols) | Specify | In progress |
| CORE-02 | P1: Core without RN (all deps injectable) | Specify | In progress |
| CORE-03 | P1: Core without RN (container replaces statics) | Specify | In progress |
| CORE-04 | P1: Core without RN (pre-init events persisted) | Specify | Pending |
| CORE-05 | P1: Core without RN (native sdk_version) | Specify | Pending |
| CORE-06 | P1: Parity tests (suite ported, counts, drop list) | Specify | In progress |
| CORE-07 | P1: Parity tests (every iOS RN ID → test) | Specify | Pending |
| CORE-08 | P1: Parity tests (close SDK-04/12/13/17 core-layer gaps) | Specify | Pending |
| CORE-09 | P1: Continuity (same suite/keys/encodings) | Specify | In progress |
| CORE-10 | P1: Continuity (no re-register on migrated state) | Specify | Pending |
| CORE-11 | P1: Continuity (fixture test) | Specify | Pending |
| CORE-12 | P2: No PII in logs (single logger, no PII values) | Specify | In progress |
| CORE-13 | P2: No PII in logs (errors-only default) | Specify | Pending |

Inherited behavior requirements (verified through CORE-07; detailed mapping is built in Tasks):

- `sdk-core-v1` (SDK-01..19): All except Android-only (e.g. SDK-11 POST_NOTIFICATIONS/API 33). Listener/emitter IDs (SDK-17..19) are split: core part here, facade part in `public-api`
- `ctr-event-reporting` (SDKCTR-01..14): All. Delegate-entry wiring is verified again in `delegate-integration`
- `opened-event-reporting` (SDKOPEN-01..10): All except SDKOPEN-10 (JS events) → `public-api`; SDKOPEN-11 (docs) → `example-and-release`
- `segment-telemetry-reporting` (SEGTEL-01..15): All (iOS variants: 24h orphan cap, `notti_session_last_seen_at_ms`, telemetry counted/evicted first in the 32 cap)
- `device-profile-fields` (DPF-01..21): All. DPF-17..21 email/phone core logic here; JS-surface wording → `public-api`

**Coverage:** 13 port requirements, 13 mapped to tasks (see `tasks.md`). About 78 inherited IDs, mapped test-by-test in task T13 (`traceability.md`).

---

## Success Criteria

- [ ] The `NottiSDK` test target runs the ported suite green in CI, with test count >= the RN iOS count for ported files (minus the listed RN-only drops).
- [ ] The traceability table shows no unmapped iOS-applicable RN ID.
- [ ] The RN 0.6.0 state fixture test passes (no duplicate registration).
- [ ] No RN symbols in `Sources/`.
