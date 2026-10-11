# NSE Rich Media Traceability

**Spec**: `.specs/features/nse-rich-media/spec.md` (NSE-01..NSE-18)
**Design**: `.specs/features/nse-rich-media/design.md`, tasks in `tasks.md`
**Status**: Written in T16 (2026-10-11). Implemented, Verifier pending (no `validation.md` yet).

Test references use `Class.test_name` with these abbreviations, all in `Tests/NottiSDKExtensionTests` unless noted: `UR` = `NottiRichMediaURLTests`, `FT` = `NottiMediaFileTypeTests`, `GT` = `NottiHandlerGateTests`, `DR` = `NottiRichMediaDropReasonTests`, `SP` = `NottiRichMediaSpikeTests`, `JB` = `NottiRichMediaJobTests`, `JD` = `NottiRichMediaJobDropTests`, `JE` = `NottiRichMediaJobEarlyAbortTests`, `JL` = `NottiRichMediaJobDeadlineTests`, `JX` = `NottiRichMediaJobExpiryTests`, `RG` = `NottiRichMediaRegistryTests`, `FA` = `NottiNotificationServiceExtensionTests`, `PV` = `NottiRichMediaPrivacyTests`, `CT` = `NottiRichMediaContractTests`, `OC` = `NottiExtensionObjCTests` (Objective-C, target `NottiSDKExtensionObjCTests`).

A test may appear under several IDs. A row lists the tests that assert that acceptance criterion. Scripts were proved on a passing and a failing tree (T13). The OS does not run a Notification Service Extension in the Simulator, so every test calls the helper directly; end to end on a device is unproven (see section 3).

---

## 1. Spec requirement to tests

| ID | Behavior | Tests / proof | Status |
| --- | --- | --- | --- |
| NSE-01 | A valid `https` URL with a 2xx, allowed-type, in-budget response gives one attachment and every other field unchanged | `JB.test_pngIsAttached`, `JB.test_jpgIsAttached`, `JB.test_gifIsAttached`, `JB.test_mp4IsAttached`, `JB.test_mp3IsAttached`, `JB.test_successLeavesOnlyTheAttachmentFileInTheDirectory`, `JE.test_aRedirectChainThatEndsOnHttpsStillAttaches`, `FA.test_aValidUrlAttachesOnceAndKeepsEveryOtherField`, `FA.test_anUppercaseHttpsSchemeIsAccepted`, `PV.test_pathSuccess` | Covered |
| NSE-02 | Missing or non-`String` key: one handler call with the original content, no request, no log | `UR.test_missingKeyIsAbsent`, `UR.test_nonStringValuesAreAbsent`, `FA.test_aMissingKeyCallsTheHandlerOnceStartsNoRequestAndLogsNothing`, `FA.test_aNonStringValueIsTreatedAsMissing`, `PV.test_pathAbsent`, `OC.testARequestWithoutAnImageUrlCallsTheHandlerOnceWithTheOriginalContent` | Covered |
| NSE-03 | Invalid URL or non-`https` scheme: no request, one `.error` line without the value, one handler call | `UR.test_emptyStringIsInvalid`, `UR.test_unparsableTextIsInvalid`, `UR.test_fileSchemeIsInvalid`, `UR.test_httpSchemeIsInvalid`, `UR.test_ftpSchemeIsInvalid`, `UR.test_customSchemeIsInvalid`, `UR.test_httpsWithoutHostIsInvalid`, `UR.test_uppercaseSchemeIsValid`, `UR.test_validHttpsUrlIsValid`, `FA.test_aFileUrlIsInvalid`, `FA.test_anHttpUrlIsInvalid`, `FA.test_anEmptyStringIsInvalid`, `PV.test_pathInvalidScheme`, `PV.test_pathHttpScheme` | Covered |
| NSE-04 | A final URL (after redirects) that is not `https` is discarded; the redirect is refused before the body | `JD.test_aFinalUrlThatIsNotHttpsIsDiscarded`, `JE.test_aRedirectToHttpEndsBeforeAnyBodyByteIsServedEvenWhenTheStubIgnoresTheRefusal`, `JE.test_aRedirectToHttpWhoseTargetNeverRespondsStillEndsAtOnce`, `SP.test_refusingARedirectWithNilAloneDoesNotCompleteTheTask_andCancelDoes`, `SP.test_refusingARedirectWithNilAndCancelCompletesWithCancelledBeforeAnyBody`, `PV.test_pathRedirectToHttp` | Covered |
| NSE-05 | Transfer failure, no file or non-2xx: nothing attached, no temp file, one handler call | `JB.test_notFoundDropsWithTheUntouchedContent`, `JB.test_transportErrorDropsWithDomainAndCodeOnly`, `JB.test_completionWithoutAFileDropsAsNoFile`, `FA.test_aNonSuccessStatusCallsTheHandlerOnceWithTheOriginalContent`, `PV.test_pathNotFound`, `PV.test_pathTransportError` | Covered |
| NSE-06 | A file over 10 MiB is deleted and not attached | `JD.test_aFileOverTheCapIsDeletedAndNotAttached`, `JD.test_aFileExactlyAtTheCapIsAccepted`, `PV.test_pathOversizeAfterDownload`, `CT.test_theSizeCapIs10MiBAsALiteralAndEnforcedAtThatBoundary`, `CT.test_aBodyDeclaredAtExactlyTheCapIsNotCutOff` | Covered |
| NSE-07 | File type from the MIME (case-insensitive), then the allowlisted URL extension, else `jpg` | `FT.test_eachAllowedMimeTypeMapsToItsExtension`, `FT.test_mimeMatchIsCaseInsensitive`, `FT.test_mimeTypeWinsOverTheUrlExtension`, `FT.test_unknownMimeFallsBackToAnAllowlistedUrlExtension`, `FT.test_unknownMimeAndUnlistedUrlExtensionFallBackToJpg`, `FT.test_noMimeAndNoExtensionFallBackToJpg`, `FT.test_aPathLikeExtensionNeverReachesTheResult`, `FT.test_onlyTheLastPathComponentExtensionCounts`, the five `JB.test_*IsAttached` (extension of the attached file) | Covered |
| NSE-08 | `UNNotificationAttachment` rejects the file: moved file deleted, nothing attached, one handler call | `JD.test_bytesTheSystemRejectsDropAsAttachmentRejectedAndTheMovedFileIsDeleted`, `PV.test_pathAttachmentRejected` | Covered |
| NSE-09 | No downloaded file stays in the temp directory except the one owned by an attachment | `JB.test_successLeavesOnlyTheAttachmentFileInTheDirectory`, `JD.test_aSuccessfulAttachmentIsTheOnlyFileInTheDirectory`, `JD.test_aDirectoryThatCannotBeWrittenDropsAsMoveFailed`, `JL.test_aStubThatNeverFinishesEndsAtTheDeadlineWithTheTaskCancelledAndNoFile`, `JL.test_aCompletionRacingTheDeadlineOrExpiryLeavesNoFileWithoutAnAttachment` (300 racing jobs; covers the lost-race cleanup), `JX.test_aLateCompletionAfterExpiryAddsNoCallAndNoFile`, the directory assertion of every `PV.test_path*` | Covered |
| NSE-10 | A 20 s total deadline cancels the download; trickling bytes do not extend it | `JL.test_aStubThatNeverFinishesEndsAtTheDeadlineWithTheTaskCancelledAndNoFile`, `JL.test_aResponseThatTricklesBytesStillEndsAtTheDeadline`, `JL.test_aJobThatFinishesFirstCancelsTheTimer`, `JL.test_theDeadlineIsMeasuredFromStartNotFromTheLastByte`, `JL.test_aResponseThatSendsLargeChunksStillEndsAtTheDeadlineBecauseProgressDoesNotRearmIt` (64 KiB chunks reach `didWriteData`; kills the re-arm mutant), `PV.test_pathDeadline`, `CT.test_theDeadlineIs20SecondsAsALiteral` (the 20 s value is asserted as a literal; the behavior tests use a short injected deadline) | Covered |
| NSE-11 | Expiry cancels the matching job, calls the handler once with the host content, a late completion adds no call | `JX.test_expireOnAnInFlightJobCancelsItAndCallsTheHandlerOnceWithTheHostContent`, `JX.test_aLateCompletionAfterExpiryAddsNoCallAndNoFile`, `JX.test_expireOnAFinishedJobCallsNothing`, `JX.test_aSecondExpireCallsNothing`, `JX.test_theDeadlineAfterAnExpiryAddsNoCall`, `JX.test_expiringOneOfTwoInFlightJobsLeavesTheOtherRunning`, `RG.test_returnsOnlyTheJobWhoseUserInfoEquals`, `RG.test_returnsNothingWhenNoUserInfoEquals`, `RG.test_keepsAtMostSixteenJobsAndDropsTheOldest`, `RG.test_stillReturnsAFinishedJob`, `RG.test_matchesBySharedDeliveryIdWhenAnotherKeyDiffers`, `RG.test_differentDeliveryIdsNeverMatchEvenWhenEverythingElseIsEqual`, `RG.test_anEmptyDeliveryIdFallsBackToUserInfoEquality`, `RG.test_aDeliveryIdOnOnlyOneSideFallsBackToUserInfoEquality`, `FA.test_expiryThroughTheFacadeCancelsTheMatchingJobAndCallsTheHandlerOnce`, `FA.test_expiryWithNoMatchingJobCallsTheHostHandlerDirectly`, `FA.test_expiryLeavesAJobOfAnotherNotificationRunning`, `FA.test_expiryStillFindsTheJobWhenTheHostChangedAnotherUserInfoKey`, `GT.test_secondFireDoesNotCallTheHandler`, `GT.test_manyConcurrentFiresCallTheHandlerOnce`, `PV.test_pathExpiry`, `SP.test_twoMutableCopiesOfTheSameRequestHaveEqualUserInfoAndADifferentOneDoesNot` | Covered |
| NSE-12 | Expiry with `nil` content calls no handler | `FA.test_expiryWithNilContentCallsNoHandler`, `OC.testExpiryWithNilContentIsANoOp` | Covered |
| NSE-13 | `NottiLogger` category `nse`, no URL, host, query, title, body or `localizedDescription`, errors as `domain#code` | `PV.test_pathSuccess` ... `PV.test_pathExpiry` (13 paths, a sentinel in the URL host, path and query and in the title and body; asserts level `.error`, one line, no sentinel; checked once against a temporary edit that logged the URL: 21 assertions failed), `PV.test_pathTransportError` (an error whose `userInfo` and description carry the URL), `PV.test_everyLogCallInTheExtensionSourcesUsesCategoryNse`, `DR.test_fixedCodesAreLiterals`, `DR.test_errorReasonsCarryOnlyDomainAndCode`, `DR.test_errorReasonsNeverUseTheErrorMessageOrUserInfo`; `scripts/check-nse-logging.sh` (CI `checks` job; proved on a fixture per banned token and on a comment-only fixture) | Covered. The category is checked on the source text, not on the captured line (the logger sink does not carry it; recorded as a deviation in T12) |
| NSE-14 | Extension-safe product, no UIKit, no dependency on `NottiSDK` | `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh`, strict device build of `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES`, `pod lib lint NottiSDK.podspec --platforms=ios` (all and `--subspec=Extension`), `PM.test_manifestIsBundledAndDeclaresFileTimestamp` | Covered (script and build checks, no unit test: Test Coverage Matrix) |
| NSE-15 | The class and its two methods are in `PUBLIC_SURFACE.txt` | `scripts/check-public-surface.sh` (71 declarations; T11 added exactly the class and the two methods) | Covered (script) |
| NSE-16 | Objective-C hosts can call both selectors | `OC.testBothSelectorsAreCallableFromObjectiveC`, `OC.testExpiryWithNilContentIsANoOp`, `OC.testARequestWithoutAnImageUrlCallsTheHandlerOnceWithTheOriginalContent`, `CT.test_theTwoPublicSelectorsAndTheClassNameAreTheDocumentedOnes`; removing the `@objc` selector names made the target fail to compile (T14, T15) | Covered. Selector in the spec text corrected to `serviceExtensionTimeWillExpireFor:contentHandler:` (design) |
| NSE-17 | A response over 10 MiB is cancelled as soon as that is known | `JE.test_aDeclaredLengthOverTheCapIsCancelledBeforeTheBody` (stub serves under 2 MiB), `JE.test_aBodyWithNoLengthIsCancelledOnceTheCapIsCrossed`, `SP.test_declaredLengthArrivesInTheFirstWriteAndCancelStopsTheBody`, `PV.test_pathOversizeDeclaredEarly`, `PV.test_pathOversizeByBytesWithNoHeader` | Covered |
| NSE-18 | Key, 10 MiB cap, 20 s deadline and the five types are asserted as literals | `CT.test_theKeyIsNottiImageUrlAndTheParserReadsExactlyThatKey`, `CT.test_theSizeCapIs10MiBAsALiteralAndEnforcedAtThatBoundary`, `CT.test_theDeadlineIs20SecondsAsALiteral`, `CT.test_theFiveAllowedMimeTypesMapToTheirExtensions`, `CT.test_onlyTheFiveUrlExtensionsAreTrustedAndTheDefaultIsJpg`, `CT.test_theTwoPublicSelectorsAndTheClassNameAreTheDocumentedOnes`, `DR.test_defaultLimitsAreTheContractLiterals`; each value was changed once by a temporary edit and a test failed (T15) | Covered |

---

## 2. Test counts by target and file (full run after the Verifier round 1 test fixes: Shared 14, SDK 453, ObjC 6, Extension 110, Extension ObjC 3 = 586; baseline before this feature 474, so 112 added)

| File | Tests |
| --- | --- |
| `NottiRichMediaURLTests` | 11 |
| `NottiMediaFileTypeTests` | 8 |
| `NottiHandlerGateTests` | 3 |
| `NottiRichMediaDropReasonTests` | 4 |
| `NottiRichMediaSpikeTests` | 4 |
| `NottiRichMediaJobTests` | 12 |
| `NottiRichMediaJobDropTests` | 6 |
| `NottiRichMediaJobEarlyAbortTests` | 5 |
| `NottiRichMediaJobDeadlineTests` | 6 |
| `NottiRichMediaJobExpiryTests` | 7 |
| `NottiRichMediaRegistryTests` | 8 |
| `NottiNotificationServiceExtensionTests` | 14 |
| `NottiRichMediaPrivacyTests` | 14 |
| `NottiRichMediaContractTests` | 7 |
| `PrivacyManifestTests` (existing) | 1 |
| `NottiExtensionObjCTests` (`NottiSDKExtensionObjCTests`) | 3 |
| Extension target total | 110, plus 3 Objective-C |

---

## 3. Findings and recorded decisions

| Item | Where | Note |
| --- | --- | --- |
| Spike on macOS, re-proved on the Simulator | `SP.*` | The four spike results of `design.md` were re-run as tests on the iOS Simulator (T5) and held |
| Job owns the outcome | `NottiRichMediaJob.finish` | Answering `nil` to a redirect does not end the task; `finish` cancels it. A job that loses the race to deadline or expiry removes the file it had already moved |
| Registry shared by process | `NottiRichMediaEnvironment.live` | `didReceive` and the expiry call are separate static calls, so the live environment holds one registry |
| Correlation by `userInfo` or `delivery_id` | `NottiRichMediaRegistry.jobs(matching:)` | D10. Two different non-empty `delivery_id`s never match; an empty or one-sided id falls back to `userInfo` equality |
| Log category not observable | `PV.test_everyLogCallInTheExtensionSourcesUsesCategoryNse` | `NottiLogger.sink` receives level and message only and `NottiShared` is out of scope, so the category `nse` is asserted on the source text of every `NottiLogger.log` call |
| `pod lib lint` caught a Sendable warning | `NottiRichMediaJob.userInfo` | Found at the first full gate after the registry task (the quick gate does not run `pod lib lint`); fixed with `nonisolated(unsafe)` on an immutable snapshot, in its own commit |
| End to end on a device | `example-and-release` | Unproven: an NSE does not run in the Simulator. A real push with `notti_image_url`, the `@objc(NotificationService)` wiring and the two forwarding calls need the example app on a device |
| Open items for Julio | design.md | None blocking. D9: confirm in App Store validation that `PrivacyInfo.xcprivacy` (C617.1 kept) is accepted |
