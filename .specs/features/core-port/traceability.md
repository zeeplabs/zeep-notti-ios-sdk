# Core Port Traceability

**Spec**: `.specs/features/core-port/spec.md` (CORE-06, CORE-07, CORE-08)
**RN baseline**: `react-native-notti` `52e4b55`, specs in `../zeep-notti-react-native/.specs/features/*/spec.md`
**Status**: Written in T13 (2026-10-10). Independent Verifier pending.

Test references use `Class.test_name`. Classes: `Core` = `NottiCoreTests`, `Api` = `NottiApiClientTests`, `DS` = `NottiDeviceStoreTests`, `ES` = `NottiEventStoreTests`, `EB` = `NottiEventBufferTests`, `NO` = `NottiNetworkObserverTests`, `RT` = `NottiRuntimeTests`, `NH` = `NottiNotificationHandlerTests`, `LP` = `NottiLoggingPrivacyTests`, `CT` = `NottiContinuityTests`, `Parse` = `NottiNotificationParsingTests` (NottiSharedTests). All are in `Tests/NottiSDKTests/` except `Parse`.

Where an RN story's ACs are covered by one group of tests, the row lists the tests that assert that specific AC; a test may appear under several IDs.

---

## 1. RN requirement → tests here

### sdk-core-v1 (SDK-01..19)

| RN ID | Behavior | Tests here | Status |
| --- | --- | --- | --- |
| SDK-01 | `initialize` gets the token and `POST`s `{token, platform}` with `Bearer` | `Core.test_initializeHappyPathRegistersTheDeviceAndPersistsIdAndTags`, `Api.test_createOrUpdateDeviceSendsPostWithCorrectHeadersAndBody`, `Core.test_initializeWithAnAsyncTokenFetchThatResolvesLaterStillRegistersOnceTheTokenArrives`, `RT.test_onApnsTokenConvertsBytesToLowercaseHexAndRegistersWithIt` | Covered |
| SDK-02 | Persist device id, cache tags | `Core.test_initializeHappyPathRegistersTheDeviceAndPersistsIdAndTags`, `Core.test_initializeHappyPathExposesThePersistedIdViaGetDeviceId`, `DS.test_deviceIdAndLastTokenRoundTripThroughUserDefaults`, `DS.test_setTagsPersistsAndGetTagsReturnsTheAddedTags` | Covered |
| SDK-03 | Missing/invalid config: log, no crash, no registration | `Core.test_initializeWithBlankAppIdLogsAndDoesNotCallTheApiClient`, `Core.test_initializeWithBlankClientKeyLogsAndDoesNotCallTheApiClient`, `Core.test_initializeWithBlankBaseUrlLogsAndDoesNotCallTheApiClient`, `Core.test_initializeWithAMalformedBaseUrlDoesNotCrashAndDoesNotRegister`, `Core.test_initializeWithAMalformedBaseUrlLeavesLaterMutationsInertRatherThanCrashing`, `Api.test_validatedBaseUrlAcceptsAbsoluteHttpUrlsAndRejectsEverythingElse`, `Api.test_anUnusableBaseUrlFailsTheCallInsteadOfCrashing` | Covered |
| SDK-04 | Missing native push prerequisite: log, no crash (RN: ❌ Needs Fix) | Core layer (CORE-08): `RT.test_onApnsRegistrationFailedLogsDomainAndCodeWithoutRegisteringAndTheCoreStaysUsable` (APNs failure callback logged as `domain#code`, no registration, core still registers later), `Core.test_initializeWithNoAvailablePushTokenLogsAndDoesNotRegister`, `Core.test_initializeWithAnAsyncTokenFetchThatFailsDoesNotCrashAndDoesNotAttemptRegistration`. The real "no `aps-environment` entitlement" device path → `example-and-release` (needs a signed app) | Covered (core layer); device path moved |
| SDK-05 | Retry 5x with backoff, then stop until foreground / token refresh | `Api.test_5xxResponsesExhaustTheRetryCapAtExactlyFiveAttempts`, `Api.test_networkErrorIsRetriedPerTheSameBackoffSchedule`, `Api.test_5xxResponseRetriesThenSucceedsWithoutExhaustingTheCap`, `Api.test_aSuccessfulResponseBeforeTheRetryCapStopsFurtherRetries`, `Core.test_registrationThatExhaustedItsRetryCapIsRetriedOnTheNextAppForeground`, `Core.test_aSuccessfulRegistrationIsNotRepeatedOnEveryForeground`, `Core.test_foregroundsArrivingWhileARegistrationIsInFlightDoNotPileUpExtraAttempts` | Covered |
| SDK-06 | Token refresh re-registers via the same upsert | `Core.test_onTokenRefreshedReRegistersWithTheNewToken`, `RT.test_onApnsTokenConvertsBytesToLowercaseHexAndRegistersWithIt`, `CT.test_sameTokenReRegistrationKeepsTheRnDeviceIdAndSkipsTheAckMigration`. OS callback wiring → `delegate-integration` | Covered (core); OS hook moved |
| SDK-07 | Repeat `initialize` with identical args is a no-op | `Core.test_repeatInitializeWithIdenticalArgsIsANoOp` | Covered |
| SDK-08 | `requestPermission` triggers the OS prompt | `Core.test_requestPermissionGrantPathInvokesTheNativePromptAndPatchesSubscribedTrue` (injected requester). The real `UNUserNotificationCenter.requestAuthorization` closure is `NottiPlatformProviders.live()` (build-verified, T8); facade in `public-api` | Covered (core); OS prompt build-only |
| SDK-09 | Grant → `PATCH {subscribed: true, token}` | `Core.test_requestPermissionGrantPathInvokesTheNativePromptAndPatchesSubscribedTrue`, `Core.test_permissionGrantedBeforeTheApnsTokenArrivesStillPatchesSubscribedAfterRegistration` | Covered |
| SDK-10 | Deny → `PATCH {subscribed: false, token}` | `Core.test_requestPermissionDenyPathPatchesSubscribedFalse` | Covered |
| SDK-11 | Android < 13 resolves granted without prompting | — | N/A: Android-only |
| SDK-12 | `addTag(s)` merges into the cache and PATCHes the full map (RN iOS: indirect evidence only) | Direct (CORE-08): `RT.test_addTagsThroughTheRuntimeCorePatchesTheFullMergedMap` (registration tags + add → full merged map in PATCH and cache; non-string value dropped by `sanitizeTags`). Also `Core.test_tagsAddedBeforeTheApnsTokenArrivesAreSentOnceRegistrationCompletes`, `DS.test_mergeTagsAddsRemovesAndLastOperationWinsOnOverlappingAddPlusRemove`, `RT.test_sanitizeTagsKeepsOnlyStringKeysWithStringValues` | Covered (gap closed) |
| SDK-13 | `removeTag(s)` removes from the cache and PATCHes the full map (RN iOS: indirect evidence only) | Direct (CORE-08): `RT.test_removeTagsThroughTheRuntimeCorePatchesTheRemainingMap`. Also `DS.test_setTagsWithAKeyRemovedFromAPriorCallIsNoLongerPresent`, `DS.test_mergeTagsAddsRemovesAndLastOperationWinsOnOverlappingAddPlusRemove` | Covered (gap closed) |
| SDK-14 | `login` → `PATCH {external_user_id, token}` | `Core.test_loginPatchesExternalUserIdAndTheCachedTokenAndPersistsItLocallyOnSuccess`, `Core.test_loginBeforeTheApnsTokenArrivesIsSentOnceRegistrationCompletes` | Covered |
| SDK-15 | `logout` clears the local association only | `Core.test_logoutClearsTheExternalUserIdLocallyOnlyAndEnqueuesEmailAndPhoneNullClears`, `Core.test_logoutBeforeInitializeClearsLocallyAndResendsTheNullsAtRegistration` | Covered |
| SDK-16 | `setSubscription` → `PATCH {subscribed, token}` | `Core.test_setSubscriptionPatchesTheGivenSubscribedValueAndTheCachedTokenAndPersistsItLocallyOnSuccess` | Covered |
| SDK-17 | Foreground push emits `notificationReceived` with the payload (RN: emission wiring untested) | Core layer (CORE-08): `NH.test_willPresentEmitsTheParsedPayloadToTheReceivedHandlerOnlyForARemotePush`, `EB.test_eventsEmittedWhileAnEmitterIsAttachedGoStraightThroughInOrder`, `EB.test_aBufferedReceivedEventIsStillReplayedWhenItsEmitterAttaches`, `Parse` (6 tests). JS/listener surface → `public-api` | Covered (core); facade moved |
| SDK-18 | Tap emits `notificationClicked` (incl. cold start) | `NH.test_bodyTapEmitsOneClickToTheAttachedHandlerAndDismissEmitsNothing`, `NH.test_didReceiveDefaultActionStillBuffersTheClickForAColdStart`, `EB.test_aColdStartClickIsHandedOverByThePullAndNotEmittedWhenTheEmitterAttaches`, `EB.test_theColdStartClickIsConsumedSoASecondPullGetsNothing`, `EB.test_aPulledClickIsNeverAlsoDeliveredAsAnEvent`. Listener surface → `public-api` | Covered (core) |
| SDK-19 | Mutations serialized, last-write-wins | `Core.test_twoRapidTagMutationsSerializeAndConvergeToTheCorrectNetMergedResult`, `Core.test_mutationsQueuedBeforeRegistrationAreFlushedInCallOrder`, `Core.test_aRegistrationLandingDuringAnInFlightAddTagsCannotClobberTheMergedTags` | Covered |

### ctr-event-reporting (SDKCTR-01..14)

| RN ID | Behavior | Tests here | Status |
| --- | --- | --- | --- |
| SDKCTR-01 | Body tap with ids is reported (now `opened` + `clicked`) | `NH.test_didReceiveDefaultActionWithIdsEnqueuesExactlyOneOpenedAndOneClicked`, `Api.test_reportEventSendsPostWithCorrectPathHeadersAndBody`, `Core.test_registrationSuccessFlushesAQueuedEventAndRemovesIt` | Covered |
| SDKCTR-02 | Cold-start tap still reported | `NH.test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration` (CORE-04), `NH.test_didReceiveDefaultActionStillBuffersTheClickForAColdStart` | Covered |
| SDKCTR-03 | Custom action → `clicked` only; dismiss → nothing | `NH.test_didReceiveCustomActionEnqueuesOneClickedEventAndNoOpened`, `NH.test_didReceiveDismissActionSkipsEnqueueEvenWithIds` | Covered |
| SDKCTR-04 | No ids → skip silently | `NH.test_willPresentWithoutIdsSkipsEnqueue`, `NH.test_willPresentWithAnEmptyIdSkipsEnqueue`, `NH.test_didReceiveDefaultActionWithoutIdsSkipsEnqueue`, `NH.test_didReceiveCustomActionWithoutIdsSkipsEnqueue` | Covered |
| SDKCTR-05 | Foreground `willPresent` reports `received` | `NH.test_willPresentWithNotificationAndDeliveryIdsEnqueuesAReceivedEvent`, `NH.test_eventHandledWithARegisteredCoreIsFlushedRightAway` | Covered |
| SDKCTR-06 | No `received` expected in background/killed | Scope statement: the only `received` source is `handleWillPresent` (foreground). `NH.test_willPresentForANonRemotePushSkipsEnqueueEvenWithIds` bounds the entry point. Background `received` from the NSE is a deferred idea (STATE) | Covered (scope); no behavior to test |
| SDKCTR-07 | Network/5xx retried 5x with backoff | `Api.test_reportEvent5xxResponsesExhaustTheRetryCapAtExactlyFiveAttempts`, `Api.test_networkErrorIsRetriedPerTheSameBackoffSchedule` | Covered |
| SDKCTR-08 | 4xx terminal except 408/429 | `Api.test_reportEventTreatsA4xxAsTerminalWithoutRetrying`, `Api.test_reportEvent408And429AreTransientRetriedAndNonTerminal`, `Api.test_patch429ThenSuccessIsRetriedAndSucceeds` | Covered |
| SDKCTR-09 | Exhausted retries → stays queued | `Api.test_reportEvent5xxExhaustionIsNonTerminal`, `Core.test_flushEventQueueKeepsTheEventWhenReportingFails` | Covered |
| SDKCTR-10 | Write-ahead persistence | `ES.test_freshStoreOverSameDefaultsSeesPreviouslyEnqueuedEvents`, `ES.test_enqueueReturnsTheRecordAndAllContainsIt`, `NH.test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration` (persisted with no core) | Covered |
| SDKCTR-11 | Removed on 2xx or terminal 4xx | `Core.test_registrationSuccessFlushesAQueuedEventAndRemovesIt`, `Core.test_flushEventQueueDropsTheEventOnATerminal4xxReport`, `ES.test_removeDropsTheRecordFromAll` | Covered |
| SDKCTR-12 | Flush on launch | `Core.test_appForegroundFlushesTheEventQueueEvenWhenAlreadyRegistered`, `Core.test_flushEventQueueBeforeInitializeIsANoOpAndKeepsTheEvent`, `CT.test_rnStateIsAdoptedWithoutRegistrationAndItsPendingEventsFlush` | Covered |
| SDKCTR-13 | Flush on reconnect | `NO.test_transitionToSatisfiedTriggersAFlush` (+3 NO tests), `Core.test_onNetworkAvailableFlushesAQueuedEventAfterRegistration`, `RT.test_networkObserverStartedByTheRuntimeFlushesQueuedEventsOnReconnect` | Covered |
| SDKCTR-14 | Duplicate flush tolerated | `Core.test_aBurstOfFlushTriggersSchedulesASingleFlush`, `Core.test_flushStopsAtTheFirstTransientFailureInsteadOfRetryingEveryEvent` | Covered |

### opened-event-reporting (SDKOPEN-01..11)

| RN ID | Behavior | Tests here | Status |
| --- | --- | --- | --- |
| SDKOPEN-01 | Body tap → `opened` | `NH.test_didReceiveDefaultActionWithIdsEnqueuesExactlyOneOpenedAndOneClicked` | Covered |
| SDKOPEN-02 | Cold-start body tap → `opened` | `NH.test_didReceiveDefaultActionStillBuffersTheClickForAColdStart`, `NH.test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration` | Covered |
| SDKOPEN-03 | Body tap also reports `clicked`; URL in data changes nothing | `NH.test_didReceiveDefaultActionWithIdsEnqueuesExactlyOneOpenedAndOneClicked`, `NH.test_didReceiveDefaultActionWithAURLInDataEnqueuesTheSameOpenedAndClickedPair` | Covered |
| SDKOPEN-04 | One pair per tap | `NH.test_eachDefaultActionResponseEnqueuesItsOwnOpenedAndClickedPair` | Covered |
| SDKOPEN-05 | Custom action → `clicked` only | `NH.test_didReceiveCustomActionEnqueuesOneClickedEventAndNoOpened` | Covered |
| SDKOPEN-06 | Dismiss → no event | `NH.test_didReceiveDismissActionSkipsEnqueueEvenWithIds`, `NH.test_bodyTapEmitsOneClickToTheAttachedHandlerAndDismissEmitsNothing` | Covered |
| SDKOPEN-07 | Custom action → no click event | `NH.test_didReceiveCustomActionDoesNotBufferAClick` | Covered |
| SDKOPEN-08 | Skip without ids / non-remote push | `NH.test_didReceiveDefaultActionWithoutIdsSkipsEnqueue`, `NH.test_didReceiveCustomActionWithoutIdsSkipsEnqueue`, `NH.test_didReceiveCustomActionForANonRemotePushSkipsEnqueueEvenWithIds`, `NH.test_didReceiveNonRemotePushSkipsEnqueueEvenWithIds`, `NH.test_willPresentForANonRemotePushSkipsEnqueueEvenWithIds` | Covered |
| SDKOPEN-09 | `opened` uses the same queue/retry/flush, `type: "opened"` | `Core.test_aQueuedOpenedEventIsFlushedWithTypeOpenedAndRemovedOn2xx`, `NH.test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration` | Covered |
| SDKOPEN-10 | JS events unchanged for body tap | Core part: `NH.test_bodyTapEmitsOneClickToTheAttachedHandlerAndDismissEmitsNothing`. JS event names → `public-api` | Covered (core); JS part moved |
| SDKOPEN-11 | README + CHANGELOG | — | N/A here: docs → `example-and-release` |

### segment-telemetry-reporting (SEGTEL-01..15)

| RN ID | Behavior | Tests here | Status |
| --- | --- | --- | --- |
| SEGTEL-01 | App version read once at init | `Core.test_appVersionDiffOnRegistrationEnqueuesAPatchWithTheVersion` (injected `versionProvider`; the `CFBundleShortVersionString` read is `live()`, build-only) | Covered |
| SEGTEL-02 | App version in the registration/flush payload | `Core.test_appVersionDiffOnRegistrationEnqueuesAPatchWithTheVersion` | Covered |
| SEGTEL-03 | Diff-and-enqueue on change | `Core.test_appVersionEqualToTheLastSyncedValueDoesNotPatchAgain`, `Core.test_aBumpedVersionBetweenTwoRegistrationsResyncsWithTheNewValue` | Covered |
| SEGTEL-04 | Missing version → skip, no crash | `Core.test_aNilVersionProviderSkipsTheSyncEntirely` | Covered |
| SEGTEL-05 | Session start; `first_session_at` set once | `Core.test_sessionStartThenEndIncrementsCountAddsElapsedTimeAndPatchesTheSnapshot`, `Core.test_firstSessionAtIsSetOnceAndNeverOverwritten`, `Core.test_aCoreCreatedWhileTheAppIsAlreadyActiveOpensTheColdStartSession` | Covered |
| SEGTEL-06 | Session end: count +1, time added | `Core.test_sessionStartThenEndIncrementsCountAddsElapsedTimeAndPatchesTheSnapshot`, `Core.test_sessionEndWithNoActiveSessionIsANoOp`, `Core.test_sessionEndUsesTheBackgroundTimestampEvenWhenTheWorkQueueIsBusy` | Covered |
| SEGTEL-07 | Snapshot PATCH per session end; telemetry coalesced before registration | `Core.test_sessionStartThenEndIncrementsCountAddsElapsedTimeAndPatchesTheSnapshot`, `Core.test_queuedTelemetryIsCoalescedToTheLatestSnapshotPerKey`, `Core.test_coalescedTelemetryNeitherCountsAgainstNorEvictsQueuedUserMutations` | Covered |
| SEGTEL-08 | Unclean kill closed at the last heartbeat (24h cap, `notti_session_last_seen_at_ms`); reload adopts the open session | `Core.test_uncleanKillIsClosedAtTheLastKnownForegroundTimestampAtTheNextSessionStart`, `Core.test_anOrphanedSessionWithoutAHeartbeatIsCountedWithZeroDurationNotInflated`, `Core.test_aCoreRecreatedByAJsReloadWhileForegroundAdoptsTheOpenSessionInsteadOfClosingIt`, `Core.test_anOpenSessionLeftByAKilledProcessIsStillClosedAsAnOrphanOnColdStart`, `RT.test_startTwiceInvalidatesTheFirstCoreAndTheSecondAdoptsTheOpenSession`, `CT.test_rnStateIsAdoptedWithoutRegistrationAndItsPendingEventsFlush` | Covered |
| SEGTEL-09 | Heartbeat / no session in background | `Core.test_theHeartbeatTimerPersistsTheLastForegroundTimestampAndStopsOnBackground`, `Core.test_aCoreCreatedInBackgroundDoesNotOpenASession`, `Core.test_anInvalidatedCoreThatIsStillAliveNoLongerReactsToLifecycle`, `RT.test_backgroundObserverClosesTheSessionGateWithoutACore` | Covered |
| SEGTEL-10 | Opt-in toggle, off by default | `Core.test_locationSharingOffNeverReadsCountryEvenWithPermissionGranted`, `DS.test_telemetryFieldsDefaultToDisabledAndZeroForANeverInitializedStore`, `Core.test_setLocationSharingEnabledPersistsImmediatelyEvenWhileTheWorkQueueIsBusy` | Covered |
| SEGTEL-11 | Read country at session start when enabled + permission | `Core.test_locationSharingOnWithPermissionAndAReadSendsCountryOnSessionStart`, `Core.test_anUnchangedCountryIsNotPatchedAgainAndReadsAreThrottled` | Covered |
| SEGTEL-12 | Omit country when disabled / no permission / nil read | `Core.test_locationSharingOnWithoutOSPermissionNeverReadsCountry`, `Core.test_aNilCountryReadOmitsTheFieldWithoutCrashing`, `Core.test_aCountryReadResolvingAfterAnOptOutIsNotWritten` | Covered |
| SEGTEL-13 | Opt-out enqueues a persisted country clear until 2xx | `Core.test_disablingLocationSharingEnqueuesAnExplicitCountryClear`, `Core.test_optOutBeforeInitializeStillClearsCountryOnceRegistrationCompletes`, `Core.test_aCountryClearThatFailsOfflineOr5xxStaysPendingUntilA2xx`, `Core.test_aCountryClearRejectedWithAPermanent4xxLogsDistinctlyAndStaysPending`, `Core.test_aTransientClearFailureKeepsTheGenericLog`, `Core.test_reOptInAfterAFailedClearForgetsTheSyncedCountryAndResendsIt`, `Core.test_optOutWithoutAPriorOptInOrSyncedCountrySendsNothing`, `Core.test_aCountryQueuedBeforeRegistrationIsNeverSentAfterAnOptOut` | Covered |
| SEGTEL-14 | SDK never requests location permission | `Core.test_locationSharingOnWithoutOSPermissionNeverReadsCountry`; `NottiLocationReader` has no `request*Authorization` call (T8, review) | Covered |
| SEGTEL-15 | Country is ISO alpha-2 from the reverse geocode | `Core.test_locationSharingOnWithPermissionAndAReadSendsCountryOnSessionStart` (value passed through unchanged); the `CLGeocoder` read is `live()` (build-only) | Covered (core); OS read build-only |

### device-profile-fields (DPF-01..21)

| RN ID | Behavior | Tests here | Status |
| --- | --- | --- | --- |
| DPF-01 | `device_os` / `device_model` / `sdk_version` read at init | `Core.test_registrationWithProfileProvidersPatchesAllSixFields`, `RT.test_startSendsSdkVersionEqualToTheNativeConstant` (CORE-05). OS reads are `live()` (build-only) | Covered |
| DPF-02 | Sent on registration | `Core.test_registrationWithProfileProvidersPatchesAllSixFields`, `Core.test_sdkVersionPassedThroughInitializeReachesThePayload` | Covered |
| DPF-03 | Diff-and-enqueue on change; ack by echo | `Core.test_onlyAChangedProfileFieldIsResentBetweenTwoRegistrations`, `Core.test_aPatchAckThatDoesNotEchoTheFieldLeavesItUnsyncedAndResendsOnTheNextRegistration`, `Core.test_aPatchAckEchoingADifferentValueDoesNotMarkTheFieldSynced`, `Core.test_anInstallUpgradedFrom050ResendsProfileFieldsItHadMarkedSyncedWithoutAnAck`, `DS.test_profileFieldAckMigrationClearsTheSixLastSyncedValuesExactlyOnce` | Covered |
| DPF-04 | Read failure → omit, no crash | `Core.test_aNilProfileProviderOmitsThatFieldWithoutCrashing`, `RT.test_startWithAnEmptySdkVersionOmitsTheField` | Covered |
| DPF-05 | `app_version` unchanged | `Core.test_appVersionDiffOnRegistrationEnqueuesAPatchWithTheVersion`, `Core.test_registrationWithProfileProvidersPatchesAllSixFields` | Covered |
| DPF-06 | `timezone_id` / `language` read at init | `Core.test_registrationWithProfileProvidersPatchesAllSixFields`, `Core.test_normalizedLanguageCodeKeepsOnlyTheIso6391PrimarySubtag` | Covered |
| DPF-07 | Sent on registration | `Core.test_registrationWithProfileProvidersPatchesAllSixFields` | Covered |
| DPF-08 | Diff-and-enqueue on change | `Core.test_onlyAChangedProfileFieldIsResentBetweenTwoRegistrations` | Covered |
| DPF-09 | Read failure → omit | `Core.test_aNilProfileProviderOmitsThatFieldWithoutCrashing` | Covered |
| DPF-10 | Permission status read at init / session start | `Core.test_registrationSuccessSyncsPermissionStatus`, `Core.test_anUnknownPermissionStatusIsOmittedWithoutCrashing`, `Core.test_aPermissionStatusReadThatResolvesAfterAReinitializePatchesTheCurrentApiClient` | Covered |
| DPF-11 | Sent on registration | `Core.test_registrationSuccessSyncsPermissionStatus` | Covered |
| DPF-12 | `requestPermission` result syncs the OS status | `Core.test_requestPermissionResultSyncsTheOSPermissionStatus` | Covered |
| DPF-13 | Settings change detected at next session start | `Core.test_aGrantedToDeniedSettingsChangeIsCaughtAtTheNextSessionStart` | Covered |
| DPF-14 | `last_unsubscribed_at` on true→false / granted→denied | `Core.test_setSubscriptionFalseOnASubscribedDeviceSetsLastUnsubscribedWhilePermissionStaysGranted`, `Core.test_setSubscriptionFalseWithAnUnknownLocalStateRecordsLastUnsubscribedAt`, `Core.test_setSubscriptionFalseWhenAlreadyFalseDoesNotRecordLastUnsubscribedAt`, `Core.test_aRetriedSetSubscriptionFalseResendsThePersistedTimestamp`, `Core.test_aRetriedPermissionDenialResendsThePersistedTimestamp`, `Core.test_twoDeniedReadsBeforeRegistrationStampTheFirstDetection`, `Core.test_aDeniedGrantedDeniedFlipBeforeRegistrationStampsTheThirdRead`, `Core.test_anUnknownPermissionReadLeavesAPendingDenialStampUntouched`, `Core.test_aGrantedPermissionResultClearsAStaleUnackedUnsubscribeStamp`, `DS.test_pendingUnsubscribeStampsRoundTripAndClear` | Covered |
| DPF-15 | Not cleared on re-subscribe | `Core.test_reSubscribeDoesNotClearLastUnsubscribedAt` | Covered |
| DPF-16 | `subscribed` and `permission_status` independent | `Core.test_setSubscriptionFalseOnASubscribedDeviceSetsLastUnsubscribedWhilePermissionStaysGranted`, `Core.test_aPermissionFlipQueuedBeforeRegistrationSendsOnlyTheFinalState` | Covered |
| DPF-17 | `setEmail` / `setPhone` persist + enqueue (core logic; JS wording → `public-api`) | `Core.test_setEmailEnqueuesAPatchWithEmailAndNeverTouchesTags`, `Core.test_setPhoneEnqueuesAPatchWithPhone`, `Core.test_setEmailBeforeInitializeIsPersistedAndResentOnRegistration` | Covered (core) |
| DPF-18 | Explicit clear, durable | `Core.test_clearEmailEnqueuesAnExplicitEmailNullClear`, `Core.test_clearEmailBeforeInitializeOfASyncedValueIsSentAsNullAtRegistration`, `Core.test_clearEmailBeforeInitializeOfANeverSyncedValueSendsNothing`, `Core.test_aFailedClearIsResentAsNullAtTheNextRegistration`, `Core.test_aSetAckedAfterANewerClearStillLeavesTheClearResendable` | Covered |
| DPF-19 | Held email/phone re-sent on registration | `Core.test_registrationSuccessResendsAHeldEmailAndPhone`, `Core.test_registrationSuccessWithNoHeldEmailOrPhoneSendsNothingForThem`, `CT.test_sameTokenReRegistrationKeepsTheRnDeviceIdAndSkipsTheAckMigration` | Covered |
| DPF-20 | No-op on unchanged acked value; re-send after failure | `Core.test_setEmailTwiceWithTheSameValueEnqueuesASingleMutation`, `Core.test_setEmailWithTheSameValueAfterAFailedPatchReEnqueuesIt`, `Core.test_setEmailThenLogoutLoginAndANewEmailConvergesOnTheNewEmail` | Covered |
| DPF-21 | Never merged into tags; never evicted from the queue | `Core.test_setEmailEnqueuesAPatchWithEmailAndNeverTouchesTags`, `Core.test_queuedEmailAndPhoneAreNeverEvictedFromAFullQueue` | Covered |

### Not in RN 0.6.0

`notification-action-buttons` (SDKACT-01..08) is at Design / Pending in the RN repo and did not ship in 0.6.0. Out of M1 scope (AD-002).

**Totals**: 19 + 14 + 11 + 15 + 21 = 80 RN IDs. 78 iOS-applicable (SDK-11 Android-only; SDKOPEN-11 is docs, moved to `example-and-release`). Every iOS-applicable ID has at least one test here. Parts moved to later features: SDK-04 device path (`example-and-release`), SDK-06 OS hook (`delegate-integration`), SDK-08 OS prompt / SDK-17 / SDK-18 / SDKOPEN-10 JS-facing surface (`public-api`).

---

## 2. Port-specific requirements (CORE-)

| ID | Tests |
| --- | --- |
| CORE-01 | Build + `grep -rnE "RCT\|React" Sources/` empty (T13). Providers build-only (T8) |
| CORE-02 | All ported tests construct their component with injected session/sleeper/defaults/monitor/providers; `RT.*` build isolated runtimes |
| CORE-03 | `RT.test_networkObserverStartedByTheRuntimeFlushesQueuedEventsOnReconnect`, `RT.test_backgroundObserverClosesTheSessionGateWithoutACore`, `RT.test_startTwiceInvalidatesTheFirstCoreAndTheSecondAdoptsTheOpenSession`, `RT.test_onNetworkAvailableWithoutACoreIsANoOp` |
| CORE-04 | `NH.test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration` |
| CORE-05 | `RT.test_startSendsSdkVersionEqualToTheNativeConstant`, `RT.test_startWithAnEmptySdkVersionOmitsTheField` |
| CORE-06 | Section 3 |
| CORE-07 | Section 1 |
| CORE-08 | SDK-04: `RT.test_onApnsRegistrationFailedLogsDomainAndCodeWithoutRegisteringAndTheCoreStaysUsable`; SDK-12/13: `RT.test_addTagsThroughTheRuntimeCorePatchesTheFullMergedMap`, `RT.test_removeTagsThroughTheRuntimeCorePatchesTheRemainingMap`; SDK-17: `NH.test_willPresentEmitsTheParsedPayloadToTheReceivedHandlerOnlyForARemotePush` |
| CORE-09 | `NottiDeviceStoreKeysTests` (golden keys; `test_productionSuiteNameMatchesRN` for the `notti_prefs` suite), `ES.*`, `CT.*` |
| CORE-10 | `CT.test_rnStateIsAdoptedWithoutRegistrationAndItsPendingEventsFlush`, `CT.test_sameTokenReRegistrationKeepsTheRnDeviceIdAndSkipsTheAckMigration` |
| CORE-11 | `CT.*` with `Fixtures/rn-0.6.0-state.plist` |
| CORE-12 | `LP.test_fullFlowWithFailuresAtVerboseLogsNoSentinelValue`, `LP.test_registrationTerminal4xxLogsNoSentinelValueAndFailsAtError`, `LP.test_registrationExhausted5xxLogsNoSentinelValueAndFailsAtError`, `Api.test_aNetworkErrorIsReportedAsDomainAndCodeWithoutTheRequestUrl`, `RT.test_onApnsRegistrationFailedLogsDomainAndCodeWithoutRegisteringAndTheCoreStaysUsable` |
| CORE-13 | `LP.test_defaultLevelIsErrorAndNothingBelowItIsEmitted`, `NottiLoggerTests.test_initialEffectiveLevelIsError`, `NottiLoggerTests.test_defaultLevelIsErrorOnly`, `NottiLoggerTests.test_messageAtLevelNoneIsNeverEmittedEvenAtVerbose` |

---

## 3. Test count: RN → here (CORE-06)

| RN file (52e4b55) | RN tests | Here | Here tests | Notes |
| --- | --- | --- | --- | --- |
| `NottiCoreTests.swift` | 123 | `NottiCoreTests` | 123 | 1:1 |
| `NottiApiClientTests.swift` | 29 | `NottiApiClientTests` | 30 | +1 `domain#code` (CORE-12) |
| `NottiDeviceStoreTests.swift` | 18 | `NottiDeviceStoreTests` + `NottiDeviceStoreKeysTests` | 18 + 2 | +1 golden key list, +1 suite name (Verifier round 1) |
| `NottiEventBufferTests.swift` | 12 | `NottiEventBufferTests` | 12 | 1:1 |
| `NottiEventStoreTests.swift` | 6 | `NottiEventStoreTests` | 7 | +1 corrupt-queue `.warn` |
| `NottiNotificationParsingTests.swift` | 6 | `NottiNotificationParsingTests` (NottiSharedTests) | 6 | 1:1 |
| `NottiNetworkObserverTests.swift` | 4 | `NottiNetworkObserverTests` | 4 | 1:1 |
| `NottiPushDelegateTests.swift` | 15 | `NottiNotificationHandlerTests` | 15 + 4 | all 15 ported to plain inputs; +4 (SDK-17, SDK-18, CORE-04, opportunistic flush) |
| — | — | `NottiRuntimeTests` | 13 | new (runtime) |
| — | — | `NottiLoggingPrivacyTests` | 4 | new (CORE-12/13); +2 registration failure (Verifier round 1) |
| — | — | `NottiContinuityTests` | 2 | new (CORE-10/11) |
| **RN total** | **213** | | | |

Suite totals after T13: `NottiSharedTests` 13, `NottiSDKTests` 233, `NottiSDKExtensionTests` 1 = 247. After the Verifier round 1 fixes: 14, 236, 1 = 251 (`NottiLoggerTests` +1).

---

## 4. Renamed, moved and dropped tests

**Renamed** (RN-specific wording only, `NottiPushDelegateTests` → `NottiNotificationHandlerTests`):

| RN name | Here |
| --- | --- |
| `test_didReceiveDefaultActionStillBuffersTheJSClickForAColdStart` | `test_didReceiveDefaultActionStillBuffersTheClickForAColdStart` |
| `test_didReceiveCustomActionDoesNotEmitTheJSClickEvent` | `test_didReceiveCustomActionDoesNotBufferAClick` |

All other ported tests keep their RN names, including `NottiCoreTests.test_aCoreRecreatedByAJsReloadWhileForegroundAdoptsTheOpenSessionInsteadOfClosingIt` (the "JS reload" scenario is the documented SEGTEL-08 case; its runtime-level equivalent is `RT.test_startTwiceInvalidatesTheFirstCoreAndTheSecondAdoptsTheOpenSession`).

**Moved to `delegate-integration`**: no test. Only the KVC fixture builders of `NottiPushDelegateTests` (`makeNotification`, `makeResponse`, the `class_createInstance` center) and the completion-handler plumbing move with the `UNUserNotificationCenterDelegate` adapter; no RN test asserted the presentation options.

**Moved test helpers**: `FakePathMonitor` (inline in RN `NottiNetworkObserverTests`) → `Support/FakePathMonitor.swift`; `LogSink`, `ThreadProbeApiClient`, `PatchHookApiClient`, `SlowEventApiClient` (end of RN `NottiCoreTests`) → `Support/`; `StubURLProtocol` → `Support/`.

**Dropped**: none. The RN NSE test (`NotificationServiceExtension/Tests`) is not part of core-port; it belongs to `nse-rich-media`.

---

## 5. Fixture values in ported tests (STATE todo from T2–T7)

Decision: ported RN tests keep their fixture values verbatim in M1 (`user@example.com`, `a@example.com`, `a@b.com`, `+5511999999999`, `+10000000000`). New tests written in this repo use `example.invalid` / `fixture` values. Recorded as AD-008 in `STATE.md`.

Reason: porting rule 1 (1:1 port, every diff line justified) and the values never leave the test process (every request goes to `StubURLProtocol`, nothing is logged by value, CORE-12). Risk accepted: `a@b.com` and `+5511999999999` are not reserved test values (`b.com` is a registered domain; the number has a valid São Paulo mobile format). Renaming them is a post-M1 todo, listed here when it happens.
