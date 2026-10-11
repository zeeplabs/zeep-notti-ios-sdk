# Validation: public-api - PASS ✅ (round 2)

**Date**: 2026-10-11 (round 2; round 1 the same day)
**Spec**: `.specs/features/public-api/spec.md` (API-01..API-15, plus the facade part of SDK-17..19, SDKOPEN-10, DPF-17..21)
**Diff range**: round 2 re-verifies `main` (`d55d980`) `..faa3c99` on `feat/public-api` (22 commits). Round-1 fix range: `469593c..faa3c99` (3 test/script fixes, lessons, status lines; `git diff --stat e31812b..HEAD -- Sources` is empty). Branch not pushed.
**Verifier**: a third independent sub-agent. It wrote neither the code, the round-1 report, nor the round-1 fixes. Read-only over the real tree: every mutant was applied, run and reverted with `git checkout -- <file>`; `git diff --stat` was empty after each (ledger column `dirty=0`).
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro`, SwiftLint 0.65.1 (Docker), CocoaPods (local), Docker `ubuntu:24.04` for the Linux run of the surface script.

**Verdict (round 2)**: PASS. All five round-1 blockers are killed on the new tree (U15, U16, U17, S06 by tests; E1 by `scripts/check-public-surface.sh`). 26 fresh code mutants on the new tests and wiring: 25 killed, 1 survived (B33, a Note); plus 32 script cases against the new G3 guard, with 4 false passes and 1 false fail, none of which touches a type that exists today. The 7 round-1 Notes that were deliberately not fixed were re-run and are unchanged. Gates are green on the unmodified tree: 356 tests (Shared 14, SDK 337, ObjC 4, Ext 1), SwiftLint 0, four scripts, `pod lib lint`, `validate_spec`, `validate_tasks`. CI is not checkable (branch not pushed). See [Round 2](#round-2) at the end. Round 1 is kept unchanged below as a record; its only edit is the sensor-tally label, renamed so that the verdict parser reads round 2's verdict.

**Blocking criteria (unchanged from round 1)**: only (a) an acceptance criterion of API-01..API-15 (or the inherited facade IDs SDK-17..19, SDKOPEN-10, DPF-17..21) with no test that fails when the behavior is wrong, (b) a correctness/LGPD/security defect, (c) a spec or AD-002 violation, or (d) a red gate blocks PASS. Everything else is a Note with a severity.

<details><summary>Round 1 (FAIL) - kept as a record</summary>

Round 1 verdict: FAIL ❌

**Date**: 2026-10-11
**Spec**: `.specs/features/public-api/spec.md` (API-01..API-15, plus the facade part of SDK-17..19, SDKOPEN-10, DPF-17..21)
**Diff range**: `main` (`d55d980`) `..e31812b` on `feat/public-api` (14 tasks, `1744c66..e31812b` on top of spec commits `3abaf8e`). Branch not pushed.
**Verifier**: independent sub-agent (author ≠ verifier). Wrote none of the code, tests, `traceability.md` or this report's inputs. Read-only over the real tree: every mutant was applied to `Sources`, run, and reverted with `git checkout -- <file>`; `git diff --stat` was empty after each one (ledger column "TREE-DIRTY" never appeared), and `git status` is clean except this file.
**Environment**: Xcode 27.0, simulator `iPhone 17 Pro` (booted), CocoaPods (local), SwiftLint 0.65.1 (Docker), Docker 29.4 (`ubuntu:24.04` for the Linux run of the surface script). Tests run through the watchdog `run.sh` (never piping `xcodebuild`).

**Verdict (round 1)**: FAIL. The gates are green and the discrimination is strong (104 of 119 mutants killed, 1 build-broken and redone), but **three acceptance criteria have a mutant that no test kills**:

1. **G1** (API-07): `setPhone`, `clearEmail` and `clearPhone` called *before* `initialize` are not proven to reach a core that exists before `start`. Mutants U15/U16/U17 survive.
2. **G2** (API-10): the public `Notti.Notifications.addClickedListener` can be wired to the `received` event and every test still passes (S06). The facade-level tests catch the same bug one layer down (L01/L02 killed), but not in the public shell.
3. **G3** (API-15, AC 2): removing `@available(iOSApplicationExtension, unavailable)` from `public enum Notti` is caught by nothing: no test, no script, no build (E1). The spec says the app-only API "SHALL be marked" this way.

All three are small and local (tests or a few lines in the surface script). Nothing else blocks: no correctness, LGPD, security, AD-002 or gate defect was found. Everything else is a Note.

**Blocking criteria applied (as instructed):** only (a) an acceptance criterion of API-01..API-15 (or the inherited facade IDs) with no test that fails when the behavior is wrong, (b) a correctness/LGPD/security defect, (c) a spec or AD-002 violation, or (d) a red gate blocks PASS. Style, speculative hardening, items outside the spec, and risks that need a product decision are Notes with a severity. CI itself was **not** checked: the branch is not pushed, so `ci.yml` was verified by reading and by running the same scripts and commands locally (and the surface script on `ubuntu:24.04`).

---

## Task Completion

| Task | Status | Notes |
| --- | --- | --- |
| T1 spike | ✅ Done | Spike results committed (`1744c66`), no source change |
| T2 `ensureCore` | ✅ Done | `1699958`; T6 later changed `invalidateCurrentCore` (see Findings F1) |
| T3 listener hub + `NottiSubscription` | ✅ Done | new files |
| T4 payload | ✅ Done | new file |
| T5-T9, T11 facade (initialize, profile, permission, listeners, log level) | ✅ Done | one commit each |
| T10 public Swift shell | ✅ Done | `Notti.swift`; G2 and G3 live here |
| T12 ObjC layer + ObjC test target | ✅ Done | `NottiObjC.swift`, `NottiSDKObjCTests` |
| T13 surface guard + CI | ✅ Done | script, `PUBLIC_SURFACE.txt`, `checks` job step |
| T14 traceability | ✅ Done | `traceability.md` written; its claims were re-derived below, not trusted |

---

## Spec-anchored acceptance criteria (evidence-or-zero)

Test files are under `Tests/NottiSDKTests/` (`FI` = `NottiFacadeInitializeTests`, `FP` = `NottiFacadeProfileTests`, `FM` = `NottiFacadePermissionTests`, `FL` = `NottiFacadeListenerTests`, `LH` = `NottiListenerHubTests`, `NP` = `NottiNotificationPayloadTests`, `FG` = `NottiFacadeLogLevelTests`, `PA` = `NottiPublicApiTests`, `OB` = `NottiObjCBridgeTests`, `PR` = `NottiLoggingPrivacyTests`, `RT` = `NottiRuntimeTests`, `OC` = `NottiSDKObjCTests/NottiObjCTests.m`). "Killed" lists mutant ids from the ledger below.

| Req | Spec-defined outcome | `file:line` + assertion | Mutants | Result |
| --- | --- | --- | --- | --- |
| API-01 | `initialize` starts the runtime; omitted/`nil` baseUrl is `https://app.zeepnotti.app`; invalid appId/clientKey/baseUrl never throws, logs without the values, uninitialized stays uninitialized, a running core is not replaced | `FI:199` `XCTAssertEqual(url?.host, "app.zeepnotti.app")`; `FI:168` `XCTAssertTrue(runtime.core === running)`; `FI:175-176` `XCTAssertNil(facade.activeConfig)` / `XCTAssertNil(runtime.core)`; `FI:105` log never contains a value; `PA:109` options.baseUrl reaches the facade; `PR:255,302` sentinels incl. `sentinel-invalid-*` | F02, F03, F04, F05, F06, F09, F10, S01 killed (each clause of the guard has its own negative: appId F04, clientKey F05, baseUrl F06) | ✅ PASS |
| API-02 | same normalized triple is a no-op (no 2nd registration); any difference rebuilds | `FI:121` `registrations.count == 1` after identical call; `FI:125` `== 2` for a new appId; `FI:135,139` clientKey and baseUrl; `FI:152` `https://x/` ≡ `https://x` ≡ `  https://x//  ` | F01 (raw vs normalized), F08, X3, X4, X5 (each conjunct of the config compare) killed. **F07 (lock removed) survives** | ✅ PASS for the ACs. Race edge case: Note N1 |
| API-03 | production path goes through `NottiRuntime.shared`, a test proves it reads/writes `notti_prefs` | `PA:260` `test_productionFacadeReadsTheDeviceIdFromTheNottiPrefsSuite` (literal suite name) | R06 (suite renamed), R07 (`.standard` fallback) killed | ✅ PASS (closes F1) |
| API-04 | `login` -> `core.login`, `logout` -> `core.logout`, core persistence semantics | `FP:101` `external_user_id == "user-fixture"`; `FP:117-122` store cleared + explicit-null email/phone PATCH; `PA:127` | U01, U02, S02, B05 killed. B12 (ObjC logout) survives (N2) | ✅ PASS |
| API-05 | `deviceId` synchronous persisted id, also before `initialize`, `nil` if never registered; observers called once per real change, on main thread | `FP:223-236` persisted / nil / registered; `FL:192-210` fires once per real change, not on same-id re-registration; `FL:243` through the dispatcher | U12, U14, L03, L04 killed | ✅ PASS |
| API-06 | `addTag(s)`/`removeTag(s)` -> `mutateTags(add:remove:)`; ObjC passes through `sanitizeTags` | `FP:125,134` merged map PATCH; `OB:90` non-string values dropped (ObjC) | U03, U04, S03, S08, B01, B13, B15 killed. B23 (ObjC `removeTag`) survives (N2) | ✅ PASS |
| API-07 | `setEmail`/`clearEmail`/`setPhone`/`clearPhone`, **also before `initialize`**, call the core on a core that exists before `start` | `FP:192-208` only covers `setEmail` then `setPhone` in one test; `FP:156` clear* only after initialize | U05-U08, U13 killed; **U15 (`setPhone`), U16 (`clearEmail`), U17 (`clearPhone`) survive** | ❌ **GAP G1** |
| API-08 | `setSubscription` incl. `last_unsubscribed_at`; location preference written synchronously, default false | `FP:170,180` PATCH fields; `FP:241-249` `XCTAssertTrue(store.getLocationSharingEnabled(), "read back synchronously, no drain")` | U09, U10 (async hop), U11 killed | ✅ PASS |
| API-09 | `requestPermission` returns the OS result, `false` and no prompt before initialize, completion variant identical, once | `FM:108` granted/denied through dispatcher; `FM:129` before-init `false`, requester never called; `FM:146` double callback delivers once; `FM:174` async variant | P01 (once-guard), P02 (main hop), X1 (async result), S04, S11, B09 killed | ✅ PASS |
| API-10 | subscription token; `remove()` stops and is idempotent; several listeners in registration order on main; detach on last removal; add/remove inside callback safe; replay to first `received` listener only; payload `title/body/data` | `LH:97-150` attach/detach, replay-first-only, order, never inline; `LH:152-187` add/remove in callback; `LH:191-230` double remove, closure release; `FL:95-136` live delivery, replay, detach buffers again, pre-initialize; `FL:149` typed payload; `NP:7-87` mapping | H01-H09, H11, H13, L01-L04, L06, X6, N01-N06 killed. **S06 survives** (public shell). H10/H12 equivalent pair (N6) | ❌ **GAP G2** (public `Notti.Notifications.addClickedListener`) |
| API-11 | `takeInitialClick` once then `nil`; clicks never replayed | `FL:164-176` not replayed, taken once, second call `nil`; `FL:178` live click is not an initial click; `PA:247` | L05, S05, B10 killed | ✅ PASS |
| API-12 | callbacks on the main thread; delivery order = emission order | `LH:138` nothing runs until the dispatcher does; `FL:95,243`; `FM:108`; OC `requestPermission` asserts `NSThread.isMainThread` | H09 (inline), P02, H07 (late recipient capture), H08 (order) killed | ✅ PASS |
| API-13 | every P1 capability callable from ObjC; `NSDictionary` payload; non-string tags dropped; a compile check in the repo | `OC` `testNottiEntryPointsAreCallable`, `testUserEntryPointsAreCallable`, `testNotificationsEntryPointsAreCallable` (compile + call); `OB:90,102,119,135,157,178` forwarding and shape | B01-B11, B13-B19 killed. B12, B20-B23 survive (N2) | ✅ PASS (AC says "callable", which the compile check proves; forwarding of 5 entry points is unproven: Note N2) |
| API-14 | levels map to `NottiLogger.level` both ways, readable; initial `.error`; no level logs PII | `FG:45` initial effective value read through the facade; `FG:50` all 6 levels round-trip and land on `NottiLogger.level`; `FG:59` both mappings; `PR:255,302` sentinels at `.verbose`; `PR:327` | G_none..G_verbose (all 6 core mappings), G_i1, G_i2, G_def (default `.error` -> `.warn`) killed | ✅ PASS (L-010 applied correctly) |
| API-15 | only listed symbols are `public`, CI fails on drift; app-only API marked `@available(iOSApplicationExtension, unavailable)`; no `package` type in a public signature; no PII at all levels | `scripts/check-public-surface.sh` + `.specs/codebase/PUBLIC_SURFACE.txt` (24 trees, below); `ci.yml:45-47` step in `checks`; `PR:255,302` | F09-F15 (PII in facade log lines) killed. **E1 (attribute removed) survives** | ❌ **GAP G3** (AC 2 attribute). Rest ✅ |
| SDK-17..19, SDKOPEN-10 (facade part) | listener/emitter and JS events surface | covered through API-10/API-11 rows | as above | ✅ (same caveat as G2) |
| DPF-17..21 (facade part) | JS-surface wording for email/phone | covered through API-07 | as above | ❌ same gap as G1 |

**Status**: ❌ gaps present (G1, G2, G3). No ⚠️ spec-precision gaps: every outcome the ACs name is precise enough to assert.

---

## Gates (unmodified tree, HEAD `e31812b`)

| Gate | Result |
| --- | --- |
| Full test run, `NBUNDLES=4` | ✅ `** TEST SUCCEEDED **`, 351 tests, 0 failures, 0 skipped. Bundles: `NottiSharedTests` 14, `NottiSDKTests` 332, `NottiSDKObjCTests` 4, `NottiSDKExtensionTests` 1 (each "passed"). 351 `Test Case ... passed` lines. Spec floor was 252: +99 |
| SwiftLint `0.65.1 --strict` (Docker) | ✅ 0 violations, 0 serious, 57 files |
| `check-version.sh` | ✅ `version ok: 0.1.0` |
| `check-extension-safety.sh` | ✅ |
| `check-package-graph.sh` | ✅ |
| `check-public-surface.sh` | ✅ `public surface ok (58 declarations)`, on macOS and in `ubuntu:24.04` (`docker run ... ubuntu:24.04 scripts/check-public-surface.sh`, awk is mawk there) |
| `pod lib lint NottiSDK.podspec --platforms=ios` | ✅ `NottiSDK passed validation.` (only AppIntents metadata NOTEs) |
| `validate_spec.py` | ✅ 0 errors, 0 warnings |
| `validate_tasks.py` | ✅ 0 errors, 11 warnings (granularity smells and "Tests: none" on T13/T14; accepted) |
| `validate_state.py public-api` | exit 1 by design: it reads this report, whose verdict is FAIL (it will pass once a PASS round exists) |
| CI (`.github/workflows/ci.yml`) | ⚠️ Not verifiable: branch not pushed. Read instead: the `Public API surface (API-15)` step exists in the `checks` job (`ubuntu-24.04`), the scripts are `100755` in git, and the `test` job runs the whole `NottiSDK-Package` scheme, which includes the new ObjC target |

**Test integrity**: tests were only added (`git diff --numstat` shows no deleted test lines; the only Sources file with deletions is `NottiRuntime.swift`, 2 lines, intended). Test count did not drop.

---

## Discrimination Sensor (mutation testing)

**Depth**: full manual mutation run (public-api touches initialize idempotency, concurrency and PII, so the ≥5 minimum was far exceeded): **119 mutants**, run against the whole `NottiSDKTests` bundle (332 tests, ~15 s) and additionally `NottiSDKObjCTests` for the ObjC ones. Build time dominated (~45 s each). Pattern counts were asserted to be exactly 1 before each edit. After each mutant: `git checkout -- <file>`, `git diff --stat` empty.

**Totals**: killed 104 (one of them by hang/timeout, R01), **survived 14**, build-broken 1 (P03, re-crafted as X1 which compiled and was killed). Ledger file kept in the scratchpad (`ledger.tsv`); table below.

Survivor triage:

- **Blocking**: U15, U16, U17 (G1), S06 (G2), E1 (G3).
- **Note**: F07, R09 (lock removals, N1), B12, B20, B21, B22, B23 (ObjC forwards, N2), H10 and H12 (equivalent pair, N6).

Mutant ledger:

| # | File:line | Mutation | Result | Failing test (first of N) | Classification |
| --- | --- | --- | --- | --- | --- |
| F01 | `Sources/NottiSDK/Facade/NottiFacade.swift:92` | idempotency compares raw baseUrl not normalized | ✅ killed | test_valuesThatAreEqualAfterNormalizationCountAsTheSame | - |
| F02 | `Sources/NottiSDK/Facade/NottiFacade.swift:16` | default baseUrl constant changed | ✅ killed | test_aNilBaseUrlSendsTheRequestToTheDefaultHost | - |
| F03 | `Sources/NottiSDK/Facade/NottiFacade.swift:89` | invalid-arg path stops the running core | ✅ killed | test_invalidArgumentsAreLoggedWithoutValuesAndLeaveTheRunningCoreInPlace | - |
| F04 | `Sources/NottiSDK/Facade/NottiFacade.swift:85` | empty appId clause removed | ✅ killed | test_invalidArgumentsAreLoggedWithoutValuesAndLeaveTheRunningCoreInPlace (+1) | - |
| F05 | `Sources/NottiSDK/Facade/NottiFacade.swift:86` | empty clientKey clause removed | ✅ killed | test_invalidArgumentsAreLoggedWithoutValuesAndLeaveTheRunningCoreInPlace | - |
| F06 | `Sources/NottiSDK/Facade/NottiFacade.swift:87` | baseUrl validation removed | ✅ killed | test_facadeFlowWithFailuresAtVerboseLogsNoSentinelValue (+2) | - |
| F07 | `Sources/NottiSDK/Facade/NottiFacade.swift:93` | initialize lock removed | ❌ **SURVIVED** | - | Note (N1) |
| F08 | `Sources/NottiSDK/Facade/NottiFacade.swift:96` | activeConfig never recorded | ✅ killed | test_aNilBaseUrlSendsTheRequestToTheDefaultHost (+3) | - |
| F09 | `Sources/NottiSDK/Facade/NottiFacade.swift:89` | invalid-arg log carries appId | ✅ killed | test_facadeFlowWithFailuresAtVerboseLogsNoSentinelValue (+1) | - |
| F10 | `Sources/NottiSDK/Facade/NottiFacade.swift:89` | invalid-arg log carries baseUrl | ✅ killed | test_facadeFlowWithFailuresAtVerboseLogsNoSentinelValue (+2) | - |
| F11 | `Sources/NottiSDK/Facade/NottiFacade.swift:97` | success path logs appId/clientKey/baseUrl | ✅ killed | test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue (+2) | - |
| F12 | `Sources/NottiSDK/Facade/NottiFacade.swift:112` | login logs external user id | ✅ killed | test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue (+1) | - |
| F13 | `Sources/NottiSDK/Facade/NottiFacade.swift:128` | setEmail logs email | ✅ killed | test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue (+1) | - |
| F14 | `Sources/NottiSDK/Facade/NottiFacade.swift:120` | addTags logs tag values | ✅ killed | test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue (+1) | - |
| F15 | `Sources/NottiSDK/Facade/NottiFacade.swift:136` | setPhone logs phone | ✅ killed | test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue (+1) | - |
| H01 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:83` | add: attachLock removed | ✅ killed | test_concurrentAddAndRemoveNeverLeaveTheSourceAttachedToAnEmptyList | - |
| H02 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:100` | remove: attachLock removed | ✅ killed | test_concurrentAddAndRemoveNeverLeaveTheSourceAttachedToAnEmptyList | - |
| H03 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:86` | attach before list update (replay misses first listener) | ✅ killed | test_removingTheLastListenerDetachesSoLaterEventsAreBufferedForTheNextFirstListener (+2) | - |
| H04 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:108` | detach never called on last removal | ✅ killed | test_afterTheLastClickedListenerIsRemovedAClickWaitsForTakeInitialClick (+3) | - |
| H05 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:108` | detach on every remove call (even idempotent) | ✅ killed | test_aListenerRemovedInsideACallbackStopsFromTheNextEvent (+3) | - |
| H06 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:93` | attach on every add | ✅ killed | test_attachOnFirstListenerAndDetachOnLastOnly (+3) | - |
| H07 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:116` | recipients captured inside dispatched block (late) | ✅ killed | test_synchronousReplayInsideAttachReachesTheFirstListenerOnly (+1) | - |
| H08 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:88` | registration order reversed | ✅ killed | test_aListenerAddedInsideACallbackReceivesOnlyLaterEvents (+3) | - |
| H09 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:117` | delivery inline instead of dispatcher | ✅ killed | test_aDeviceIdChangeIsDeliveredThroughTheDispatcher (+3) | - |
| H10 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:104` | remove of unknown id reports last-removed | ❌ **SURVIVED** | - | Note (N6, equivalent pair with H12) |
| H11 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:119` | removed-before-turn listener not skipped | ✅ killed | test_aListenerRemovedAfterTheEventWasQueuedIsNotCalled | - |
| H12 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:28` | subscription keeps onRemove after remove (not nil-ed) | ❌ **SURVIVED** | - | Note (N6, equivalent pair with H10) |
| H13 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:104` | remove ignores id (removes first entry) | ✅ killed | test_aRemovedReceivedListenerIsNotCalledAgainWhileAnotherKeepsListening (+1) | - |
| L01 | `Sources/NottiSDK/Facade/NottiFacade.swift:46` | received hub bound to .clicked | ✅ killed | test_aReceivedListenerRegisteredBeforeInitializeReceivesEvents (+3) | - |
| L02 | `Sources/NottiSDK/Facade/NottiFacade.swift:47` | clicked hub bound to .received | ✅ killed | test_aLiveClickReachesEveryClickedListener (+2) | - |
| L03 | `Sources/NottiSDK/Facade/NottiFacade.swift:50` | deviceId hub detach is a no-op | ✅ killed | test_removingTheLastDeviceIdListenerClearsTheRuntimeHandler | - |
| L04 | `Sources/NottiSDK/Facade/NottiFacade.swift:49` | deviceId hub attach is a no-op | ✅ killed | test_aDeviceIdChangeIsDeliveredThroughTheDispatcher (+3) | - |
| L05 | `Sources/NottiSDK/Facade/NottiFacade.swift:209` | takeInitialClick always nil | ✅ killed | test_aColdStartClickIsNeverReplayedToListenersAndIsTakenOnce (+3) | - |
| L06 | `Sources/NottiSDK/Facade/NottiFacade.swift:64` | notification hub detach is a no-op | ✅ killed | test_afterTheLastClickedListenerIsRemovedAClickWaitsForTakeInitialClick (+1) | - |
| P01 | `Sources/NottiSDK/Facade/NottiFacade.swift:161` | permission once-guard removed | ✅ killed | test_aCallbackInvokedTwiceDeliversTheCompletionOnce | - |
| P02 | `Sources/NottiSDK/Facade/NottiFacade.swift:162` | permission completion without main hop | ✅ killed | test_grantedAndDeniedOsResultsComeBackThroughTheDispatcher | - |
| P03 | `Sources/NottiSDK/Facade/NottiFacade.swift:170` | async permission always true | ⚠️ build-broken (redone as X1) | - | - (re-crafted as X1) |
| U01 | `Sources/NottiSDK/Facade/NottiFacade.swift:112` | login not forwarded | ✅ killed | test_loginAndLogoutReachTheFacade (+3) | - |
| U02 | `Sources/NottiSDK/Facade/NottiFacade.swift:116` | logout not forwarded | ✅ killed | test_loginAndLogoutReachTheFacade (+1) | - |
| U03 | `Sources/NottiSDK/Facade/NottiFacade.swift:120` | addTags becomes remove | ✅ killed | test_addTagsPatchesTheMergedMap (+3) | - |
| U04 | `Sources/NottiSDK/Facade/NottiFacade.swift:124` | removeTags passes nil | ✅ killed | test_removeTagsPatchesTheRemainingMap (+2) | - |
| U05 | `Sources/NottiSDK/Facade/NottiFacade.swift:128` | setEmail calls clearEmail | ✅ killed | test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration (+3) | - |
| U06 | `Sources/NottiSDK/Facade/NottiFacade.swift:132` | clearEmail not forwarded | ✅ killed | test_clearEmailAndClearPhoneSendExplicitNull (+1) | - |
| U07 | `Sources/NottiSDK/Facade/NottiFacade.swift:136` | setPhone sends the value as email | ✅ killed | test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration (+2) | - |
| U08 | `Sources/NottiSDK/Facade/NottiFacade.swift:140` | clearPhone calls clearEmail | ✅ killed | test_clearEmailAndClearPhoneSendExplicitNull (+1) | - |
| U09 | `Sources/NottiSDK/Facade/NottiFacade.swift:144` | setSubscription inverted | ✅ killed | test_subscribingSendsSubscribedTrueWithoutLastUnsubscribedAt (+3) | - |
| U10 | `Sources/NottiSDK/Facade/NottiFacade.swift:150` | location sharing hopped to async (not sync write) | ✅ killed | test_locationSharingPreferenceIsWrittenBeforeTheCallReturns (+2) | - |
| U11 | `Sources/NottiSDK/Facade/NottiFacade.swift:150` | location sharing inverted | ✅ killed | test_locationSharingPreferenceIsWrittenBeforeTheCallReturns (+2) | - |
| U12 | `Sources/NottiSDK/Facade/NottiFacade.swift:108` | deviceId always nil | ✅ killed | test_deviceIdIsThePersistedIdBeforeInitialize (+3) | - |
| U13 | `Sources/NottiSDK/Facade/NottiFacade.swift:128` | setEmail drops before initialize (no ensureCore) | ✅ killed | test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration | - |
| U14 | `Sources/NottiSDK/Facade/NottiFacade.swift:108` | deviceId before initialize returns nil (no ensureCore) | ✅ killed | test_deviceIdIsThePersistedIdBeforeInitialize (+2) | - |
| U15 | `Sources/NottiSDK/Facade/NottiFacade.swift:136` | setPhone dropped before initialize | ❌ **SURVIVED** | - | BLOCKING (G1) |
| U16 | `Sources/NottiSDK/Facade/NottiFacade.swift:132` | clearEmail dropped before initialize | ❌ **SURVIVED** | - | BLOCKING (G1) |
| U17 | `Sources/NottiSDK/Facade/NottiFacade.swift:140` | clearPhone dropped before initialize | ❌ **SURVIVED** | - | BLOCKING (G1) |
| R01 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:131` | ensureCore does not store the core | ✅ killed (hang) | test_beforeInitializeTheResultIsFalseAndTheRequesterIsNeverCalled | - |
| R02 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:188` | retired core not retained (T6 retention removed) | ✅ killed | test_aMutationQueuedOnTheEnsuredCoreSurvivesStartReplacingIt (+1) | - |
| R03 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:113` | start does not invalidate previous core | ✅ killed | test_aMutationQueuedOnTheEnsuredCoreSurvivesStartReplacingIt (+2) | - |
| R04 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:130` | ensureCore always builds a new core | ✅ killed | test_aCallbackInvokedTwiceDeliversTheCompletionOnce (+3) | - |
| R05 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:183` | invalidate removed on replace | ✅ killed | test_startTwiceInvalidatesTheFirstCoreAndTheSecondAdoptsTheOpenSession (+1) | - |
| R06 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:20` | shared suite name changed | ✅ killed | test_productionFacadeReadsTheDeviceIdFromTheNottiPrefsSuite (+1) | - |
| R07 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:25` | shared falls back to .standard | ✅ killed | test_productionFacadeReadsTheDeviceIdFromTheNottiPrefsSuite | - |
| R08 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:194` | retire timeout 0 (drain wait immediate) | ✅ killed | test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration | - |
| R09 | `Sources/NottiSDK/Runtime/NottiRuntime.swift:126` | ensureCore without lifecycleLock | ❌ **SURVIVED** | - | Note (N1) |
| N01 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:27` | title/body swapped | ✅ killed | test_aColdStartClickIsNeverReplayedToListenersAndIsTakenOnce (+3) | - |
| N02 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:29` | non-string data values stringified instead of dropped | ✅ killed | test_nonStringDataValuesAreDroppedAndStringsKept | - |
| N03 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:25` | missing data becomes non-empty | ✅ killed | test_aNonDictionaryDataValueBecomesAnEmptyDictionary (+1) | - |
| N04 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:38` | data key changed | ✅ killed | test_aColdStartClickIsNeverReplayedToListenersAndIsTakenOnce (+3) | - |
| N05 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:36` | title key changed | ✅ killed | test_aColdStartClickIsNeverReplayedToListenersAndIsTakenOnce (+3) | - |
| N06 | `Sources/NottiSDK/Facade/NottiNotificationPayload.swift:37` | body key changed | ✅ killed | test_aPayloadBuiltByTheCoreParsingRoundTrips (+3) | - |
| G_none | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:42` | coreLevel .none mapped to .error | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+2) | - |
| G_error | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:43` | coreLevel .error mapped to .warn | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+1) | - |
| G_warn | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:44` | coreLevel .warn mapped to .info | ✅ killed | test_aMessageAboveTheSetLevelIsNotEmittedAndOneAtOrBelowIs (+3) | - |
| G_info | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:45` | coreLevel .info mapped to .debug | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+1) | - |
| G_debug | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:46` | coreLevel .debug mapped to .verbose | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+1) | - |
| G_verbose | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:47` | coreLevel .verbose mapped to .debug | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+3) | - |
| G_i1 | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:36` | init(.verbose) mapped to .debug | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+2) | - |
| G_i2 | `Sources/NottiSDK/Facade/NottiLogLevelObjC.swift:31` | init(.none) mapped to .error | ✅ killed | test_everyLevelRoundTripsAndLandsOnTheLogger (+1) | - |
| G_def | `Sources/NottiShared/NottiLogger.swift:38` | default level .warn | ✅ killed | test_defaultLevelIsErrorAndNothingBelowItIsEmitted (+1) | - |
| S01 | `Sources/NottiSDK/Public/Notti.swift:38` | shell initialize ignores options.baseUrl | ✅ killed | test_initializeReachesTheFacadeWithTheOptionsBaseUrl | - |
| S02 | `Sources/NottiSDK/Public/Notti.swift:43` | shell login not forwarded | ✅ killed | test_loginAndLogoutReachTheFacade | - |
| S03 | `Sources/NottiSDK/Public/Notti.swift:83` | shell addTag swaps key/value | ✅ killed | test_userTagMethodsReachTheFacade | - |
| S04 | `Sources/NottiSDK/Public/Notti.swift:134` | shell requestPermission(completion:) not forwarded | ✅ killed | test_requestPermissionCompletionReachesTheFacade | - |
| S05 | `Sources/NottiSDK/Public/Notti.swift:160` | shell takeInitialClick nil | ✅ killed | test_takeInitialClickReachesTheFacade | - |
| S06 | `Sources/NottiSDK/Public/Notti.swift:154` | shell clicked listener bound to received | ❌ **SURVIVED** | - | BLOCKING (G2) |
| S07 | `Sources/NottiSDK/Public/Notti.swift:74` | shell logLevel setter not forwarded | ✅ killed | test_logLevelGetAndSetReachTheLogger | - |
| S08 | `Sources/NottiSDK/Public/Notti.swift:92` | shell removeTag removes nothing | ✅ killed | test_userTagMethodsReachTheFacade | - |
| S09 | `Sources/NottiSDK/Public/Notti.swift:117` | shell setSubscription not forwarded | ✅ killed | test_userEmailPhoneAndSubscriptionMethodsReachTheFacade | - |
| S10 | `Sources/NottiSDK/Public/Notti.swift:112` | shell clearPhone -> clearEmail | ✅ killed | test_userEmailPhoneAndSubscriptionMethodsReachTheFacade | - |
| S11 | `Sources/NottiSDK/Public/Notti.swift:128` | shell async requestPermission always false | ✅ killed | test_requestPermissionAsyncReachesTheFacade | - |
| S12 | `Sources/NottiSDK/Public/Notti.swift:62` | shell deviceId listener not forwarded | ✅ killed | test_deviceIdChangedListenerReachesTheFacadeAndCanBeRemoved | - |
| B01 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:78` | ObjC addTags sanitize replaced by all-or-nothing cast | ✅ killed | test_nonStringTagValuesAreDroppedThroughTheObjCPath | - |
| B02 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:150` | ObjC payload dict loses data | ✅ killed | test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt | - |
| B03 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:151` | ObjC payload always has title | ✅ killed | test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt | - |
| B04 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:152` | ObjC payload drops body | ✅ killed | test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt | - |
| B05 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:31` | ObjC login not forwarded | ✅ killed | test_nottiObjCReachesTheFacade | - |
| B06 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:26` | ObjC initialize not forwarded | ✅ killed | test_clickedListenerAndDeviceIdListenerReachTheFacade (+3) | - |
| B07 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:93` | ObjC setEmail not forwarded | ✅ killed | test_userMethodsReachTheFacade | - |
| B08 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:137` | ObjC addClickedListener bound to received | ✅ killed | test_clickedListenerAndDeviceIdListenerReachTheFacade | - |
| B09 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:125` | ObjC requestPermission not forwarded | ✅ killed | test_requestPermissionCompletionReachesTheFacade | - |
| B10 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:143` | ObjC takeInitialClick nil | ✅ killed | test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt | - |
| B11 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:42` | ObjC deviceId nil | ✅ killed | test_nottiObjCReachesTheFacade | - |
| B12 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:36` | ObjC logout not forwarded | ❌ **SURVIVED** | - | Note (N2) |
| B13 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:72` | ObjC addTag swaps | ✅ killed | test_userMethodsReachTheFacade | - |
| B14 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:113` | ObjC setSubscription inverted | ✅ killed | test_userMethodsReachTheFacade | - |
| B15 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:88` | ObjC removeTags not forwarded | ✅ killed | test_userMethodsReachTheFacade | - |
| B16 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:131` | ObjC addReceivedListener drops events | ✅ killed | test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt | - |
| B17 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:50` | ObjC deviceId listener not forwarded | ✅ killed | test_clickedListenerAndDeviceIdListenerReachTheFacade | - |
| B18 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:61` | ObjC logLevel setter no-op | ✅ killed | testLogLevelRoundTripsThroughTheObjCEnum (+1) | - |
| B19 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:55` | ObjC setLocationSharing not forwarded | ✅ killed | test_nottiObjCReachesTheFacade | - |
| B20 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:103` | ObjC setPhone not forwarded | ❌ **SURVIVED** | - | Note (N2) |
| B21 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:98` | ObjC clearEmail not forwarded | ❌ **SURVIVED** | - | Note (N2) |
| B22 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:108` | ObjC clearPhone not forwarded | ❌ **SURVIVED** | - | Note (N2) |
| B23 | `Sources/NottiSDK/Public/ObjC/NottiObjC.swift:83` | ObjC removeTag not forwarded | ❌ **SURVIVED** | - | Note (N2) |
| X1 | `Sources/NottiSDK/Facade/NottiFacade.swift:170` | async permission result forced true (compiling redo of P03) | ✅ killed | test_theAsyncVariantReturnsTheOsResultAndFalseBeforeInitialize | - |
| X3 | `Sources/NottiSDK/Facade/NottiFacade.swift:95` | idempotency ignores appId | ✅ killed | test_deviceIdChangedFiresOncePerRealChangeAndNotOnAReRegistrationWithTheSameId (+3) | - |
| X4 | `Sources/NottiSDK/Facade/NottiFacade.swift:95` | idempotency ignores clientKey | ✅ killed | test_aDifferentClientKeyOrBaseUrlAlsoRebuildsTheCore | - |
| X5 | `Sources/NottiSDK/Facade/NottiFacade.swift:95` | idempotency ignores baseUrl | ✅ killed | test_aDifferentClientKeyOrBaseUrlAlsoRebuildsTheCore | - |
| X6 | `Sources/NottiSDK/Facade/NottiListenerHub.swift:32` | NottiSubscription.remove never runs the action | ✅ killed | test_aListenerRemovedAfterTheEventWasQueuedIsNotCalled (+3) | - |
| E1 | `Sources/NottiSDK/Public/Notti.swift:16` | @available(iOSApplicationExtension, unavailable) removed from public enum Notti (API-15 AC2) | ❌ **SURVIVED** | - | BLOCKING (G3) |

**Sensor tally (round 1)**: 104/119 killed; 5 blocking survivors (3 distinct gaps), 9 non-blocking survivors. ❌ FAIL.

---

## Public surface guard (scripts/check-public-surface.sh) proven against passing and failing trees

Each case was built in a throw-away copy of `Sources`, `scripts` and `PUBLIC_SURFACE.txt` under the scratchpad (never in the repo). Lesson L-002/L-004 (guard must fail on a bad input, test on the CI's OS) applied; the baseline also passes in `ubuntu:24.04`.

| Case | Expected | Result |
| --- | --- | --- |
| clean tree | pass | ✅ rc 0, 58 declarations |
| added `public func` (extension member) | fail | ✅ rc 1, diff printed |
| removed a listed symbol | fail | ✅ rc 1 |
| `public` -> `open` | fail | ✅ rc 1 |
| `public struct` in `NottiShared` | fail with its own message | ✅ rc 1, "public/open declaration in Sources/NottiShared" |
| `package` / `internal` / `var open` / `publicX` | pass (not matched) | ✅ rc 0 |
| `public` in an extension member, `public extension X {` block | fail | ✅ rc 1 (both) |
| multi-line `public func` added; parameter type changed in a listed one | fail | ✅ rc 1 (joined into one entry) |
| `public` inside `//`, `///` comment or a string | pass | ✅ rc 0 |
| `let s = "x"; public func ...` (same line after `;`) | fail | ✅ rc 1 |
| `public private(set) var`, `private(set) public var`, `public init/subscript/protocol/actor`, attributes `@available(...) public var`, `@objc(Foo) public class`, tab after `public` | fail | ✅ rc 1 |
| `public` in `NottiSDKExtension` | fail | ✅ rc 1 |
| missing `Sources/NottiSDKExtension` | fail loudly | ✅ rc 1, "expected directory not found" |
| `public` alone on its own line (then `func ...` / `final class ...` on the next) | fail | ❌ **rc 0 (not detected)**. Documented in the script header ("the code style keeps modifiers on the declaration line"); Note N3 |
| `@discardableResult public` then newline | fail | ❌ rc 0 (same, N3) |
| `/* c */ public func ...` | fail | ❌ rc 0 (starts like a comment line, N3) |
| attribute on its own line removed (`@available(iOSApplicationExtension, unavailable)` above `public enum Notti`) | fail (AC 2) | ❌ rc 0 and all 4 scripts green: **G3** |

---

## Code Quality

| Principle | Status |
| --- | --- |
| Minimum code / no scope creep | ✅ The facade is one-line forwards plus the four owned behaviors (idempotency, ensureCore, hub, main hop). `Notti.Options` is a public type not named in the spec's symbol list but implied by `initialize(appId:clientKey:options:)`; accepted |
| Surgical changes | ✅ `NottiRuntime.swift` is the only existing source file touched (+32/-2): `ensureCore`, the `core` doc, and the T6 retain-on-replace |
| AD-002 | ✅ `git diff main..HEAD --stat` over `Sources/NottiSDK/Core`, `Network`, `Storage`, `Events/NottiNotificationHandler.swift`, `Events/NottiEventBuffer.swift`, plus `NottiShared`, `NottiSDKExtension` and `NottiSDK.podspec`: empty. `NottiSubscription` and `NottiListenerHub` are new files |
| Extension safety | ✅ No new public/app-only API in `NottiShared` or `NottiSDKExtension` (surface script + diff); the public shell and ObjC classes are `@available(iOSApplicationExtension, unavailable)` (but see G3: nothing enforces it) |
| Public symbols match the spec list | ✅ `Notti`, `Notti.User`, `Notti.Notifications`, `Notti.Options`, `Notti.LogLevel` (typealias of `NottiLogLevel`/`NottiLogLevelObjC`), `NottiSubscription`, `NottiNotificationPayload`, and the ObjC classes `Notti`, `NottiUser`, `NottiNotifications` (Swift `NottiObjC`, `NottiUserObjC`, `NottiNotificationsObjC`). No `package` type in a public signature (compiles) |
| PII and attribution | ✅ No `Claude`/`Anthropic`/`Co-Authored-By` in the diff or in the 17 commit messages (`git log main..HEAD`). Diff fixtures are synthetic (`example.invalid`, `fixture`, `+10000000000`). Commit metadata carries only the author's own identity |
| Mutation-first lessons L-008..L-011 | ✅ L-008 (literal `notti_prefs`: R06/R07 killed), L-009 (sentinels on failure paths: `PR:302`; F09-F15 killed), L-010 (initial effective level through the facade: G_def killed), L-011 (each conjunct: F04/F05/F06, X3/X4/X5 killed). L-011/L-009 were applied to initialize but **not** to the pre-initialize profile methods (G1) |
| Documented guidelines | AGENTS.md (privacy/logging, extension safety, conventional commits, no attribution), `.specs/codebase/TESTING.md` |

---

## Findings

### Blocking (fix tasks)

| ID | Req | Gap | Evidence | Fix (verify with) |
| --- | --- | --- | --- | --- |
| G1 | API-07, DPF-17..21 | `setPhone`, `clearEmail`, `clearPhone` before `initialize` are not proven to go through `ensureCore()`. The only pre-initialize test (`FP:192`) calls `setEmail` first, which creates the core, so a later `runtime.core?.setPhone(...)` still works. `clearEmail`/`clearPhone` are never called before initialize | Mutants U15 (`NottiFacade.swift:136`), U16 (`:132`), U17 (`:140`): `runtime.ensureCore().X` -> `runtime.core?.X`, 332/332 pass | One test per method, each on a fresh runtime where that method is the **first** pre-initialize call (the spec's own Independent Test: "one test per method before `initialize`"): for `setPhone`, assert the value persists and is PATCHed at registration; for `clearEmail`/`clearPhone`, persist an email/phone first in the store, call clear, `initialize`, and assert the store is cleared and an explicit null is sent. Re-run U15-U17 |
| G2 | API-10 (SDK-17..19, SDKOPEN-10) | `Notti.Notifications.addClickedListener` could register on the `received` event and `PA:231` still passes: it emits `.received` and `.clicked` with the same payload and both assertions hold either way (the received listener also fires the mutated clicked listener, and the unmatched `.clicked` is simply buffered) | Mutant S06 (`Notti.swift:154`): `addClickedListener(handler)` -> `addReceivedListener(handler)`, all pass. The facade tests catch the same bug a layer below (L02 killed, B08 killed on the ObjC side) | In `PA:231`, emit a **clicked-only** event and assert the clicked listener fired and the received one did not, then the reverse. Re-run S06 |
| G3 | API-15 AC 2 | Nothing fails when `@available(iOSApplicationExtension, unavailable)` is removed from the public `Notti` enum (or from the ObjC classes). `NottiSDK` is not built with `APPLICATION_EXTENSION_API_ONLY`, `NottiSDKExtension` does not depend on it, the surface file only records the declaration line (the attribute sits on the line above), and `check-extension-safety.sh`/`check-package-graph.sh` look elsewhere | Mutant E1 (`Notti.swift:16`): attribute deleted -> 332/332 tests, all four scripts and `check-public-surface.sh` green (also run by hand on the mutated tree) | Make the surface script check it: for every top-level public type in `Sources/NottiSDK/Public` require the attribute (or record the preceding attribute line in `PUBLIC_SURFACE.txt`), and prove it fails on a tree without it. Alternative: a small test that compiles a sample with `-application-extension` is heavier; the script change is enough |

### Notes (non-blocking)

| ID | Severity | Note |
| --- | --- | --- |
| N1 | Medium | **Race edge case is not deterministically tested.** Removing `NottiFacade.lock` (F07) or `NottiRuntime.ensureCore`'s `lifecycleLock` (R09) leaves all tests green. `FI:205` (two racing different initializes) is probabilistic. It is an Edge Case in the spec, not an AC. Without the facade lock, two racing initializes could leave `_activeConfig = A` while the core is `B`, and a later `initialize(A)` would then be a silent no-op. Suggest a hook that parks the first `runtime.start` while the second initialize is issued (or a runtime stub that records start order) |
| N2 | Medium | **ObjC forwards not asserted for 5 entry points.** `NottiObjC.logout` (B12), `NottiUserObjC.setPhone` (B20), `clearEmail` (B21), `clearPhone` (B22), `removeTag` (B23) can become no-ops with every test green. API-13 AC 1 says "callable", which the `.m` compile-and-call tests satisfy, so it does not block; but a silent no-op from ObjC is user-visible (and the RN bridge will use these). Add the five to `OB:102-133` |
| N3 | Low | **Surface script blind spots**, documented in its header: `public` alone on a line, `@attr public` followed by a newline, and `/* c */ public func`. Today the code style keeps modifiers on the declaration line and SwiftLint does not enforce it. Consider a custom SwiftLint regex rule rejecting a line that is only a modifier, or `swift package diagnose-api-breaking-changes` on the macOS job. Related to G3 |
| N4 | Low | **ObjC test target uses the real production runtime** (`NottiRuntime.shared`, real `notti_prefs` suite) in the simulator: `OC` writes `user@example.invalid`/`+10000000000` and `setLocationSharingEnabled:NO` there and leaks state between tests and runs. Synthetic values only, simulator only; no LGPD impact. A suite wipe in `tearDown` would make it hermetic |
| N5 | Low | **`Notti.Options`** is a public struct that is not in the spec's symbol list (it is implied by `options:`). It is listed in `PUBLIC_SURFACE.txt`, so the change is visible. Mention it in the spec's symbol list for the record |
| N6 | Info | **H10 and H12 are an equivalent pair**: `NottiSubscription.remove()` nils its closure and `NottiListenerHub.remove(id:)` is itself idempotent; each guard hides the other. Removing both would double-detach. Not a gap; the closure held by the subscription captures only `weak hub` and an id, never the host handler, so "no strong reference to the handler after `remove()`" (spec edge case) holds by construction and `LH:217` proves the hub releases it |
| N7 | Info | `Notti.deviceId` and the listener APIs create `NottiRuntime.shared` (network path monitor, background observer) on first touch even before `initialize`. By design (`ensureCore`); mention in the README when written |

### F1 - Review of the T6 change in `NottiRuntime.invalidateCurrentCore` (retire-on-replace)

**What it does**: when `start` or `stop` replaces a core, the old core is invalidated (observers removed, heartbeat stopped) and then retained by a `DispatchQueue.global(qos: .utility).async { previous.waitForPendingWork(timeout: 60) }` so that blocks already queued on its serial `workQueue` (which capture `self` weakly) still run. It exists because `setEmail` before `initialize` queues work on the ensured core, and `initialize` then replaces that core.

**Assessment**: [Certo] the retention is necessary for the behavior the spec wants (API-07), and it is tested: removing it (R02), the `invalidate` (R05), `start`'s invalidate (R03), or shrinking the timeout to 0 (R08) each fail a test. No ported core file was edited (AD-002 holds). It is correct, with these residual risks:

| Risk | Severity | Analysis |
| --- | --- | --- |
| Utility thread pinned up to 60 s per replaced core | Low | `waitForPendingWork` enqueues a sentinel on the old core's serial queue and blocks a GCD worker until it runs. In the normal case the queue is short and the thread returns in milliseconds. It only pins for long when the old core is mid-HTTP with retry/backoff (blocking semaphore client), where the queue is genuinely busy |
| Repeated start/stop loops | Low-Medium | Identical `initialize` is a no-op (N1 closed), so a host must pass a *different* config each time to replace a core. Each replacement parks one worker for as long as the old queue is busy; GCD caps workers (~64), so a pathological loop of config switches against a dead network could starve the utility pool for up to 60 s per core. Not reachable in normal use (one process, one app id). `stop()` is internal |
| Memory | Low | One core (its `NottiApiClient`, stores' closures) is held for at most 60 s after replacement, then released. Negligible |
| Old core can still act after replacement | Low | Work queued on the old core (e.g. a PATCH or registration) runs with the **old** appId/clientKey and may fire `runtime.onDeviceIdChanged` for the old app into the new listeners (the callback is on the runtime, not the core). Acceptable for the pre-initialize `setEmail` case; surprising only for a deliberate config switch |
| Design alternative | Info | A cheaper way to get the same retention without pinning a thread: enqueue `previous.workQueue.async { _ = previous }` (a block that strongly captures the core and is released when it runs). It needs a small internal accessor on `NottiCore` (no ported behavior change). Not required for PASS |

**Recommendation**: keep as is for M1; record the alternative in STATE as a post-M1 todo. No fix task.

---

## Edge Cases (spec)

- [x] `initialize` from a background thread: same behavior (`FI:205` runs two concurrent initializes)
- [x] Listener registered before `initialize` works (`FL:138`)
- [~] Two racing initializes end with one consistent core (`FI:205` passes, but is not discriminating: N1)
- [x] `requestPermission` twice concurrently: both complete (`FM:192`)
- [x] Main-thread hop never reorders events for one listener (`LH:138`, H08/H09 killed)
- [x] Retained `NottiSubscription` after `remove()` holds no handler (N6, `LH:217`)
- [x] `http://` baseUrl follows the build rule (`FI:179`, Debug accepts, under `#if DEBUG`)

---

## Fix Plans

1. **G1**: add the three pre-initialize tests (see table). Kill U15-U17.
2. **G2**: strengthen `PA:231` with clicked-only and received-only emissions. Kill S06.
3. **G3**: make `check-public-surface.sh` (or a new script wired into `checks`) require the extension-unavailability attribute on public types and prove it against a tree without it. Kill E1.
4. Optional (Notes): N2 five ObjC forwards, N1 deterministic race test, N3 own-line `public`.

Max 3 fix-to-re-verify rounds apply; this is round 1.

---

## Requirement Traceability Update (for the orchestrator to apply to `spec.md`)

| Requirement | Previous | New |
| --- | --- | --- |
| API-01, 02, 03, 04, 05, 06, 08, 09, 11, 12, 14 | Implemented (Verifier pending) | ✅ Verified |
| API-07 | Implemented (Verifier pending) | ❌ Needs Fix (G1) |
| API-10 | Implemented (Verifier pending) | ❌ Needs Fix (G2) |
| API-13 | Implemented (Verifier pending) | ✅ Verified (Note N2) |
| API-15 | Implemented (Verifier pending) | ❌ Needs Fix (G3) |

---

## Summary

**Overall**: ❌ Not Ready (three small, local gaps).

**Spec-anchored check**: 12 of 15 requirements verified against code and tests with a killing mutant; API-07, API-10 and API-15 have an AC clause no test defends.
**Sensor**: 104/119 mutants killed; 14 survived (5 blocking in 3 gaps, 9 notes); 1 build-broken and redone.
**Gate**: 351 passed, 0 failed, SwiftLint 0, four scripts green (also on Linux), `pod lib lint` passed. CI not checkable (not pushed).

**What works**: initialize idempotency and invalid-argument handling (every clause of every guard killed), the listener hub (locks, ordering, attach/detach, recipient capture, no inline delivery), permission once/main-hop, log-level mapping (all six, both directions, initial effective value), payload mapping, the PII sentinels through the facade (including failure paths and the facade's own log lines), `notti_prefs` wiring, ObjC shape, AD-002 and extension-safety hygiene, the surface script on 24 trees including Linux.

**Issues found**: G1, G2, G3 above.

**Next steps**: implement the three fixes, re-run the 5 surviving blocking mutants (U15, U16, U17, S06, E1) plus the full gate, then round 2. Lessons to distil (`scripts/lessons.py`): (1) a pre-initialize test must make each method the *first* call, because an earlier call creates the core and hides the bug (extends L-011); (2) a shell-level "reaches the facade" test must emit one event type at a time, not all of them with one payload; (3) an attribute the spec requires on a public symbol needs a guard that reads the attribute, not only the declaration line (extends L-004).

</details>

---

## Round 2

### 2.1 The five round-1 blockers, re-run on `faa3c99`

Definitions are the exact round-1 ledger entries. Tests via the watchdog `run.sh`, class `NottiSDKTests/NottiFacadeProfileTests` or `NottiPublicApiTests`; E1 via the script.

| # | File:line | Mutation | Round 1 | Round 2 | Failing assertion / message |
| --- | --- | --- | --- | --- | --- |
| U15 | `Sources/NottiSDK/Facade/NottiFacade.swift:136` | `setPhone`: `runtime.ensureCore().setPhone` -> `runtime.core?.setPhone` | survived | ✅ killed | `NottiFacadeProfileTests.test_setPhoneAsTheFirstCallBeforeInitializePersistsAndIsSentAtRegistration` (`Tests/NottiSDKTests/NottiFacadeProfileTests.swift:225-239`: `XCTAssertEqual(store.getPhone(), "+10000000000")` and the PATCH contains the phone) |
| U16 | `NottiFacade.swift:132` | `clearEmail` -> `runtime.core?.clearEmail` | survived | ✅ killed | `test_clearEmailAsTheFirstCallBeforeInitializeClearsAndSendsExplicitNullAtRegistration` (`XCTAssertNil(store.getEmail())`, explicit `NSNull` PATCH) |
| U17 | `NottiFacade.swift:140` | `clearPhone` -> `runtime.core?.clearPhone` | survived | ✅ killed | `test_clearPhoneAsTheFirstCallBeforeInitializeClearsAndSendsExplicitNullAtRegistration` (`XCTAssertNil(store.getPhone())`, explicit `NSNull` PATCH) |
| S06 | `Sources/NottiSDK/Public/Notti.swift:154` | `addClickedListener` wired to `addReceivedListener` | survived | ✅ killed | `NottiPublicApiTests.test_receivedAndClickedListenersReachTheFacadeEachOnItsOwnEvent` (`Tests/NottiSDKTests/NottiPublicApiTests.swift:231-252`: `XCTAssertEqual(clicked.values, ["Clicked title fixture"])` / `received.values == []`) |
| E1 | `Notti.swift:16` | `@available(iOSApplicationExtension, unavailable)` removed from `public enum Notti` | survived | ✅ killed (by the script, not a test) | `scripts/check-public-surface.sh` exits 1: `error: public type without @available(iOSApplicationExtension, unavailable) (API-15 AC 2)`; same on macOS and `ubuntu:24.04` |

G1, G2 and G3 are closed.

### 2.2 Fresh code mutants (new tests and wiring)

Test mutants (ledger file `scratchpad/ledger2.tsv`): each run against the relevant class only; "first failing test" is the first `Test Case ... failed`. 26 mutants: **25 killed, 1 survived (B33, Note), 0 build-broken**. (The earlier crafting error of one E1 invocation with a wrong argument was a pattern error, nothing was applied.)

| # | File | Mutation | Result | First failing test | Class |
| --- | --- | --- | --- | --- | --- |
| V01 | `NottiFacade.swift` | `login` -> `runtime.core?.login` (first call before initialize) | ✅ killed | `NottiFacadeProfileTests.test_eachOtherPreInitializeCallAsTheFirstCallReachesEnsureCoreAndDoesNotCrash` (`XCTAssertNotNil(isolated.core)`, line 282) | - |
| V02 | `NottiFacade.swift` | `logout` -> `core?` | ✅ killed | same test | - |
| V03 | `NottiFacade.swift` | `addTags` -> `core?` | ✅ killed | same test | - |
| V04 | `NottiFacade.swift` | `removeTags` -> `core?` | ✅ killed | same test | - |
| V05 | `NottiFacade.swift` | `setSubscription` -> `core?` | ✅ killed | same test | - |
| V06 | `NottiFacade.swift` | `setLocationSharingEnabled` -> `core?` | ✅ killed | `test_locationSharingPreferenceIsWrittenBeforeTheCallReturns` | - |
| V07 | `NottiFacade.swift` | `deviceId` -> `core?.getDeviceId()` | ✅ killed | `test_deviceIdIsThePersistedIdBeforeInitialize` | - |
| V08 | `NottiFacade.swift` | `setEmail` -> `core?` | ✅ killed | `test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration` | - |
| W01 | `NottiRuntime.swift` | `ensureCore` builds a core but does not store it | ✅ killed | `test_clearEmailAsTheFirstCallBeforeInitializeClearsAndSendsExplicitNullAtRegistration` | - |
| W02 | `NottiRuntime.swift` | `ensureCore` never reuses the stored core | ✅ killed | `test_addTagsPatchesTheMergedMap` | - |
| W03 | `NottiFacade.swift` | `setEmail` calls `ensureCore()` but drops the call | ✅ killed | `test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration` | - |
| W04 | `NottiFacade.swift` | `clearPhone` calls `ensureCore()` but drops the call | ✅ killed | `test_clearEmailAndClearPhoneSendExplicitNull` | - |
| W05 | `NottiFacade.swift` | `setPhone` then `runtime.stop()` (core dropped after use) | ✅ killed | `test_clearEmailAndClearPhoneSendExplicitNull` | - |
| S10 | `Notti.swift` | shell `addReceivedListener` wired to clicked | ✅ killed | `NottiPublicApiTests.test_receivedAndClickedListenersReachTheFacadeEachOnItsOwnEvent` | - |
| S11 | `Notti.swift` | shell received listener fires twice | ✅ killed | same | - |
| S12 | `Notti.swift` | shell clicked listener fires twice | ✅ killed | same | - |
| S13 | `Notti.swift` | shell `addDeviceIdChangedListener` fires twice | ✅ killed | `test_deviceIdChangedListenerReachesTheFacadeAndCanBeRemoved` | - |
| S14 | `Notti.swift` | shell deviceId listener swallowed | ✅ killed | same | - |
| S15 | `Notti.swift` | shell received listener swallowed | ✅ killed | `test_receivedAndClickedListenersReachTheFacadeEachOnItsOwnEvent` | - |
| S20 | `Notti.swift` | shell `clearPhone` -> `clearEmail` | ✅ killed | `test_userEmailPhoneAndSubscriptionMethodsReachTheFacade` | - |
| S21 | `Notti.swift` | shell `setPhone` -> `setEmail` | ✅ killed | same | - |
| B30 | `NottiObjC.swift` | ObjC `addReceivedListener` wired to clicked | ✅ killed | `NottiObjCBridgeTests.test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt` | - |
| B31 | `NottiObjC.swift` | ObjC `addClickedListener` wired to received | ✅ killed | `NottiObjCBridgeTests.test_clickedListenerAndDeviceIdListenerReachTheFacade` | - |
| B32 | `NottiObjC.swift` | ObjC clicked listener fires twice | ✅ killed | same | - |
| B33 | `NottiObjC.swift:50` | ObjC `addDeviceIdChangedListener` fires twice | ❌ **SURVIVED** | - | Note (N8) |
| B34 | `NottiObjC.swift:50` | ObjC deviceId listener swallowed | ✅ killed | `test_clickedListenerAndDeviceIdListenerReachTheFacade` | - |

Observation on V01-V05: `test_eachOtherPreInitializeCallAsTheFirstCallReachesEnsureCoreAndDoesNotCrash` kills them only through `XCTAssertNotNil(isolated.core)`. That is enough for the wiring (each method is the first call on a fresh runtime, the exact G1 shape), but it does not assert the call's effect. The effect of login/logout/tags/subscription needs a registered device and is covered after initialize (round-1 U01-U04, U09, S02, S03).

### 2.3 The new G3 guard (`scripts/check-public-surface.sh`) against 32 cases

Method: each case is a new file `Sources/NottiSDK/Public/Extra.swift` (or an edit) in a throw-away copy of `Sources`, `scripts` and `PUBLIC_SURFACE.txt` under the scratchpad (never in the repo), the surface file refreshed with `--update` so that only the attribute check can fail, then the check on macOS and in `docker run --rm -v ... ubuntu:24.04` (mawk). macOS and Linux agreed on every case run on both (14 snippet cases, E1 and G3a-c).

Removing the attribute from each existing type, in the real tree:

| Case | Expected | Got (macOS / Linux) |
| --- | --- | --- |
| E1 `Notti` | fail | ✅ rc 1 / rc 1, "public type without @available(...)" |
| G3a `NottiObjC` | fail | ✅ rc 1 / rc 1 |
| G3b `NottiUserObjC` | fail | ✅ rc 1 / rc 1 |
| G3c `NottiNotificationsObjC` | fail | ✅ rc 1 / rc 1 |

New declarations (surface file kept in sync):

| Case | Expected | Got |
| --- | --- | --- |
| `public struct` without attribute | fail | ✅ fail |
| `public protocol`, `public final class`, `public enum`, `public actor`, `public class`, `open class` (6 cases) | fail | ✅ all fail |
| generic `public struct Box<T>`, `public final  class   Spaces` (extra spaces), `@MainActor public struct`, `public struct X: Sendable`, inside `#if DEBUG` | fail | ✅ all fail |
| attribute above a **different** type (`A1` marked, `B1` not) | fail | ✅ fail |
| attribute above a `public func`, then an unmarked type | fail | ✅ fail |
| attribute above a `public typealias`, then an unmarked type | fail | ✅ fail |
| three types, attribute above 1st and 2nd only | fail | ✅ fail (3rd named) |
| blank line between attribute and type | fail | ✅ fail (strict, documented) |
| `//` comment between attribute and type | fail | ✅ fail (stricter than Swift, documented) |
| `@available(iOS 15, *)` instead of the extension-unavailable form | fail | ✅ fail |
| type whose name is the allowlisted name plus a suffix (`NottiSubscriptionX`) | fail | ✅ fail (exact-token match) |
| attribute on the same line (`@available(...) public struct`) | pass | ✅ pass |
| `@available(iOS 15, *)` plus the extension attribute | pass | ✅ pass |
| attribute, `@objc(Foo)` line, then the type; attribute then `@objc(Foo) public final class` | pass | ✅ pass (both) |
| `///` doc comment above the attribute | pass | ✅ pass |
| nested `public struct` inside an `extension` (indented) | pass (top-level only, documented) | ✅ pass |

**Findings against the guard** (none blocks: no type that exists today is affected, and AC 2 holds for every type in the tree, proven by E1 and G3a-c):

| ID | Case | Behavior | Severity |
| --- | --- | --- | --- |
| N9 | `public indirect enum X` | not matched by the type regex (`indirect` is not in the modifier list): **false pass**, with or without the attribute. No such type exists today | Low |
| N10 | `public struct X {} // @available(iOSApplicationExtension, unavailable)` | the attribute text inside a trailing comment satisfies the check: **false pass**. Contrived | Info |
| N11 | top-level `public func` / `public let` / `public extension` (not a type) that reads `NottiFacade.shared` | the check is for types only: **false pass**. Nothing like it exists (`grep` of unindented non-type `public` in `Sources/NottiSDK` is empty). The spec's AC 2 says "app-only API", so a top-level free function would be in scope; the surface-file diff still forces a reviewer to see it | Low |
| N12 | `@available(iOSApplicationExtension, unavailable, message: "...")` | **false fail** (exact string match): stricter than needed; a contributor would add the plain form or allowlist it | Info |
| N3 (r1) | `public` alone on a line, then `struct X` | still not matched by either the surface scan or the attribute check (58 declarations, rc 0). Unchanged from round 1; documented in the script header | Low |
| N13 | a type added to `ext_safe_types` in the script | **passes silently**, no test or script notices (`git grep` shows only `ci.yml` and the script reference it). Only a reviewer reading the script diff sees it. By design (the allowlist is the escape hatch, documented in the script and AGENTS.md); mitigation: CODEOWNERS or a review checklist line | Low |

The script also still passes on `ubuntu:24.04` for the real tree (58 declarations).

### 2.4 Round-1 Notes that were deliberately not fixed

| Note | Re-check | Changed? |
| --- | --- | --- |
| F07 (facade `lock` removed in `initialize`) | re-run against `NottiFacadeInitializeTests`: survived | No. Note N1 stands (Medium; spec Edge Case, not an AC) |
| R09 (`ensureCore` without `lifecycleLock`) | re-run against Runtime, Profile and Initialize tests: survived | No. N1 stands |
| B12 (ObjC `logout`), B20 (`setPhone`), B21 (`clearEmail`), B22 (`clearPhone`), B23 (`removeTag` singular) | re-run against `NottiObjCBridgeTests` + `NottiSDKObjCTests`: all 5 survived (the plural `removeTags` forward is killed) | No. N2 stands. B33 (new, same family) adds the ObjC deviceId observer's call count. API-13 AC 1 says "callable", which the `.m` compile-and-call tests prove; Medium Note, not blocking |
| T6 retire-on-replace (`NottiRuntime.invalidateCurrentCore`) | `git diff e31812b..HEAD -- Sources` is empty, so the F1 analysis (60 s worker pin, old core can still act on old config, alternative `workQueue.async { _ = previous }`) is unchanged. The new `W01`/`W02`/`W05` runtime mutants around `ensureCore` are killed | No. Keep as a post-M1 todo |
| N3 script blind spots | see N3/N9-N13 above: the round-1 blind spots remain, two new ones (`indirect`, non-type `public`) recorded | Slightly widened inventory, none violates an AC |
| N4, N5, N6, N7 | no source or test change since round 1 | No |

### 2.5 Gates (unmodified tree, HEAD `faa3c99`)

| Gate | Result |
| --- | --- |
| Full test run via the watchdog, `NBUNDLES=4` (log `pv2_full.log`) | ✅ `** TEST SUCCEEDED **`; all four bundles "passed": `NottiSharedTests` 14, `NottiSDKTests` 337, `NottiSDKObjCTests` 4, `NottiSDKExtensionTests` 1 = **356**, 0 failures; 356 `Test Case ... passed` lines. Round 1 was 351: +5 (the five new G1 tests; the G2 test was rewritten in place) |
| SwiftLint `0.65.1 --strict` (Docker) | ✅ 0 violations, 0 serious, 57 files |
| `check-version.sh && check-extension-safety.sh && check-package-graph.sh && check-public-surface.sh` | ✅ `version ok: 0.1.0`, `extension safety ok`, `package graph ok`, `public surface ok (58 declarations)` |
| `check-public-surface.sh` in `ubuntu:24.04` | ✅ `public surface ok (58 declarations)` |
| `pod lib lint NottiSDK.podspec --platforms=ios` | ✅ `NottiSDK passed validation.` (only AppIntents metadata NOTEs) |
| `validate_spec.py` | ✅ 0 errors, 0 warnings |
| `validate_tasks.py` | ✅ 0 errors, 11 warnings (same granularity smells as round 1; accepted) |
| `validate_state.py public-api` | ✅ exit 0 (run after this report was written) |
| CI (`.github/workflows/ci.yml`) | ⚠️ Not verifiable: the branch is not pushed. Read instead: the step `Public API surface (API-15)` (`.github/workflows/ci.yml:45-47`) is in the `checks` job (`ubuntu-24.04`, after the version and extension-safety steps); the `test` job runs the whole `NottiSDK-Package` scheme, which includes the ObjC target |

Test integrity: the only test-file changes since round 1 are in `NottiFacadeProfileTests.swift` (+79, tests added) and `NottiPublicApiTests.swift` (+27/-13: the one G2 test rewritten and strengthened, with both directions asserted). No test was deleted or weakened; the count rose from 351 to 356.

### 2.6 AD-002, PII, attribution

- AD-002: `git diff main..HEAD --stat` over `Sources/NottiSDK/Core`, `Network`, `Storage`, `Events/NottiEventBuffer.swift`, `Events/NottiNotificationHandler.swift`, `Sources/NottiShared`, `Sources/NottiSDKExtension` and `NottiSDK.podspec` is empty. The only existing source file touched on the branch is `Sources/NottiSDK/Runtime/NottiRuntime.swift` (+32/-2, `ensureCore` and retire-on-replace, reviewed in round 1 F1). Sources are byte-identical to round 1.
- PII: the new tests use synthetic values only (`user@example.invalid`, `+10000000000`, `user-fixture`, `*fixture*` titles). A scan of the round-1 fix diff for emails/phones finds only those.
- Attribution: no `Claude`, `Anthropic` or `Co-Authored-By` in the 22 commit messages. A text scan of the whole diff matches three lines that are not attribution: the path `.claude/skills/` in `tasks.md`, the round-1 report's own description of this check, and a pre-existing sentence in `AGENTS.md` context ("Claude Code, Codex, Cursor").

### 2.7 Findings

**Blocking**: none.

**Notes (new in round 2)**

| ID | Severity | Note |
| --- | --- | --- |
| N8 | Medium | **ObjC `addDeviceIdChangedListener` call count is not asserted.** B33 (the ObjC forward wraps the handler so it fires twice) passes `NottiObjCBridgeTests.test_clickedListenerAndDeviceIdListenerReachTheFacade`, which reads `ids.values.first` (`Tests/NottiSDKTests/NottiObjCBridgeTests.swift:157-173`) and never `count`. The same property is proven for the Swift shell (S13 killed) and the facade (L03/L04), so it is a ObjC-layer pass-through. Same family as N2. One-line fix: `XCTAssertEqual(ids.values.count, 1)` |
| N9-N13 | Low/Info | G3 guard blind spots, see 2.3 |
| N14 | Low | **`traceability.md` is stale for round 2**: it still says 332 / 351 tests and "Independent Verifier pending", and its API-07/API-10/API-15 rows do not name the G1/G2/G3 tests or the new guard clause (see recommendations) |
| N15 | Info | `test_eachOtherPreInitializeCallAsTheFirstCallReachesEnsureCoreAndDoesNotCrash` asserts only that the core exists (see 2.2 observation) |

Round-1 Notes N1-N7 stand (2.4).

### 2.8 Lessons (not written to `LESSONS.md`; for the orchestrator to distil)

L-012..L-014 from round 1 were applied correctly: each pre-initialize method is the first call on a fresh runtime (U15-U17, V01-V08 killed), the shell test emits one event type at a time with distinct payloads (S06, S10-S12, S15 killed), and the surface guard reads the attribute (E1, G3a-c killed). Candidates:

1. **A mutation of a guard script must include "false pass" inputs from the grammar, not only the removal of what exists today.** The new attribute check handles the shapes in use but misses `public indirect enum`, a non-type `public`, and an attribute inside a trailing comment. When a guard is textual, enumerate the declaration keywords and modifiers of the language (Swift: `indirect`, `final`, `actor`, `@frozen`, free functions) and run them as negative fixtures (extends L-004 and L-014).
2. **A forwarding layer test must assert the call count (`count == 1`), not `first`.** B33 survives because the ObjC test reads `.first`; the same pattern let the pre-fix S06 pass. Assert `count`, and make each event/entry point distinguishable (extends L-013).
3. **A "reaches the core" assertion that only checks the core exists is a weak oracle**: pair it with an observable effect when the call can be made to produce one (N15).

### 2.9 Traceability status recommendations (for the orchestrator; spec.md/tasks.md are not edited by the Verifier)

| Requirement | Previous (after round 1) | New |
| --- | --- | --- |
| API-01, 02, 03, 04, 05, 06, 08, 09, 11, 12, 14 | ✅ Verified | ✅ Verified (unchanged) |
| API-07 (and DPF-17..21) | ❌ Needs Fix (G1) | ✅ Verified (U15-U17 and V01-V08, W01-W05 killed) |
| API-10 (SDK-17..19, SDKOPEN-10) | ❌ Needs Fix (G2) | ✅ Verified (S06, S10-S15, B30-B32 killed) |
| API-13 | ✅ Verified (Note N2) | ✅ Verified (Notes N2, N8) |
| API-15 | ❌ Needs Fix (G3) | ✅ Verified (E1, G3a-c killed; guard Notes N9-N13) |

Also update `traceability.md` section 4 (counts to 14 / 337 / 4 / 1 = 356) and its API-07/API-10/API-15 rows (N14).

### 2.10 Summary

**Overall**: ✅ Ready (PASS, round 2).

**Spec-anchored check**: 15 of 15 requirements have a test (or, for the attribute clause of API-15, a script) that fails when the behavior is wrong; the round-1 gaps G1, G2 and G3 are closed and each re-run blocker is killed.
**Sensor**: round 2 total 26 fresh test mutants (25 killed, 1 survived as a Note, 0 build-broken), 5 round-1 blockers killed, 7 round-1 Notes re-run (7 survived, unchanged), plus 4 script mutants (killed) and 32 guard-input cases (4 false passes, 1 false fail, none blocking).
**Gate**: 356 passed, 0 failed, SwiftLint 0, four scripts green (also on Linux), `pod lib lint` passed. CI not checkable (not pushed).
**Next steps**: optional Notes (N8 one-line assertion, N2 ObjC forwards, N1 race test, N9-N13 guard hardening, N14 traceability refresh). Ready for the pull request; CI will be the first real run of the `checks` job on Linux.

### Closing check

`python3 .claude/skills/tlc-spec-driven/scripts/validate_state.py public-api` after writing this report: `0 error(s) across [public-api]`, exit 0. `git status` shows only this file modified; `git diff` over `Sources`, `Tests` and `scripts` is empty.
