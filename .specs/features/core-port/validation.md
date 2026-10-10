# Validation: core-port - PASS ✅ (round 2)

**Date**: 2026-10-10 (round 2; round 1 the same day)
**Spec**: `.specs/features/core-port/spec.md`
**Diff range**: round 2 re-verifies `main` (`437b826`) `..4303e49` on `feat/core-port`. Round-1 fix commit: `2643c4d..4303e49`.
**Verifier**: independent sub-agents (author ≠ verifier). Round 2 was run by a different agent from round 1, which wrote neither the code nor the round-1 report.
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, CocoaPods (local), SwiftLint 0.65.1 (Docker). RN baseline `../zeep-notti-react-native` at `52e4b55`.

**Verdict (round 2)**: PASS. All three round-1 gaps are closed: R1, L4, L6 and G2 are killed again, and so are 8 variants of them. The fix commit changes only the suite-name constant in `Sources`. 31 round-2 mutants: 25 killed, 6 survived. None of the 6 is blocking (each is classified below). All gates are green, and CI on PR #3 (head `4303e49`) is green. See [Round 2](#round-2) at the end. The round-1 report below is kept unchanged as a record. Its only edit is the sensor-result label, renamed so that the verdict parser reads round 2's verdict.

<details><summary>Round 1 header (FAIL)</summary>

Round 1 verdict: FAIL ❌

**Date**: 2026-10-10
**Spec**: `.specs/features/core-port/spec.md`
**Diff range**: `main` (`437b826`) `..b3b7e18` on `feat/core-port` (13 commits, `5c47368..b3b7e18`; 38 files, +9351/-87). Code surface: `Sources/NottiShared/NottiNotificationParsing.swift`, `Sources/NottiSDK/{Core,Events,Network,Platform,Runtime,Storage}/*`, `Tests/NottiSDKTests/**`, `Tests/NottiSharedTests/{NottiNotificationParsingTests,NottiLoggerTests}.swift`, `Package.swift` (test resources).
**Verifier**: independent sub-agent (author ≠ verifier), round 1
**Environment**: Xcode 27.0 (27A266a), simulator `iPhone 17 Pro`, CocoaPods (local), SwiftLint 0.65.1 (Docker). RN baseline `../zeep-notti-react-native` at `52e4b55`, files extracted with `git show 52e4b55:ios/<file>`.

**Verdict**: FAIL. Three surviving mutants in the scope of CORE ACs (CORE-09, CORE-12, CORE-13). The code itself has no defect and is a faithful port: every gap is a test that does not detect a regression. All fixes are small test additions (one also adds a constant). Everything else passes.


</details>

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | `diff -w` vs RN: only `public`→`package`, `NottiPayloadKeys` constants (same strings), provenance header. 6/6 RN tests, same names. |
| T2 | ✅ Done | Store `diff -w` identical except access level. 18/18 + golden test. S1 and S5 killed. |
| T3 | ✅ Done | Only change: the `guard` is split so a decode failure logs `.warn` (missing data does not log). Still returns `[]`, as in RN. 6/6 + 1. S2, S3, S4 killed. |
| T4 | ✅ Done | Only `static let shared` removed. 12/12. B1 killed. |
| T5 | ✅ Done | Only `lastError` = `domain#code` (`NottiApiClient.swift:260-263`). `permanentClientErrorStatus` needs the `"HTTP "` prefix, so the 401/403/404 detection is unchanged. 29/29 + 1. A1-A6 killed. |
| T6 | ✅ Done | Only `static let shared` and its `NottiImpl.activeCore` callback removed. 4/4. N1 killed. |
| T7 | ✅ Done | Normalized `diff -w` (access modifiers and AD-007 headers stripped): 24 `logger(` sites with identical text (checked one by one), logger signature, 2× `[self]` (SPEC_DEVIATION). No other line differs. 123/123: the only test diff is `logger: { _, message in … }`. C1, C2 killed. |
| T8 | ✅ Done | `NottiLocationReader` and `NottiBackgroundTask` bodies match RN under `diff -w` (only the access level, the `@available(iOSApplicationExtension, unavailable)` attribute and the type/func name change). Provider closures are verbatim, apart from the 2 SPEC_DEVIATIONs. Build-only. |
| T9 | ✅ Done | 13 tests. R2-R7 killed. **R1 survived** (Gap 1). |
| T10 | ✅ Done | The handler matches RN `NottiPushDelegate.swift:52-138` decision for decision. All 15 RN tests ported (2 renames) + 4 new. H1-H6 killed. |
| T11 | ⚠️ Partial | 2 tests + 1 logger test. L1, L2, L3, L5, G1 killed. **L4 and G2 survived** (Gaps 2 and 3). |
| T12 | ✅ Done | The fixture matches RN key names and encodings (`NottiDeviceStore.swift:88-117` RN, NSNumber ints, dictionary tags, `PendingEvent` JSON with `id/notificationId/deliveryId/type/createdAtMs`, decoded from the plist). 2 tests. |
| T13 | ✅ Done | All 173 test references in `traceability.md` exist as `func test_…()` (checked mechanically). `grep -rnE "RCT\|React" Sources/` is empty (rc 1). |

---

## Spec-Anchored Acceptance Criteria

| ID | Criterion | Spec-defined outcome | Evidence (`file:line` + assertion / command) | Status |
| --- | --- | --- | --- | --- |
| CORE-01 | `NottiSDK` contains the ported components and no RN symbol | 7 components + provider wiring; no `RCT*`/React | Files present (`Sources/NottiSDK/**`, `Sources/NottiShared/NottiNotificationParsing.swift`); `grep -rnE "RCT\|React" Sources/` → no match (rc 1); full build + `pod lib lint` rc 0 | ✅ PASS |
| CORE-02 | All deps injectable | session, sleeper, defaults, path monitor, providers | `NottiRuntime.swift:50-59` (`defaults`, `providers`, `pathMonitor`, `apiClientFactory` carries session + sleeper); `NottiRuntimeTests.swift:63-72` builds a hostless runtime with a `StubURLProtocol` session and a no-op sleeper | ✅ PASS |
| CORE-03 | Container, not scattered statics | `NottiRuntime` owns core/store/buffer/gate/observers | `grep "static var\|static let shared" Sources/` → only `NottiRuntime.shared`, the logger's lock-guarded level/sink, and computed `bundle`/`version`. `NottiRuntimeTests.swift:157` `XCTAssertEqual(backgroundTasks.value, 1, …)` (R2 killed), `:275` `XCTAssertFalse(runtime.sessionGate.isOpen)` (R3 killed), `:263` reconnect flush path (R7 killed) | ✅ PASS |
| CORE-04 | Pre-init event persisted, flushed after registration | Persisted with no core; flushed with its original ids after registration | `NottiNotificationHandlerTests.swift:297` `XCTAssertEqual(runtime.eventStore.all().map(\.type), ["opened", "clicked"])`; `:298` no request; `:307-310` 2 event POSTs, `delivery_id` `["d-1","d-1"]`, store empty | ✅ PASS |
| CORE-05 | `sdk_version` from the native constant; empty value omits the field | `== NottiSDKVersion.current`; field absent when empty | `NottiRuntimeTests.swift:108` `XCTAssertEqual(patches.compactMap { $0["sdk_version"] as? String }, [NottiSDKVersion.current])`; `:119` `allSatisfy { $0["sdk_version"] == nil }`. R6 (`"0.6.0"` hard-coded) killed | ✅ PASS |
| CORE-06 | RN tests ported; counts ≥ RN; drops listed | Core 123, Api 29, DS 18, EB 12, ES 6, Parse 6, NO 4, PushDelegate 15 | Executed counts (`xcodebuild test`): Core 123, Api 30, DS 18 (+1 Keys), EB 12, ES 7, Parse 6, NO 4, Handler 19. `comm` of RN vs ported `func test_` names: no RN name missing except the 2 renames listed in `traceability.md` §4. Dropped: none | ✅ PASS |
| CORE-07 | Every iOS-applicable RN ID maps to a test | 78/80 mapped; N/A reasons | `traceability.md` §1. Every cited test exists. Mapping spot-checked against the RN spec tables at `52e4b55` (SEGTEL-01..15, DPF-01..21): each row cites a test for that behavior | ✅ PASS (notes N3, N4) |
| CORE-08 | Direct tests for SDK-04/12/13/17 | A direct core-layer test, or a recorded move | SDK-04: `NottiRuntimeTests.swift:219` exact `"…fixture.apns#3000"`, `:221` no request, `:226` later registration works (R5 killed). SDK-12: `:321` full merged map. SDK-13: `:338` `["lang": "pt"]`. SDK-17: `NottiNotificationHandlerTests.swift:264-270` (H5 killed) | ✅ PASS |
| CORE-09 | Suite `notti_prefs` + RN keys and encodings | Exactly RN names and encodings | Keys: `NottiDeviceStoreKeysTests.swift:99,103-105` (S1, S5 killed); `notti_pending_events`: `NottiEventStoreTests.swift:127`, continuity fixture (S2 killed). **Suite name: no test.** `NottiRuntime.swift:21` `UserDefaults(suiteName: "notti_prefs")` can be renamed with the full suite green (R1 survived, 233/233) | ❌ GAP (Gap 1) |
| CORE-10 | No re-register on migrated state unless RN would | No `POST /devices` without a token; same id | `NottiContinuityTests.swift:118` `XCTAssertTrue(requests(pathSuffix: "/devices").isEmpty, …)`; `:119` id; `:121` PATCH addressed to the RN id; `:167-170` same-token upsert: one POST, same id, no change event | ✅ PASS |
| CORE-11 | Fixture test with synthetic values | Fixture loaded; above asserted | `Tests/NottiSDKTests/Fixtures/rn-0.6.0-state.plist` (values `*-fixture`, `example.invalid`, `ZZ`); `Package.swift` `resources: [.copy("Fixtures")]`; `NottiContinuityTests.swift:40-53` loads it; events decoded from the plist by hand (not by the ported encoder) | ✅ PASS |
| CORE-12 | One logger; no email/phone/token/external id/country/tag value in logs | No sentinel in any log line | `NottiLoggingPrivacyTests.swift:134-142` sentinel scan; `NottiApiClientTests.swift:219` exact `domain#code` (A5 killed); L1 (email/phone), L2 (tags), L3 (country), R5 killed. **L4 survived**: `\(token)` appended to `NottiCore.swift:725` (`device registration failed`) passes all 125 tests, because no sentinel test drives a failed registration | ❌ GAP (Gap 2) |
| CORE-13 | Default config emits errors only | Only `.error` at default | `NottiLoggingPrivacyTests.swift:160` `XCTAssertEqual(captured.map(\.level), [.error])` after `NottiLogger.level = NottiLogger.defaultLevel` (`:149`); `NottiLoggerTests.swift:22` `defaultLevel == .error` (G1 killed). **G2 survived**: with `_level` initialised to `.verbose` (`NottiLogger.swift:41`) all 233 + 13 tests pass, because every test sets the level explicitly before asserting | ❌ GAP (Gap 3) |

**Status**: ❌ 10/13 ACs covered with discriminating tests; 3 gaps (CORE-09, CORE-12, CORE-13). No spec-precision gap.

### Edge cases

- [x] Corrupt `notti_pending_events`: dropped, no crash, one `.warn` (`NottiEventStoreTests.swift:127-132`; S4 killed). Same as RN, which also drops the queue.
- [x] `initialize` twice: core layer `NottiCoreTests.swift:280` (SDK-07). Runtime `start` twice adopts the open session (`NottiRuntimeTests.swift:151-152`). See note N1 on `start` vs SDK-07.
- [x] Network unavailable at init: registration retry and reconnect flush (`NottiRuntimeTests.swift:244-265`; `NottiCoreTests` SDK-05).
- [~] `http://` rejected in release: code unchanged from RN (`NottiApiClient.swift:68-74`, `#if DEBUG`). Not testable in a DEBUG test build. Note N5.

---

## Port fidelity (`diff -w`, access modifiers and AD-007 headers normalized)

| Ported file | Non-listed diff lines | Result |
| --- | --- | --- |
| `NottiNotificationParsing.swift` | none (keys → `NottiPayloadKeys`, same strings, listed) | ✅ |
| `NottiDeviceStore.swift` | none | ✅ |
| `NottiEventStore.swift` | `guard` split for the listed `.warn` (behavior unchanged: missing → `[]` silent, undecodable → `[]` + warn) | ✅ |
| `NottiEventBuffer.swift` | none (`shared` removed, listed) | ✅ |
| `NottiNetworkObserver.swift` | none (`shared` removed, listed) | ✅ |
| `NottiApiClient.swift` | none (`domain#code`, listed) | ✅ |
| `NottiCore.swift` | none beyond the logger signature, 24 levels (text identical) and 2× `[self]` | ✅ |
| `NottiLocationReader` / `NottiBackgroundTask` (from `NottiImpl`) | none (access level, attribute, name) | ✅ |
| `NottiPlatformProviders.live()` (from `NottiImpl.init`) | 1 comment wording, `case .ephemeral: status = nil` | ✅ (SPEC_DEVIATION) |
| `NottiNotificationHandler` (from `NottiPushDelegate`) | none in the decisions; plain inputs and the runtime instead of statics (designed) | ✅ |
| Tests (Parsing, DS, ES, EB, NO, Api, StubURLProtocol, Core) | only `@testable import`, helpers moved to `Support/` unchanged, the logger closure arity, and the 2 listed added tests | ✅ |

**SPEC_DEVIATIONs re-checked**: (1) `[self]` at `NottiCore.swift:390,800`: the enclosing scope already holds a strong `self` (`guard let self`/method scope), and RN captures it implicitly the same way. Behavior-neutral. (2) `.ephemeral` → nil at `NottiPlatformProviders.swift:143`: RN fell through `@unknown default` to nil. Same value. (3) Comment wording only. All three are behavior-neutral.

**Flagged points**:
- `NottiApiClientTimeoutError` (`NottiApiClient.swift:43-45`): the message text changes from "Notti API request timed out" to the bridged `domain#code`. It is a logging-only change, has no PII, and does not affect `permanentClientErrorStatus`. Its `errorDescription` is now unused. Note N6.
- `NottiRuntime` locking: `lifecycleLock` serializes `start`/`stop`. `lock` guards `_core`/`_onDeviceIdChanged`. Invalidation happens outside `lock` (no callback runs under it). `deinit` reads `_core` without the lock, which is safe because no other reference exists then. The `[weak self]` network callback and the gate-only background observer avoid retain cycles. No defect.
- Continuity test 1 (orphan PATCH): the fixture's last heartbeat is 30 s after its start, which gives `session_time` +30 000 and count 7→8 (`NottiContinuityTests.swift:138-139`). This matches SEGTEL-08 iOS semantics in the verbatim core. C1 (close at `now`) is killed by this test.
- Continuity test 2 (same-token re-register re-sends email/phone): this is RN behavior (upsert on every token, DPF-19). CORE-10 allows a POST "when RN would also do so". Consistent.

---

## Discrimination Sensor

Scratch: `git worktree add --detach <scratchpad>/wt HEAD`, separate `-derivedDataPath`, one mutant at a time, `git checkout -- <file>` in the worktree after each (`clean_after: true` for all 37). The worktree was removed afterwards. Real tree `git status --porcelain` is empty before and after.

| # | File:line | Mutation | Result |
| --- | --- | --- | --- |
| A1 | `NottiApiClient.swift:62` | `maxAttempts` 5→4 | ✅ Killed (6 tests) |
| A2 | `:291` | backoff `delayMs *= 2`→`*= 3` | ✅ Killed (12) |
| A3 | `:324` | 429 no longer transient | ✅ Killed (2) |
| A4 | `:277` | `< 500`→`<= 500` (500 terminal) | ✅ Killed (4) |
| A5 | `:263` | `domain#code`→`localizedDescription` | ✅ Killed |
| A6 | `:156,181,218` | `"Bearer \(key)"`→`"Bearer\(key)"` | ✅ Killed (2) |
| S1 | `NottiDeviceStore.swift` | `notti_session_last_seen_at_ms` renamed | ✅ Killed (golden) |
| S2 | `NottiEventStore.swift` | `notti_pending_events` renamed | ✅ Killed (ES + both CT) |
| S3 | `NottiEventStore.swift:68` | queue cap 32→33 | ✅ Killed |
| S4 | `NottiEventStore.swift` | corrupt-queue `.warn` removed | ✅ Killed |
| S5 | `NottiDeviceStore.swift` | `notti_profile_field_ack_migrated` renamed | ✅ Killed (golden + CT) |
| R1 | `NottiRuntime.swift:21` | suite `notti_prefs`→`notti_prefs_v2` | ❌ **Survived** (233 + 13 pass) |
| R2 | `NottiRuntime.swift:108` | `start` drops the old core without `invalidate()` | ✅ Killed |
| R3 | `NottiRuntime.swift:78` | background observer does not close the gate | ✅ Killed |
| R4 | `NottiRuntime.swift:129` | hex upper-case | ✅ Killed |
| R5 | `NottiRuntime.swift:137` | APNs failure logs `localizedDescription` | ✅ Killed |
| R6 | `NottiRuntime.swift:111` | `sdkVersion` hard-coded `"0.6.0"` | ✅ Killed |
| R7 | `NottiRuntime.swift:80` | network observer not started | ✅ Killed |
| H1 | `NottiNotificationHandler.swift:70` | body tap: `clicked` not enqueued | ✅ Killed (10) |
| H2 | `:79` | custom action also buffers a click | ✅ Killed |
| H3 | `:91` | empty `notification_id` accepted | ✅ Killed |
| H4 | `:97` | opportunistic flush removed | ✅ Killed |
| H5 | `:101` | every payload treated as remote | ✅ Killed (4) |
| H6 | `:45` | `received` → `opened` | ✅ Killed |
| P1 | `NottiNotificationParsing.swift` | prefix filter `hasPrefix`→`==` | ✅ Killed |
| B1 | `NottiEventBuffer.swift` | `takeInitialClick` does not consume | ✅ Killed |
| N1 | `NottiNetworkObserver.swift:106` | flush on every `.satisfied`, not only transitions | ✅ Killed |
| C1 | `NottiCore.swift:1154` | orphan closed at `now`, not the last heartbeat | ✅ Killed (Core + CT) |
| C2 | `NottiCore.swift:1346` | mutation cap `>=`→`>` | ✅ Killed |
| L1 | `NottiCore.swift:942` | email/phone value appended to the contact-PATCH failure log | ✅ Killed (LP) |
| L2 | `NottiCore.swift:599` | merged tag map appended to the tag-PATCH failure log | ✅ Killed (LP) |
| L3 | `NottiCore.swift:1238` | country appended to the country-PATCH failure log | ✅ Killed (LP) |
| L4 | `NottiCore.swift:725` | push `token` appended to the registration-failure log | ❌ **Survived** |
| L5 | `NottiCore.swift:1406` | "event stays queued" `.warn`→`.debug` | ✅ Killed (LP) |
| L6 | `NottiCore.swift:725` | registration failure `.error`→`.warn` | ❌ Survived (known; STATE todo: 21 levels review-only) |
| G1 | `NottiLogger.swift` | `defaultLevel` `.error`→`.warn` | ✅ Killed |
| G2 | `NottiLogger.swift:41` | initial `_level` = `.verbose` (constant untouched) | ❌ **Survived** (233 + 13 pass) |

**Sensor depth**: P0-full manual (37 mutants: retry/backoff, transient vs terminal, keys, queue cap/corrupt path, session gate/start-stop, click parsing, log redaction, continuity).
**Round-1 sensor outcome** - 33/37 killed. FAIL ❌ (R1, L4, G2 blocking; L6 non-blocking, already recorded).

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code | ✅ |
| Surgical changes (port = RN + listed changes only) | ✅ (normalized `diff -w` above) |
| No scope creep | ✅ |
| Matches patterns | ✅ |
| Spec-anchored outcome check | ⚠️ 3 ACs with a non-discriminating test |
| Per-layer coverage (TESTING.md matrix) | ✅ every layer has its test file; providers build-only, as designed |
| Every test maps to a requirement | ✅ (`traceability.md` §1-§3) |
| Guidelines followed: `AGENTS.md`, `.specs/codebase/TESTING.md`, AD-007, AD-008 | ✅ LGPD logging: no log interpolates a PII value (manual review of all 24 core sites, the 2 runtime sites and the event-store site; failure `message`s are `HTTP <code>`, `domain#code` or fixed text). Extension safety: `scripts/check-extension-safety.sh` rc 0, no forbidden API in `NottiShared`/`NottiSDKExtension`. App-only types carry `@available(iOSApplicationExtension, unavailable)`. Access: no `public`/`open` in `Sources/NottiSDK`; `NottiShared` uses `package`. Resources: no `Bundle.module` in `Sources/`. |

---

## Gate Check

- **Tests**: `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`, rc 0. `NottiSharedTests` 13, `NottiSDKTests` 233, `NottiSDKExtensionTests` 1 = **247**, 0 failures, 0 skipped.
- **Test count before feature** (`main`): 6 / 2 / 1 = 9. **After**: 13 / 233 / 1 = 247 (+238). RN parity floor met per file (CORE-06 row).
- **SwiftLint** `lint --strict`: `Found 0 violations, 0 serious in 42 files.` rc 0.
- **Scripts**: `version ok: 0.1.0`, `extension safety ok`, `package graph ok`, each rc 0.
- **`pod lib lint NottiSDK.podspec --platforms=ios`**: `NottiSDK passed validation.` rc 0. With `--subspec=Extension`: passed, rc 0.
- **Validators**: `validate_tasks.py` 0 errors (13 granularity warnings); `validate_spec.py` 0 errors, 0 warnings.
- **CI**: not run on this branch (no PR CI run was read).

---

## Fix Plans

### Fix 1 (Gap 1, CORE-09): the `notti_prefs` suite name is not guarded

- **Root cause**: `NottiRuntime.swift:21` hard-codes the suite inside `shared`, and no test references `"notti_prefs"` (`grep -rn notti_prefs Tests` → nothing). Every test uses its own suite, by design. A typo would orphan every migrated device's state: a new registration, a duplicate device row, and lost pending events. This is the exact failure CORE-09/10 exist to prevent.
- **Fix task**: add `static let defaultsSuiteName = "notti_prefs"` on `NottiRuntime` and use it in `shared`. Add one assertion (for example in `NottiDeviceStoreKeysTests`, next to the frozen key list) that `NottiRuntime.defaultsSuiteName == "notti_prefs"`.
- **Verify**: R1 (rename the literal) fails the new test.
- **Priority**: Major (blocking).

### Fix 2 (Gap 2, CORE-12): the registration-failure log site is not covered by the sentinel test

- **Root cause**: `test_fullFlowWithFailuresAtVerboseLogsNoSentinelValue` always registers successfully, so `NottiCore.swift:725` (`Notti.initialize: device registration failed: …`, where the raw `token` is in scope) never emits during a sentinel scan. Other unexercised sites with PII in scope are not covered either.
- **Fix task**: extend `NottiLoggingPrivacyTests` with a failing registration (for example a terminal 4xx and an exhausted 5xx for the POST) after `onApnsToken(tokenBytes)`, then run the same sentinel scan. Optionally also assert that the line is emitted at `.error` (this also kills L6 for that site).
- **Verify**: L4 (`\(token)` appended at `:725`) fails.
- **Priority**: Major (blocking).

### Fix 3 (Gap 3, CORE-13): the effective initial level is not asserted

- **Root cause**: tests check the `defaultLevel` constant and then set `NottiLogger.level = defaultLevel` themselves. So `private static var _level` (`NottiLogger.swift:41`) can start at any level unnoticed.
- **Fix task**: add a `NottiLoggerTests` test that reads `NottiLogger.level` without setting it and asserts `.error`. This is safe because every test restores the saved level in `tearDown`. Alternatively, assert in `setUp` before saving.
- **Verify**: G2 fails.
- **Priority**: Minor in size, but blocking (CORE-13 scope).

---

## Non-blocking notes

- **N1 (public-api)**: `NottiRuntime.start` always builds a new core (RN JS-reload semantics), so SDK-07's "repeat `initialize` with identical args is a no-op" holds only at the core layer (`NottiCoreTests.swift:280`). If `public-api` maps `Notti.initialize` to `start`, a second identical call would re-register and could re-prompt for the APNs token. `public-api` must call `core.initialize` on the live core (or compare the args) and test this at the facade.
- **N2**: L6, the other 21 `NottiCore` log levels, are review-only (already a STATE todo). Fix 2 can cover the registration-failure level cheaply.
- **N3**: SEGTEL-01 "read once at init", SEGTEL-15 ISO alpha-2 and DPF-01/06 OS reads are covered only by injected providers; the `live()` closures are build-only (STATE todo for `example-and-release`). Acceptable per the TESTING.md matrix.
- **N4**: SDKCTR-06 is mapped as a scope statement with no behavior test, which is reasonable because there is no code path.
- **N5**: The release-only `http` rejection (`#if DEBUG`) cannot be tested in a debug test build. RN has the same limitation. Consider a release-config build check post-M1.
- **N6**: `NottiApiClientTimeoutError.errorDescription` is now dead code (STATE todo exists).
- **N7 (LGPD, validate internally)**: the privacy manifest declares Email, Phone, CoarseLocation and ProductInteraction (AD-005). The ported core also sends `external_user_id` and a server device id linked to the user. Check whether `NSPrivacyCollectedDataTypeUserID` (and possibly Device ID) should be declared. This is a package-foundation/AD-005 decision rather than a core-port regression, so it needs internal/legal review, not a fix in this feature.
- **N8 (AD-008)**: ported tests keep non-reserved RN values (`a@b.com`, `+5511999999999`). They never leave the process and are never logged. A rename is already a post-M1 todo.
- **N9**: `Tests/NottiSDKTests/NottiContinuityTests.swift:41` uses `Bundle.module` in a test target (SPM only), which is fine because AGENTS.md's wrapper rule targets `Sources/`.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| CORE-01..08, CORE-10, CORE-11 | Implemented | ✅ Verified |
| CORE-09 | Implemented | ❌ Needs Fix (Fix 1) |
| CORE-12 | Implemented | ❌ Needs Fix (Fix 2) |
| CORE-13 | Implemented | ❌ Needs Fix (Fix 3) |

(`spec.md` is not edited by the Verifier. The implementer updates the statuses after the fixes and round 2.)

---

## Summary

**Overall**: ❌ Not Ready (3 small test gaps)

**Spec-anchored check**: 10/13 ACs matched with discriminating tests; 0 spec-precision gaps.
**Sensor**: 33/37 killed (R1, L4, G2 blocking; L6 known).
**Gate**: 247 passed, 0 failed; SwiftLint 0; 3 scripts ok; `pod lib lint` (full + Extension) passed.

**What works**: a faithful port (normalized `diff -w` clean apart from the listed changes); RN test parity per file, with all names kept; retry/backoff, transient/terminal, keys, queue cap and corrupt path, session gate, click handling and continuity all have killing tests; no PII interpolated in any log site; extension-safe.

**Next steps**: implement Fixes 1-3 (tests + one constant), then run the independent Verifier round 2.

---

## Round 2

**Date**: 2026-10-10 · **HEAD**: `4303e49` · **Verifier**: an independent sub-agent that is neither the implementer nor the round-1 Verifier.
**Verdict**: PASS ✅

### Fix commit scope (AD-002)

`git diff 2643c4d..4303e49 -- Sources` touches one file: `Sources/NottiSDK/Runtime/NottiRuntime.swift:18-27`. It adds `static let defaultsSuiteName = "notti_prefs"`, makes `shared` use `UserDefaults(suiteName: defaultsSuiteName)`, and rewords the doc comment. No ported file changed. The rest of the commit is tests (`NottiDeviceStoreKeysTests` +1, `NottiLoggingPrivacyTests` +2 with helpers, `NottiLoggerTests` +1) and specs.

### Gap closure

| Round-1 gap | AC | Fix evidence | Mutants re-applied (round 2) | Status |
| --- | --- | --- | --- | --- |
| Gap 1: suite name untested | CORE-09 | `Tests/NottiSDKTests/NottiDeviceStoreKeysTests.swift:112` `XCTAssertEqual(NottiRuntime.defaultsSuiteName, "notti_prefs")` | **R1** (constant → `notti_prefs_v2`): killed by `test_productionSuiteNameMatchesRN`. **R1b** (literal `"notti_prefs_v2"` written into `shared` with the constant intact) and **R1c** (`shared` uses `UserDefaults.standard`): survived on the full suite (236 + 14). See finding F1 | ✅ Closed (residual: F1, Note) |
| Gap 2: registration-failure log not sentinel-scanned | CORE-12 | `Tests/NottiSDKTests/NottiLoggingPrivacyTests.swift:147-163` (terminal 400 and 5×503): `:200` `XCTAssertEqual(failures.map(\.message), [expected])`, `:201` `XCTAssertEqual(failures.map(\.level), [.error])`, plus a sentinel scan over every captured line. Five POSTs asserted at `:161` | **L4** (`\(token)` appended at `NottiCore.swift:725`): killed by both new tests. **L4u** (`token.uppercased()`): killed. **L6** (`.error`→`.warn` at that site): killed. **L7** (new variant: `externalUserId` appended to the login-failure log, `NottiCore.swift:423`): killed by `test_fullFlowWithFailuresAtVerboseLogsNoSentinelValue` | ✅ Closed |
| Gap 3: initial effective level untested | CORE-13 | `Tests/NottiSharedTests/NottiLoggerTests.swift:25-26` `XCTAssertEqual(savedLevel, .error)`, `XCTAssertEqual(NottiLogger.level, .error)`. `savedLevel` is read in `setUp` without being assigned, and every test restores it in `tearDown`. If a test leaked a level, this check would fail rather than pass falsely | **G2** (`_level = .verbose`), **G2n** (`.none`), **G2w** (`.warn`): all killed by `test_initialEffectiveLevelIsError`. **G3** (`NottiRuntime.init` sets `NottiLogger.level = .verbose`): killed by `test_defaultLevelIsErrorAndNothingBelowItIsEmitted`. **G4** (`<=`→`<` in the level filter): killed | ✅ Closed |

### Spec-anchored ACs (round 2 delta)

CORE-09, CORE-12 and CORE-13 now have discriminating tests (evidence above). CORE-01..08, CORE-10 and CORE-11 were re-checked against HEAD:
- Port fidelity: normalized `diff -w` against RN `52e4b55`, with access modifiers and comments stripped. `NottiApiClient`: only `lastError` = `domain#code` (listed). `NottiNetworkObserver` / `NottiEventBuffer`: only `static let shared` removed. `NottiEventStore`: only the `guard` split for the `.warn`. `NottiDeviceStore`: whitespace only. `NottiCore`: the logger signature, 2× `[self]` (SPEC_DEVIATION) and 24 `logger(` sites, whose message strings are identical, compared mechanically. The round-1 table holds.
- `grep -rnE "RCT|React" Sources/` → no match.
- New mutants on CORE-03/04/10 paths (RT1-RT3, H7-H11, CT1) are killed (table below).

**Status**: ✅ 13/13 ACs covered with discriminating tests. No spec-precision gap.

### Discrimination sensor (round 2)

Scratch: `git worktree add --detach <scratchpad>/r2/wt HEAD`, separate `-derivedDataPath`, one mutant at a time, file restored after each (`clean_after: true` for all 31). The worktree was removed afterwards. Real-tree `git status --porcelain` is empty before and after. A mutant is reported as surviving only when the tests that exercise the mutated path ran. R1b, R1c and G2 ran the full SDK + Shared suites.

| # | File | Mutation | Tests run | Result |
| --- | --- | --- | --- | --- |
| R1 | `NottiRuntime.swift:20` | `defaultsSuiteName` → `notti_prefs_v2` | full (236 + 14) | ✅ Killed |
| R1b | `NottiRuntime.swift:25` | `shared` opens the literal `"notti_prefs_v2"` (constant intact) | full | ❌ Survived → F1 (Note) |
| R1c | `NottiRuntime.swift:25` | `shared` uses `UserDefaults.standard` | full | ❌ Survived → F1 (Note) |
| L4 | `NottiCore.swift:725` | `\(token)` appended to the registration-failure log | LP + Core | ✅ Killed (2) |
| L4u | `NottiCore.swift:725` | `token.uppercased()` appended | LP | ✅ Killed (2) |
| L6 | `NottiCore.swift:725` | `.error` → `.warn` | LP + Core | ✅ Killed (2) |
| L7 | `NottiCore.swift:423` | `externalUserId` appended to the login-failure log | LP | ✅ Killed |
| G2 | `NottiLogger.swift:41` | `_level = .verbose` | full | ✅ Killed |
| G2n | `NottiLogger.swift:41` | `_level = .none` | Shared | ✅ Killed |
| G2w | `NottiLogger.swift:41` | `_level = .warn` | Shared | ✅ Killed |
| G3 | `NottiRuntime.swift` `init` | runtime forces `NottiLogger.level = .verbose` | LP + RT | ✅ Killed |
| G4 | `NottiLogger.swift` `log` | level filter `<=` → `<` | Shared | ✅ Killed (2) |
| H7 | `NottiNotificationHandler.swift:74` | a dismiss reports `clicked` | NH | ✅ Killed (2) |
| H8 | `NottiNotificationHandler.swift:92` | `!deliveryId.isEmpty` removed | NH (19) | ❌ Survived → F2 (Minor) |
| H9 | `NottiNotificationHandler.swift:69-70` | body tap enqueues `clicked` before `opened` | NH | ✅ Killed (7) |
| H10 | `NottiNotificationHandler.swift:79` | custom action reports `opened` instead of `clicked` | NH | ✅ Killed |
| H11 | `NottiNotificationHandler.swift:62` | body tap buffers `.received` instead of `.clicked` | NH | ✅ Killed (3) |
| B2 | `NottiEventBuffer.swift` `setHandler` | buffered clicks replayed on attach | EB + NH | ✅ Killed (10) |
| B3 | `NottiEventBuffer.swift:39` | buffer cap 10 → 11 | EB | ✅ Killed |
| B4 | `NottiEventBuffer.swift:40` | dedupe memory 50 → 1 | EB + NH (31) | ❌ Survived → F3 (Note) |
| B5 | `NottiEventBuffer.swift` `emit` | `deliveredKeys` dedupe removed | EB + NH | ✅ Killed |
| B6 | `NottiEventBuffer.swift` `takeInitialClick` | oldest click wins instead of latest | EB | ✅ Killed |
| N2 | `NottiNetworkObserver.swift:109` | `lastStatus` never updated | NO + RT | ✅ Killed |
| N3 | `NottiNetworkObserver.swift` `cancel` | the monitor is not cancelled | NO + RT | ✅ Killed |
| ES1 | `NottiEventStore.swift:97` | cap overflow drops the newest instead of the oldest | ES | ✅ Killed |
| ES3 | `NottiEventStore.swift:88` | `createdAtMs` written in seconds | ES + CT + Core (132) | ❌ Survived → F4 (Note) |
| CT1 | `NottiEventStore.swift` `PendingEvent` | JSON key `createdAtMs` → `created_at_ms` (RN encoding broken) | ES + CT | ✅ Killed (CT ×2) |
| CT4 | `NottiCore.swift` `initializeOnQueue` | a nil token falls back to the persisted `lastToken` (re-registers on migrated state) | CT + Core (125) | ❌ Survived → F5 (Note) |
| RT1 | `NottiRuntime.swift` `stop` | core dropped without `invalidate()` | RT + LP | ✅ Killed |
| RT2 | `NottiRuntime.swift` `makeCore` | each core gets a fresh `SessionGate` (no adoption) | RT | ✅ Killed (4) |
| RT3 | `NottiRuntime.swift` `makeCore` | `onDeviceIdChanged` not forwarded | RT | ✅ Killed |

**Sensor depth**: P0-full manual (31 mutants: 12 on the round-1 gaps and their variants, 19 in areas round 1 covered less).
**Round-2 sensor outcome** - 25/31 killed. The 6 survivors are classified non-blocking below, so the sensor does not block.

### Findings (round 2)

- **F1 - Note (CORE-09 residual, owned by `public-api`)**: R1b and R1c survive because the test asserts the constant, not the wiring of `shared` (`NottiRuntime.swift:24-27`), which is the implementer's stated limitation. Judgement: not blocking. `NottiRuntime.shared` has **no caller in M1** (`grep -rn "NottiRuntime.shared" Sources Tests` → none), so the wiring cannot regress any M1 behavior. A regression now needs someone to replace a named constant with a different literal on the one line that uses it. The likely regression, editing the value, is guarded (R1 killed). **Action for `public-api`**: when the facade starts using `shared`, add a facade-level test that the production runtime reads and writes the `notti_prefs` suite. For example, seed a key in `UserDefaults(suiteName: "notti_prefs")` and observe it through the runtime's store, then clean up. Alternatively, expose the runtime's suite name for an assertion.
- **F2 - Minor (SDKCTR-04 edge, non-blocking)**: H8 survives. No test sends a non-empty `notification_id` with an **empty** `delivery_id`. `test_willPresentWithAnEmptyIdSkipsEnqueue` (`NottiNotificationHandlerTests.swift:111`) empties only `notification_id`. The code is faithful to RN (`NottiPushDelegate.swift:126-127` RN). SDKCTR-04's spec outcome ("no `notification_id`/`delivery_id` → skip silently") is covered by the absent-id tests, and empty strings are not in the RN spec. Impact if the check regresses: a malformed payload, which the backend contract never sends, would queue an event whose report gets a terminal 4xx and is dropped. **Suggested fix (one test, can go with `delegate-integration` or a follow-up)**: `willPresent(makeRemoteUserInfo(notificationId: "n-1", deliveryId: ""))` → `XCTAssertTrue(runtime.eventStore.all().isEmpty)`.
- **F3 - Note**: B4 survives. The dedupe memory size (50) is a ported tuning bound. RN's own tests do not assert it either. Dedupe itself (SDK-18 "a pulled click is never also delivered") is guarded (B5 killed). Duplicate delivery to listeners is part of the `public-api` listener surface.
- **F4 - Note**: ES3 survives. `PendingEvent.createdAtMs` has no consumer (`grep -rn createdAtMs Sources` hits only `NottiEventStore.swift`), and it is never sent to the backend. The persisted *encoding* (key name and type) is guarded by CT1. The value's unit is unobservable in M1.
- **F5 - Note**: CT4 survives because no test calls the token provider back with `nil` while a `lastToken` is persisted. The branch is unreachable in production: the live iOS `tokenProvider` never invokes its callback (`NottiPlatformProviders.swift:64-75`), and tokens arrive only through `onApnsToken` → `onTokenRefreshed`. CORE-10 holds on the real path (`NottiContinuityTests.swift:118`). Worth one test if a future provider can yield `nil` (for example, a wrapper).
- **F6 - Note (process)**: an `xcodebuild` process that this Verifier did not start (PID 89298, origin unknown) was running when round 2 began. It was gone after the first gate run, which ends with `pkill xcodebuild` in the watchdog. No result depends on it: every gate and every mutant ran alone afterwards.
- No LGPD/PII violation: all 24 core log strings are RN-identical with no PII interpolated, and L4/L4u/L7 prove the sentinel scan now catches token and external-id leaks at the failure sites. No extension-safety violation. No port-fidelity defect.
- Round-1 notes N1-N9 still apply unchanged.

### Gate check (round 2, HEAD `4303e49`)

- **Tests**: `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` → `** TEST SUCCEEDED **`. `NottiSharedTests` 14, `NottiSDKTests` 236, `NottiSDKExtensionTests` 1 = **251**, 0 failures, 0 skipped (round 1: 247, +4: 1 + 2 + 1).
- **SwiftLint** `lint --strict` (0.65.1, Docker): `Found 0 violations, 0 serious in 42 files.` rc 0.
- **Scripts**: `version ok: 0.1.0`, `extension safety ok`, `package graph ok`, each rc 0.
- **`pod lib lint NottiSDK.podspec --platforms=ios`**: `NottiSDK passed validation.` rc 0.
- **CI (PR #3, draft, head `4303e49`)**: run `38089421897` (`pull_request`) succeeded. `checks`, `lint`, `pod-lint` and `test` all pass, and CI's test log shows 236 / 14 / 1.

### Requirement traceability update (round 2)

| Requirement | Previous status | New status |
| --- | --- | --- |
| CORE-01..08, CORE-10, CORE-11 | ✅ Verified (round 1), re-checked | ✅ Verified |
| CORE-09 | ❌ Needs Fix | ✅ Verified (F1 note → `public-api`) |
| CORE-12 | ❌ Needs Fix | ✅ Verified |
| CORE-13 | ❌ Needs Fix | ✅ Verified |

### Summary (round 2)

**Overall**: ✅ Ready (merge-ready from the verification side)
**Spec-anchored check**: 13/13 ACs matched with discriminating tests; 0 spec-precision gaps.
**Sensor**: round 2 25/31 killed. All round-1 blocking survivors are now killed. The 6 new survivors are non-blocking (F1-F5).
**Gate**: 251 passed, 0 failed; SwiftLint 0; 3 scripts ok; `pod lib lint` passed; CI green.
**Next steps**: open the PR for review. Carry F1 into `public-api` (facade-level suite-name test) and F2 as a one-test follow-up.
