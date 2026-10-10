# Validation: core-port - FAIL ❌

**Date**: 2026-10-10
**Spec**: `.specs/features/core-port/spec.md`
**Diff range**: `main` (`437b826`) `..b3b7e18` on `feat/core-port` (13 commits, `5c47368..b3b7e18`; 38 files, +9351/-87). Code surface: `Sources/NottiShared/NottiNotificationParsing.swift`, `Sources/NottiSDK/{Core,Events,Network,Platform,Runtime,Storage}/*`, `Tests/NottiSDKTests/**`, `Tests/NottiSharedTests/{NottiNotificationParsingTests,NottiLoggerTests}.swift`, `Package.swift` (test resources).
**Verifier**: independent sub-agent (author ≠ verifier), round 1
**Environment**: Xcode 27.0 (27A266a), simulator `iPhone 17 Pro`, CocoaPods (local), SwiftLint 0.65.1 (Docker). RN baseline `../zeep-notti-react-native` at `52e4b55`, files extracted with `git show 52e4b55:ios/<file>`.

**Verdict**: FAIL. Three surviving mutants in the scope of CORE ACs (CORE-09, CORE-12, CORE-13). The code itself has no defect and is a faithful port: every gap is a test that does not detect a regression. All fixes are small test additions (one also adds a constant). Everything else passes.

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
**Result**: 33/37 killed. FAIL ❌ (R1, L4, G2 blocking; L6 non-blocking, already recorded).

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
