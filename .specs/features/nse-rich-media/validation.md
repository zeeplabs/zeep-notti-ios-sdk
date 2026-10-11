# Validation: nse-rich-media - PASS (round 2)

**Date**: 2026-10-11
**Spec**: `.specs/features/nse-rich-media/spec.md` (NSE-01..NSE-18, Goals, Success Criteria; the only source for blocking)
**Diff range**: `fe26920..HEAD` (`4d1a513`), 17 commits, 41 files, `git diff --stat`: +2810 / -120. Spec/design/tasks docs are at `fe26920`; the later commits touch `Sources/NottiSDKExtension`, `Tests/NottiSDKExtensionTests`, `Tests/NottiSDKExtensionObjCTests`, `Package.swift`, `scripts/check-nse-logging.sh`, `.github/workflows/ci.yml`, `AGENTS.md`, `.specs/`. The only spec edit after `fe26920` is the status column and the coverage line (checked with `git diff`): no AC was reworded or weakened.
**Verifier**: independent, author of none of the code, tests or docs. Every mutant was applied, run and reverted with `git checkout -- <file>`; `git status --short` was empty after each one (the harness records it). Throwaway probe tests were added to `Tests/NottiSDKExtensionTests`, run, and deleted. At the end of this report `git status --short` shows only the new `validation.md`.
**Environment**: Xcode 27.0 (27A266a), simulator `iPhone 17 Pro`, SwiftLint 0.65.1 (Docker), CocoaPods 1.17.0. Tests through the watchdog `run.sh`, one `xcodebuild` at a time.

## Verdict (round 2): PASS. B1, B2 and B3 are closed (see the Round 2 section at the end); no new blocker. Round 1 below was FAIL.

## Round 1 history: FAIL (round 1), no production defect found

The production code satisfied every AC and every Goal in all my probes. Three realistic one-line regressions of production code pass the whole 584-test suite, and each violates a literal sentence of the spec (B1, B2, B3 below). The fix for all three is **tests only** (no change under `Sources/`); I give the exact probe for each.

Reading note for Julio: I read "a surviving mutant blocks only if it maps to a spec AC that has no other test that fails" as "blocks unless some other test would fail when that sentence of the AC is violated". Under that reading B1 to B3 block (the tests the traceability cites for them are insensitive to the mutant, shown below). If you read the rule as "blocks only if the AC has zero tests", B1 to B3 become non-blocking and the verdict is PASS. Everything else is non-blocking in both readings.

Blocking criteria used: NSE-01..18 as written, Goals and Success Criteria, the gates, AGENTS.md rules (privacy and logging, extension safety, public surface, no AI attribution). Everything else is a note.

---

## Gates (HEAD `4d1a513`, my own runs)

| Gate | Result |
| --- | --- |
| Full suite (`xcodebuild test -scheme NottiSDK-Package`, `NBUNDLES=5`) | `** TEST SUCCEEDED **`: **584 tests, 0 failures** (584 `Test Case ... passed`, 0 failed). Bundles: Shared 14, SDK 453, SDK ObjC 6, Extension 108, Extension ObjC 3. Success Criteria floor is 474: met (+110). Matches `traceability.md` section 2 exactly |
| SwiftLint 0.65.1 `--strict` (Docker) | 0 violations, 0 serious, 100 files |
| `check-version.sh` | `version ok: 0.1.0` |
| `check-extension-safety.sh` | `extension safety ok` |
| `check-package-graph.sh` | `package graph ok` |
| `check-public-surface.sh` | `public surface ok (71 declarations)` (68 before, +3: the class and its two methods) |
| `check-no-url-open.sh` | `no url open ok` |
| `check-launch-hook-purity.sh` | `launch hook purity ok` |
| `check-nse-logging.sh` | `extension logging ok (10 files)` |
| `check-hook-linked.sh spm` (`NOTTI_SIM="iPhone 17 Pro"`) | `NOTTI_HOOK loadCount=1 installCount=1`, `hook linked ok (spm)` |
| `check-hook-linked.sh pod` | `hook linked ok (pod)` |
| `pod lib lint NottiSDK.podspec --platforms=ios` | `NottiSDK passed validation.` |
| `pod lib lint ... --subspec=Extension` | `NottiSDK passed validation.` |
| Strict device build `NottiSDK` (`generic/platform=iOS`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`, CI command) | rc 0 |
| Strict device build `NottiSDKExtension` (same flags plus `APPLICATION_EXTENSION_API_ONLY=YES`) | rc 0 |
| AI attribution in the 17 commits | none (`git log fe26920..HEAD --format=%B` has no `co-authored`, `claude`, `anthropic` or `generated with`); author Julio Sousa on all |

**Clean builds**: both device builds ran with a fresh `-derivedDataPath` in the scratchpad (empty before the build), so both products were compiled from scratch, not incrementally. The test and pod builds used the normal derived data.

**Flakiness**: the whole `NottiSDKExtensionTests` plus `NottiSDKExtensionObjCTests` ran 3 times in one invocation (`-test-iterations 3`): 333 passes (111 x 3), 0 failures. Separately, `NottiRichMediaJobExpiryTests`, `NottiNotificationServiceExtensionTests`, `NottiRichMediaJobDeadlineTests` and `NottiRichMediaPrivacyTests` ran 30 times in one invocation: 1170 passes (39 x 30), 0 failures, 0 `error:` lines.

---

## AC-by-AC

"Mutants" are the ids of the ledger below that exercise the AC. Tests are `Class.test_name` in `Tests/NottiSDKExtensionTests` unless marked. I read the bodies of the tests listed here (not only the names).

| AC | Proven by (test bodies read) | Mutants | Verdict |
| --- | --- | --- | --- |
| NSE-01 attach once, other fields equal | `NottiRichMediaJobTests.test_{png,jpg,gif,mp4,mp3}IsAttached` (assert count 1, one attachment, extension, all fields through `assertFieldsEqualToOriginal`, no log), `NottiNotificationServiceExtensionTests.test_aValidUrlAttachesOnceAndKeepsEveryOtherField`, `test_anUppercaseHttpsSchemeIsAccepted` | t1 (title cleared), t2 (two attachments), q | Met, mutants killed |
| NSE-02 missing or non-String key | `test_aMissingKeyCallsTheHandlerOnceStartsNoRequestAndLogsNothing`, `test_aNonStringValueIsTreatedAsMissing`, `NottiRichMediaURLTests` absent cases, ObjC `testARequestWithoutAnImageUrlCallsTheHandlerOnceWithTheOriginalContent` | o1 (handler twice), o2 (starts a request), q | Met |
| NSE-03 invalid URL or non-https | `NottiNotificationServiceExtensionTests.test_aFileUrlIsInvalid/test_anHttpUrlIsInvalid/test_anEmptyStringIsInvalid` (no request, exactly `["rich media dropped: invalid_url"]`, level `.error`, one call), `NottiRichMediaURLTests`, `NottiRichMediaPrivacyTests.test_pathInvalidScheme/test_pathHttpScheme` | f (http accepted), r1 (handler not called), s2 (host-less https), d2 (raw value in the log). s1 (empty guard removed) survives: equivalent, `URL(string: "")` is `nil` | Met |
| NSE-04 final URL not https, discard | `NottiRichMediaJobDropTests.test_aFinalUrlThatIsNotHttpsIsDiscarded`, `NottiRichMediaJobEarlyAbortTests.test_aRedirectToHttp...` (two), `test_aRedirectChainThatEndsOnHttpsStillAttaches`, `NottiRichMediaPrivacyTests.test_pathRedirectToHttp` | g (refusal skipped), h (final-URL check skipped) killed. **t12 survives (see B2)** | Met in production; proof of "http is never fetched" incomplete (B2) |
| NSE-05 transfer failure, no file, non-2xx | `NottiRichMediaJobTests.test_notFoundDropsWithTheUntouchedContent`, `test_transportErrorDropsWithDomainAndCodeOnly`, `test_completionWithoutAFileDropsAsNoFile`, facade `test_aNonSuccessStatusCallsTheHandlerOnce...` (each asserts one call, no attachment, directory empty, exact log) | n (status check removed), n2 (200..<500), t6 (no-file branch removed; killed by an assertion plus a crash), t11 (wrong reason) | Met |
| NSE-06 file over 10 MiB deleted | `NottiRichMediaJobDropTests.test_aFileOverTheCapIsDeletedAndNotAttached` (asserts the source file is gone), `test_aFileExactlyAtTheCapIsAccepted`, `NottiRichMediaPrivacyTests.test_pathOversizeAfterDownload` | i (check skipped), e2 (`>=`), e5 (`> cap+1`), k2 (received file not deleted), e1 (11 MiB), e4 (9 MiB) | Met |
| NSE-07 file type | `NottiMediaFileTypeTests` (8), `NottiRichMediaContractTests.test_theFiveAllowedMimeTypesMapToTheirExtensions`, `test_onlyTheFiveUrlExtensionsAreTrustedAndTheDefaultIsJpg`, extension of the attached file in the five `JB` tests | l1 (case-sensitive), l2 (unlisted extension through), l3 (URL ext not lowercased) killed. **l4 survives (N1)**: the job's wiring of the original URL into the fallback is unproven | Met in production; N1 |
| NSE-08 attachment rejected | `NottiRichMediaJobDropTests.test_bytesTheSystemRejectsDropAsAttachmentRejectedAndTheMovedFileIsDeleted` (6 MiB of zeros as `audio/mpeg`; asserts one call, no attachment, directory empty, log prefix), `NottiRichMediaPrivacyTests.test_pathAttachmentRejected` | k1 (moved file not deleted) | Met |
| NSE-09 no leaked temp file | directory assertions in `JB`, `JD`, `JL`, `JX` and every `PV.test_path*`, `test_aDirectoryThatCannotBeWrittenDropsAsMoveFailed` | k1, k2 killed. **k3 survives (B3)**: the file moved by a job that loses the race to the deadline or to expiry | Met on every sequential path; the race path is unproven by the committed suite (B3) |
| NSE-10 20 s total deadline, trickle does not extend it | `NottiRichMediaJobDeadlineTests` (4), `NottiRichMediaPrivacyTests.test_pathDeadline`, `NottiRichMediaContractTests.test_theDeadlineIs20SecondsAsALiteral` | a (never scheduled) killed by 3 tests, t9 (25 s) killed, t7 (timer not cancelled on finish) survives: equivalent, `finish` is first-caller-wins. **w (idle deadline: re-arm on every `didWriteData`) survives (B1)** | First sentence proven. Second sentence met in production (my probe) but not provable by the committed tests (B1) |
| NSE-11 expiry cancels, one call, late completion adds none | `NottiRichMediaJobExpiryTests` (7), facade `test_expiryThroughTheFacadeCancelsTheMatchingJobAndCallsTheHandlerOnce`, `test_expiryLeavesAJobOfAnotherNotificationRunning`, `test_expiryStillFindsTheJobWhenTheHostChangedAnotherUserInfoKey`, `NottiRichMediaRegistryTests` (8), `NottiHandlerGateTests` (3) | b2, b3, c1, c2, m1, m2, m3, t3, t5, v4, x killed. b1 (only `task.cancel()` removed) and m4 survive: equivalent (see ledger) | Met |
| NSE-12 expiry with nil content | `test_expiryWithNilContentCallsNoHandler` (also asserts the job was not cancelled), ObjC `testExpiryWithNilContentIsANoOp` | t4 (nil calls the handler) | Met |
| NSE-13 logging | `NottiRichMediaPrivacyTests` (13 path tests with a sentinel in URL host, path, query, title and body; assert one `.error` line, no sentinel, one handler call, directory state), `NottiRichMediaDropReasonTests`, `test_everyLogCallInTheExtensionSourcesUsesCategoryNse`, `scripts/check-nse-logging.sh` | d1 (host), d2 (raw value), d3 (`localizedDescription`), d4 (query), d5 (host in the expiry line), d6 (category), d7 (level) all killed | Met. Notes N3 (script limits) |
| NSE-14 extension-safe | `check-extension-safety.sh`, `check-package-graph.sh`, strict extension device build with `APPLICATION_EXTENSION_API_ONLY=YES` (clean build), both `pod lib lint`, my own grep of `Sources/NottiSDKExtension` (no `UIKit`, `UIApplication`, `beginBackgroundTask`, `registerForRemoteNotifications`, `CLLocationManager`, `import NottiSDK`, rc 1 = no match); `Package.swift`: target depends on `NottiShared` only | n/a (build/script AC) | Met |
| NSE-15 public surface | `check-public-surface.sh` passes. `PUBLIC_SURFACE.txt` diff against `fe26920` is exactly 3 added lines: `public final class NottiNotificationServiceExtension: NSObject`, `public static func didReceive(...)`, `public static func serviceExtensionTimeWillExpire(...)`. No other file in the extension has `public` | n/a | Met |
| NSE-16 ObjC mirror | `NottiExtensionObjCTests.m` (3 tests, compiled and run in `NottiSDKExtensionObjCTests`), `NottiRichMediaContractTests.test_theTwoPublicSelectorsAndTheClassNameAreTheDocumentedOnes`. Selectors in source: `@objc(NottiNotificationServiceExtension)`, `didReceive:withContentHandler:`, `serviceExtensionTimeWillExpireFor:contentHandler:`, exactly what spec NSE-16 says | y (class renamed) and z (selector renamed): killed by an Objective-C compile error | Met |
| NSE-17 early oversize abort | `NottiRichMediaJobEarlyAbortTests.test_aDeclaredLengthOverTheCapIsCancelledBeforeTheBody` (served bytes < 2 MiB, stop count >= 1), `test_aBodyWithNoLengthIsCancelledOnceTheCapIsCrossed` (served between 10 and 16 MiB), contract boundary tests, `PV.test_pathOversizeDeclaredEarly/ByBytesWithNoHeader` | j1 (declared length branch), j2 (bytes branch), j3 (both), e3 (`>=`) each killed by a different test | Met |
| NSE-18 contract literals | `NottiRichMediaContractTests` (7) and `NottiRichMediaDropReasonTests.test_defaultLimitsAreTheContractLiterals`: key `"notti_image_url"`, `10485760`, `20`, five MIME types and five extensions as literals, and `NottiRichMediaEnvironment.live.limits` too. Not tautological (they never read the constant they test) | e1, e4, t9, q killed | Met |

### Goals and Success Criteria, literally

| Goal / criterion | Result |
| --- | --- |
| Two forwarding calls attach image, video, audio, no download code in the host | Met for the stub (five types). Real device unproven (see Not proven) |
| Every failure ends in exactly one handler call, never crashes, hangs or calls twice | Met. 13 sequential paths asserted after a grace period; **plus my stress probe: 900 jobs racing deadline and expiry against completion, handler count exactly 1 each time** (probe ii) |
| Only https fetched, first URL and after redirects, 10 MiB cap | Met in production (my probe: the http redirect target is never requested, `requested = ["https"]`). The committed tests do not prove the "never requested" part (B2) |
| No PII, URL, host or query in a log line | Met. Three `NottiLogger.log` call sites exist (facade invalid URL, job drop, job expiry), all fixed codes, all `category: "nse"`, all `.error` |
| Extension product extension-safe, never depends on `NottiSDK` | Met (scripts, grep, clean strict device build) |
| Temp files not leaked | Met on sequential paths; unproven by the committed suite on the race path (B3). My stress probe on production code: files left == attachments returned in every run |
| Gates: scripts, device build, `pod lib lint` (all and Extension), SwiftLint 0, count >= 474 | Met (584) |
| End to end on a real device listed as unproven | Listed (this report, "Not proven") |

---

## Mutant ledger

Harness: `python3 mut.py <id>`: applies one exact-match edit (asserted to match once), runs the whole `NottiSDKExtensionTests` bundle through the watchdog (the two ObjC mutants y and z also run `NottiSDKExtensionObjCTests`), records the failing tests, reverts with `git checkout --`, checks `git status --short` is empty. All 61 edits matched; 0 invalid.

**61 mutants applied. 4 survive as equivalent (b1, m4, s1, t7). 57 non-equivalent: 52 killed, 5 survive (k3, t8, t12, w, l4).** Of the 5, k3, t12 and w are blocking (B3, B2, B1); l4 and t8 are non-blocking notes.

| Id | Mutation | Result | Killing test(s) (first ones) |
| --- | --- | --- | --- |
| a | deadline timer never scheduled | KILLED | `JL.test_aResponseThatTricklesBytesStillEndsAtTheDeadline`, `JL.test_theDeadlineIsMeasuredFromStartNotFromTheLastByte`, `PV.test_pathDeadline` |
| b1 | `finish` drops only `task?.cancel()` (session invalidate stays) | SURVIVED, equivalent | `invalidateAndCancel()` cancels the task too |
| b2 | `finish` neither cancels the task nor invalidates the session | KILLED | `FA.test_expiryThroughTheFacade...`, `JL.test_aStubThatNeverFinishes...`, `JE.test_aDeclaredLength...`, `JB.test_theJobIsReleasedAfter*` |
| b3 | `expire` only fires the gate (no finish, no cancel) | KILLED | `FA.test_expiryThroughTheFacade...`, `JX.test_aSecondExpireCallsNothing` (9 failing) |
| c1 | gate never records `fired` | KILLED | `GT.test_secondFireDoesNotCallTheHandler`, `GT.test_manyConcurrentFiresCallTheHandlerOnce` |
| c2 | `finish` loses its first-caller guard (gate stays) | KILLED | `JX.test_aSecondExpireCallsNothing`, `JX.test_expireOnAFinishedJobCallsNothing` |
| d1 | drop log appends the request host | KILLED | 19 tests, including every `PV.test_path*` |
| d2 | invalid-URL log appends the raw value | KILLED | `FA.test_aFileUrlIsInvalid`, `PV.test_pathInvalidScheme` |
| d3 | transport reason carries `localizedDescription` | KILLED | `DR.test_errorReasonsNeverUseTheErrorMessageOrUserInfo`, `PV.test_pathTransportError` |
| d4 | drop log appends the request query | KILLED | 19 tests |
| d5 | expiry log appends the host | KILLED | `JX.test_expireOnAnInFlightJob...`, `PV.test_pathExpiry` |
| d6 | drop log category `net` | KILLED | `PV.test_everyLogCallInTheExtensionSourcesUsesCategoryNse` |
| d7 | drop log level `.warn` | KILLED | 10 tests (`JB.test_notFound...`, `PV.test_pathDeadline`...) |
| e1 | cap 11 MiB | KILLED | `CT.test_theSizeCapIs10MiB...`, `DR.test_defaultLimitsAreTheContractLiterals` |
| e2 | post-download `>` becomes `>=` | KILLED | `JD.test_aFileExactlyAtTheCapIsAccepted` |
| e3 | `didWriteData` `>` becomes `>=` | KILLED | `CT.test_aBodyDeclaredAtExactlyTheCapIsNotCutOff`, `JE.test_aBodyWithNoLength...` |
| e4 | cap 9 MiB | KILLED | `CT.test_aBodyDeclaredAtExactlyTheCapIsNotCutOff`, `CT.test_theSizeCapIs10MiB...` |
| e5 | post-download check `> cap + 1` | KILLED | `JD.test_aFileOverTheCapIsDeletedAndNotAttached` |
| f | scheme allowlist accepts `http` | KILLED | `FA.test_anHttpUrlIsInvalid`, `PV.test_pathHttpScheme`, `UR.test_httpSchemeIsInvalid` |
| g | redirect refusal skipped | KILLED | `JE.test_aRedirectToHttpEndsBeforeAnyBodyByteIsServed...`, `JE.test_aRedirectToHttpWhoseTargetNeverResponds...` |
| h | final-URL scheme check skipped | KILLED | `JD.test_aFinalUrlThatIsNotHttpsIsDiscarded` |
| i | post-download size check skipped | KILLED | `JD.test_aFileOverTheCapIsDeletedAndNotAttached`, `PV.test_pathOversizeAfterDownload` |
| j1 | early abort on declared length skipped | KILLED | `JE.test_aDeclaredLengthOverTheCapIsCancelledBeforeTheBody`, `CT.test_theSizeCapIs10MiB...` |
| j2 | early abort on bytes written skipped | KILLED | `JE.test_aBodyWithNoLengthIsCancelledOnceTheCapIsCrossed`, `JE.test_aDeclaredLength...` |
| j3 | early abort removed entirely | KILLED | `JE` and `CT` tests (5 failing) |
| k1 | moved file not deleted when the attachment is rejected | KILLED | `JD.test_bytesTheSystemRejects...`, `PV.test_pathAttachmentRejected` |
| k2 | received file not deleted on a drop | KILLED | `JD.test_aFileOverTheCapIsDeletedAndNotAttached`, `PV.test_pathOversizeAfterDownload` |
| k3 | moved file not deleted when the attach loses the race | **SURVIVED** | none. **B3** |
| l1 | MIME match case-sensitive | KILLED | `FT.test_mimeMatchIsCaseInsensitive` |
| l2 | unlisted URL extension passes through | KILLED | `FT.test_aPathLikeExtensionNeverReachesTheResult`, `FT.test_unknownMimeAndUnlistedUrlExtension...` |
| l3 | URL extension not lowercased | KILLED | `FT.test_unknownMimeFallsBackToAnAllowlistedUrlExtension` |
| l4 | job passes the temp location, not the original URL, to the file-type fallback | SURVIVED | none. N1 |
| m1 | registry: `delivery_id` fallback removed | KILLED | `FA.test_expiryStillFindsTheJobWhenTheHostChangedAnotherUserInfoKey`, `RG.test_matchesBySharedDeliveryId...` |
| m2 | registry matches everything | KILLED | `RG.test_aDeliveryIdOnOnlyOneSide...`, `RG.test_anEmptyDeliveryId...` |
| m3 | registry skips finished jobs | KILLED | `RG.test_stillReturnsAFinishedJob` |
| m4 | registry: ids equal returns true, else falls to userInfo equality | SURVIVED, equivalent | different ids make `userInfo` unequal anyway |
| n | non-2xx attaches anyway | KILLED | `JB.test_notFoundDropsWithTheUntouchedContent`, `FA.test_aNonSuccessStatus...` |
| n2 | status accepts 200..<500 | KILLED | `JB.test_notFound...`, `PV.test_pathNotFound` |
| o1 | missing key calls the handler twice | KILLED | `FA.test_aMissingKeyCallsTheHandlerOnce...`, `FA.test_aNonStringValue...` |
| o2 | missing key starts a request | KILLED | same two tests (`requestedURLs` is empty) |
| p | session not invalidated in `finish` | KILLED | `JB.test_theJobIsReleasedAfterSuccess/StatusDrop/TransportDrop` |
| q | extension reads another payload key | KILLED | 31 failing |
| r1 | invalid-URL path does not call the handler | KILLED | `FA.test_aFileUrlIsInvalid`, `PV.test_pathInvalidScheme` |
| s1 | empty-string guard removed | SURVIVED, equivalent | `URL(string: "")` is `nil` |
| s2 | host-less https accepted | KILLED | `UR.test_httpsWithoutHostIsInvalid` |
| t1 | success clears the title | KILLED | `FA.test_aValidUrlAttachesOnceAndKeepsEveryOtherField`, `JE.test_aRedirectChainThatEndsOnHttps...` |
| t2 | success attaches two attachments | KILLED | 13 tests |
| t3 | expiry fires the job's content, not the host's | KILLED | `FA.test_expiryThroughTheFacade...`, `FA.test_expiryStillFinds...` |
| t4 | nil-content expiry calls the handler | KILLED | `FA.test_expiryWithNilContentCallsNoHandler` |
| t5 | no-match expiry does not call the handler | KILLED | `FA.test_expiryWithNoMatchingJobCallsTheHostHandlerDirectly` |
| t6 | `didCompleteWithError(nil)` no-file branch removed | KILLED | `JB.test_completionWithoutAFileDropsAsNoFile` (assertion failure then a crash; my first classifier missed it, re-read by hand) |
| t7 | deadline timer not cancelled on finish | SURVIVED, equivalent | the late timer calls `finish`, which returns at once; the work item holds `self` weakly |
| t8 | live configuration `.ephemeral` becomes `.default` | SURVIVED | none. N2 (not an AC) |
| t9 | default deadline 25 s | KILLED | `CT.test_theDeadlineIs20SecondsAsALiteral`, `DR.test_defaultLimits...` |
| t11 | status drop reported with another reason | KILLED | `JB.test_notFound...`, `FA.test_aNonSuccessStatus...` |
| t12 | redirect refusal answers `completionHandler(request)` instead of `nil`, then still cancels | **SURVIVED** | none. The http target **is requested** (probe). **B2** |
| v4 | `didReceive` does not register the job | KILLED | `FA.test_expiryThroughTheFacade...`, `FA.test_expiryLeavesAJobOfAnotherNotification...` |
| w | idle deadline: every `didWriteData` re-arms the timer | **SURVIVED** | none. Probe with 64 KiB chunks: elapsed 1.12 s, no drop (baseline 0.35 s). **B1** |
| x | expiry loop runs over no job | KILLED | `FA.test_expiryLeavesAJobOfAnotherNotification...`, `FA.test_expiryStillFinds...` |
| y | ObjC class name `NottiNSE` | KILLED | Objective-C compile error in `NottiExtensionObjCTests.m` |
| z | selector label changed | KILLED | Objective-C compile error (`no known class method for selector 'serviceExtensionTimeWillExpireFor:contentHandler:'`) |

### Script mutants (`check-nse-logging.sh`), by fixture on a scratch copy of the tree

No committed test runs the script (TESTING.md: "Scripts / CI workflow: none, verified by running the script against a passing and a failing input"), so a script mutant cannot fail a committed test; I judged them by fixture.

| Id | Check | Result |
| --- | --- | --- |
| r1s | drop `os_log` from the pattern, fixture with `os_log("x")` | rc 0: mutant undetected without a fixture. Original: rc 1 |
| r2s | stop stripping comments, comment-only fixture | rc 1 (false positive). The real tree has no banned word in a comment, so only a fixture tells the two apart. Original: rc 0 |
| fixtures | each banned token (`NSLog`, `print(`, `print (`, `debugPrint(`, `dump(`, `dump (`, `os_log(`, `localizedDescription`, `Swift.print(`, a token inside a string) rc 1; `//`, `/* */`, `///` comment-only, `blueprint`, `isDumping` rc 0; empty dir rc 1; nested dir rc 1 | as designed |

---

## Probes

| Probe | Result |
| --- | --- |
| (i) Does the deadline cap a trickling response, not only idle time? | **Production: yes.** Throwaway test, 20 chunks of 64 KiB every 50 ms (progress callbacks fire), deadline 0.3 s: handler once, log `["rich media dropped: deadline"]`, elapsed 0.348 s. There is no re-arm anywhere in production (one schedule site, `start(url:)`). **But the committed trickle tests are blind to an idle-reset regression**: they use 50-byte and 10-byte chunks, for which `URLSession` never calls `didWriteData`, so mutant w (re-arm in `didWriteData`) passes them. With the same mutant the probe above fails (elapsed 1.12 s, attached). B1 |
| (ii) Handler ever called twice under expiry racing completion? | The 30x loop of 39 tests (Expiry, Facade, Deadline, Privacy): 1170 passes, 0 failures. Plus a throwaway stress test, 3 runs x 300 jobs, each with a random deadline of 0.3 to 6 ms and an `expire(with:)` from another queue at a random 0 to 6 ms, over a stub that completes at once: **900 jobs, every handler count exactly 1; temp files left on disk equal the attachments returned (250/250, 260/260, 252/252)**. About 15 % of the jobs lost the race after the file was on disk, so the lost-race cleanup branch was exercised. With mutant k3 the same probe fails (286 files for 261 attachments, 25 leaked) |
| (iii) Any log line with URL, host, query, title, body or `localizedDescription`? | Three `NottiLogger.log` call sites in total (`grep`): `NottiNotificationServiceExtension.swift:79`, `NottiRichMediaJob.swift:99` and `:102`. Each message is `"rich media dropped: <code>"` with a fixed code or `domain#code`. `grep localizedDescription Sources/NottiSDKExtension` is empty. No `print`, `NSLog`, `os_log`, `dump`. The sentinel tests cover 13 paths, and mutants d1 to d5 (host, query, raw value, description) are all killed |
| (iv) Is `nonisolated(unsafe)` on `NottiRichMediaJob.userInfo` justified? | Yes. It is a `let`, assigned once in `init` from `content.userInfo as NSDictionary` (an immutable snapshot) and only read (`isEqual`, subscript) by the registry. No write exists. The reason for the annotation is that `NSDictionary` is not `Sendable`; it was needed for the `pod lib lint` warning (commit `171f66e`). Residual: the values inside the dictionary are the push's own objects; nothing in the SDK mutates them |
| (v) Extension sources free of UIKit, `UIApplication`, `NottiSDK`? | `grep -rnE "UIKit|UIApplication|beginBackgroundTask|registerForRemoteNotifications|CLLocationManager|import NottiSDK"` on `Sources/NottiSDKExtension`: no match. Imports are `Foundation`, `UserNotifications`, `NottiShared` (behind `canImport`). `Package.swift`: target dependency `NottiShared` only. Podspec subspec `Extension` depends on `NottiSDK/Shared` only |
| (vi) `PUBLIC_SURFACE.txt` and ObjC naming | Diff against `fe26920`: exactly three added lines, the class and the two static methods, nothing else. The two `NottiSDKExtensionModule` lines are gone with the placeholder. ObjC: `+didReceive:withContentHandler:` and `+serviceExtensionTimeWillExpireFor:contentHandler:`, class `NottiNotificationServiceExtension`, as spec NSE-16 reads now |
| (vii) Test count and mapping | 584 real, 584 in `traceability.md`. Per-file counts in its section 2 match the source (sum 108 + 3). All 105 `XX.test_name` references in the traceability resolve to a real test function (script); I read the bodies of the tests in the AC table. None tautological: NSE-18 tests assert literals. Not vacuous for the ACs marked Met, except the three sentences in B1 to B3 |
| (viii) Tautological, vacuous or time-flaky tests | No tautology found. Vacuous against a realistic regression: the trickle tests (B1), the redirect tests (B2), and there is no test of the lost-race cleanup (B3). Time-based `settle()` sleeps are used throughout; no flake in 3 whole-bundle runs and 30 runs of the timing-heavy classes |
| (ix) http redirect target requested? | Baseline: `StubURLProtocol.requestedURLs` has only the https URL. With mutant t12 it also has the http URL, in 3 of 3 runs. No committed test asserts it. B2 |

---

## Findings

### BLOCKING

**B1. NSE-10 second sentence ("A response that keeps sending bytes SHALL NOT extend the deadline") is not provable by the committed tests.**
- Where: `Tests/NottiSDKExtensionTests/NottiRichMediaJobDeadlineTests.swift:35` (`test_aResponseThatTricklesBytesStillEndsAtTheDeadline`) and `:68` (`test_theDeadlineIsMeasuredFromStartNotFromTheLastByte`). Production under test: `NottiRichMediaJob.swift:59-66` (timer) and `:136-144` (`didWriteData`).
- What: both tests use 50-byte and 10-byte chunks. `URLSession` batches those into its temp file and does not call `didWriteData`, so they cannot detect a regression that re-arms the timer on progress.
- Failing scenario: someone "improves" `didWriteData` to cancel and re-arm `deadlineItem` (mutant w). A CDN that trickles 1 KiB every 5 s then keeps the extension alive past the OS budget of about 30 s; the OS kills it and the push is lost. All 584 tests stay green.
- Evidence: mutant w survives the whole bundle. My probe (64 KiB x 20 chunks, 50 ms apart, deadline 0.3 s) passes on `HEAD` (elapsed 0.348 s) and fails on w (elapsed 1.12 s, no drop log).
- Fix (test only): add that probe as a test in `NottiRichMediaJobDeadlineTests`: `Behavior(headers: ["Content-Type": "image/png"], chunks: Array(repeating: Data(count: 64 * 1024), count: 20), chunkInterval: 0.05)`, `shortDeadline(0.3)`, assert one call, log `["rich media dropped: deadline"]`, elapsed < 0.8 s. Re-run mutant w and require it to fail.

**B2. "Only https media is fetched ... after redirects" (Goals, NSE-04 design D4) is not proven: nothing asserts the http redirect target is never requested.**
- Where: `NottiRichMediaJob.swift:123-133` (`willPerformHTTPRedirection`). Tests: `NottiRichMediaJobEarlyAbortTests.swift:20` and `:36`.
- What: the tests assert no body byte is served (`servedBytes(for: httpTarget) == 0`) and that the handler ends once, not that the http request is never started.
- Failing scenario: a refactor answers `completionHandler(request)` (continue) and relies on the following `finish` to cancel (mutant t12). The SDK then opens a cleartext connection to the `http://` target before cancelling (the stub saw `startLoading` for the http URL in 3 of 3 runs). In a host that allows arbitrary loads (ATS exception) that is a real cleartext request. Every committed test stays green.
- Evidence: mutant t12 survives. On `HEAD` the probe shows `requestedURLs` = only `https`.
- Fix (test only): in both redirect tests also assert `StubURLProtocol.requestedURLs.filter { $0.scheme == "http" }` is empty. Re-run t12 and require a failure.

**B3. NSE-09 on the race path is unproven: no test fails if the file moved by a job that loses the race is not deleted.**
- Where: `NottiRichMediaJob.swift:200` (`if !finish(.attached(attachment)) { try? fileManager.removeItem(at: destination) }`).
- What: when the deadline or an expiry call wins between the top-of-function `isFinished` guard and `finish`, the job has already moved the file into `directory`; only this line removes it. No committed test reaches it (the sequential tests never lose the race).
- Failing scenario: delete that line (mutant k3). A completion that lands within milliseconds of the 20 s deadline, or of an expiry call, leaves a downloaded media file in the extension's temp directory; repeated over many pushes this fills the extension container. All 584 tests stay green.
- Evidence: mutant k3 survives. My stress probe (300 jobs per run, random deadline 0.3 to 6 ms and concurrent expiry) fails on k3 in 1 of 1 run (286 files for 261 attachments) and passes on `HEAD` in 3 of 3 (files == attachments).
- Fix (test only): add a stress test to `NottiRichMediaJobDeadlineTests` or `...ExpiryTests` (about 300 iterations, around 3 s): start jobs over a stub that completes at once with a random 0.3 to 6 ms deadline and a concurrent `expire(with:)`, then assert every recorder has count 1 and `directoryContents().count` equals the number of results with an attachment. Re-run k3 and require a failure. (A deterministic seam, for example an injectable hook between the guard and `finish`, is the alternative.)

### NON-BLOCKING

- **N1 (l4, NSE-07 wiring).** `NottiRichMediaJob.swift:181` passes `downloadTask.originalRequest?.url ?? location` to the file-type function. `NottiMediaFileType` is covered by unit tests, but no job-level test serves a response without a MIME type and a URL ending in `.mp3` (or `.png`) and asserts the attached file's extension. Mutant l4 (pass `location`) survives; the effect would be a `.jpg` name on an mp3 download and the OS refusing it, so the original plain content shows. Add one job test with no `Content-Type` and a `.mp3` URL.
- **N2 (t8, not an AC).** `NottiRichMediaEnvironment.live` (`makeConfiguration`: ephemeral, `reloadIgnoringLocalCacheData`, `waitsForConnectivity = false`; `directory`: `temporaryDirectory/notti-media`) is never exercised: every test injects its own configuration and directory. `.default` instead of `.ephemeral` passes the suite. A one-assert test on `NottiRichMediaEnvironment.live.makeConfiguration()` would pin design D8.
- **N3 (`scripts/check-nse-logging.sh`).** Textual limits, none of them an AC: (a) the comment stripper is not string-aware, so a `//` inside a string literal blanks the rest of the line: `let u = "https://x.invalid"; NSLog("x")` exits 0 (probe); (b) not caught: `let f = print`, `fputs(..., stderr)`, `Logger()` / `os.Logger()`; (c) no committed regression test for the script, so a mutant that drops a token or starts flagging comments is invisible to the suite (r1s, r2s). The header already says string literals are not stripped; (a) is the unexpected one.
- **N4 (design Risk, recorded).** `NottiRichMediaRegistry.jobs(matching:)` matches by equal `userInfo`, or by a shared non-empty `delivery_id`. If the host mutates `bestAttemptContent.userInfo` and the push has no `delivery_id`, no job matches, `serviceExtensionTimeWillExpire` calls the host handler directly (`NottiNotificationServiceExtension.swift:97-99`) and the still-running job can call it again later (second call). Pinned by `RG.test_aDeliveryIdOnOnlyOneSideFallsBackToUserInfoEquality`. It needs a host that rewrites `userInfo` and a push without `delivery_id`; the doc-comment example does not. Cheap hardening: when nothing matches and exactly one unfinished job exists in the registry, expire that one. Validate with the backend that every push carries `delivery_id` [Incerto, not checked].
- **N5 (equivalent survivors).** b1, m4, s1, t7 survive because they do not change behavior (reasons in the ledger). They could be deleted from production without effect (`task?.cancel()` next to `invalidateAndCancel()`, the `isEmpty` guard, the timer cancel); leaving them is fine for readability.
- **N6 (`PrivacyInfo.xcprivacy`).** Unchanged, `C617.1` still declared; the code now reads `fileSizeKey`, which is not on Apple's file-timestamp list, so it is a harmless over-declaration. Design D9 already flags this; confirm at `example-and-release` with an App Store validation [Incerto].
- **N7 (doc snippet).** The class comment says `import NottiSDKExtension`. That is the SPM module name; under CocoaPods all subspecs compile into the module `NottiSDK`. Wiring docs are out of scope for this feature; carry it to `example-and-release`.
- **N8 (category check).** `NottiRichMediaPrivacyTests.test_everyLogCallInTheExtensionSourcesUsesCategoryNse` reads the source text line by line (the sink does not carry the category). It kills d6, but a log call split over several lines would fail it; acceptable and recorded in `traceability.md`.
- **N9 (doc not audited).** I did not read `tasks.md` line by line (its "Done when" boxes are not a blocking source). `spec.md`, `design.md`, `traceability.md`, `AGENTS.md`, `TESTING.md` and the RN reference were read; `STATE.md` was not.
- **N10 (traceability wording).** `traceability.md` NSE-13 says the URL-logging edit "failed 21 assertions"; my equivalents (d1, d4) failed 19 tests. Not a defect, a different counting unit.

---

## Not proven

- Real device, real push, real APNs `mutable-content` delivery: the OS does not run an NSE in the Simulator; every test calls the helper directly.
- The `@objc(NotificationService)` principal-class wiring in a host target, the Xcode extension target, `Info.plist`, App Group: all `example-and-release`.
- The real `UNNotificationAttachment` limits on a device (audio over about 5 MB, video over about 50 MB; the 6 MiB MP3 rejection is simulator behavior).
- The actual extension memory and time limits under iOS (about 30 s and a small memory cap), and that the 20 s deadline leaves enough time on a slow device.
- Static CocoaPods linking of the `Extension` subspec into a real extension target (`pod lib lint` passes, but no host app was integrated). Duplicate symbols when the app and the extension both link `NottiSDK/Shared` are untested.
- `URLSession` behavior over a real network (real TLS, real redirects, HTTP/2, content-length absent with chunked encoding): all tests use `StubURLProtocol`. The spike (macOS) and its simulator re-proof use the same stub.
- Whether the Notti backend sends `delivery_id` on every push (N4) and whether `PrivacyInfo.xcprivacy` is accepted by App Store validation (N6).
- The race window in `didFinishDownloadingTo` is only probed by my stress test, not pinned by the suite (B3).

## Cleanup

All mutants reverted; `git status --short` after each was empty. Probe tests (`ProbeRaceTests.swift`, `ProbeTrickle.swift`) were created in `Tests/NottiSDKExtensionTests` and deleted before the end. Logs, scratch copies, the two clean DerivedData folders and the harness are in the session scratchpad only. The extension tests use no `notti_prefs`; no simulator state was left. In the scratchpad I deleted an earlier `ledger.tsv` left by a previous session (throwaway). Nothing was committed or pushed.

---

# Round 2

**Date**: 2026-10-11. **HEAD**: `2b68b49`. **Verdict: PASS.** B1, B2 and B3 are closed; no new blocker. Production is untouched: `git diff 4d1a513..HEAD -- Sources` is empty (0 bytes). The range touches only `Tests/NottiSDKExtensionTests/NottiRichMediaJobDeadlineTests.swift`, `NottiRichMediaJobEarlyAbortTests.swift` and `traceability.md`. I did not rely on the executor's claims: every mutant below was applied, run against the whole `NottiSDKExtensionTests` bundle through the watchdog `run.sh` (iPhone 17 Pro, one `xcodebuild` at a time), reverted with `git checkout --`, and `git status --short` was checked clean after each (only the untracked `validation.md`).

## Mutants (original round-1 mutants re-applied from their descriptions, plus fresh variants)

| Id | Mutation | Valid | Result | Killed by |
| --- | --- | --- | --- | --- |
| w | re-arm the deadline timer on every `didWriteData` (round-1 edit) | yes | KILLED | `JL.test_aResponseThatSendsLargeChunksStillEndsAtTheDeadlineBecauseProgressDoesNotRearmIt` |
| w2 (fresh) | same re-arm, placed at the END of `didWriteData` (after the oversize check) | yes | KILLED | same test |
| w3 (fresh) | re-arm only on the FIRST `didWriteData` (one-time extension) | yes | SURVIVED | none (see N6) |
| t12 | refusal answers `completionHandler(request)` instead of `nil`, then cancels | yes | KILLED | `JE.test_aRedirectToHttpEndsBeforeAnyBodyByteIsServedEvenWhenTheStubIgnoresTheRefusal`, `JE.test_aRedirectToHttpWhoseTargetNeverRespondsStillEndsAtOnce` |
| t12c (fresh) | `finish` first, then `completionHandler(request)` | yes | KILLED | the same two |
| t12b (fresh) | http allowed on the SECOND redirect only (hop counter) | yes | SURVIVED | none (see N7) |
| t12d (fresh) | refusal never answers `completionHandler`; `finish` still cancels | yes | SURVIVED, equivalent | none: no http request is made, the task is cancelled by `finish`; observable behavior is the same |
| k3 | remove the lost-race `removeItem` (`NottiRichMediaJob.swift:200`) | yes | KILLED | `JL.test_aCompletionRacingTheDeadlineOrExpiryLeavesNoFileWithoutAnAttachment` |
| k3b (fresh) | cleanup skipped only when the race is lost to EXPIRY (flag set in `expire`) | yes | KILLED | same test |
| k3c (fresh) | cleanup skipped only when the race is lost to the DEADLINE (flag set in the timer) | yes | KILLED | same test |
| k3d (fresh) | cleanup removes `location` (already moved) instead of `destination` | yes | KILLED | same test |

11 mutants, 0 invalid (each edit matched exactly once and built). 8 killed, 3 survived (1 equivalent: t12d; 2 judged non-blocking: w3, t12b). The 3 original blockers are all killed, with 2 to 3 variants each (w: 1 of 2 variants killed, k3: 3 of 3, t12: 1 of 2 killed plus 1 equivalent and 1 contrived survivor).

## Surviving variants (non-blocking, my judgment; Julio can overrule)

- **N6 (w3).** A one-shot re-arm on the first progress callback extends the deadline by the time to first byte. The committed test cannot see it: its chunks start at 0.05 s and the bound is `elapsed < 0.8` with a 0.3 s deadline, so a 0.05 s extension is inside the slack, and tightening the bound to catch it would be flaky. The realistic regression (re-arm on progress, any placement) is killed. If wanted: a stub whose first chunk arrives at about 0.25 s with deadline 0.3 s and bound `< 0.45`. It maps to NSE-10 second sentence only for that one-shot shape; I did not require it.
- **N7 (t12b).** No test redirects https -> https -> http, so a stateful guard that lets the second hop through survives. The production guard is stateless and runs on every hop, so this needs a deliberate hop counter; the realistic regression (t12 and t12c) is killed. Cheap hardening: one test with a two-hop chain and `assertNoHttpRequest()`. Note the second barrier (final-URL check) would still discard the file, but the cleartext request would have been made.

## Flakiness and bounds

| Run | Result |
| --- | --- |
| `NottiRichMediaJobDeadlineTests` (6) + `NottiRichMediaJobEarlyAbortTests` (5), `-test-iterations 30` | 330 of 330 passed, 0 failures (260 s) |
| Race test alone, `-test-iterations 30` | 30 of 30 passed (54 s), about 1.8 s per iteration |
| Same two classes x10 under load: 20 concurrent `yes` on a 10-core machine, load average peak 128 | 110 of 110 passed, 0 failures |
| Race test + large-chunk (bound) test x10 under the same load | 20 of 20 passed, 0 failures |

The `elapsed < 0.8` bound (deadline 0.3 s) held in all of them, including with the machine at load average above 100. Not tautological: the large-chunk test fails on w and w2, the race test fails on k3, k3b, k3c and k3d (so it does hit both the deadline-loses and expiry-loses interleavings), and the two redirect tests fail on t12 and t12c. I could not run the loaded runs with a lower-priority load; the load was plain CPU spin, not I/O pressure.

## Gate (run by me on HEAD `2b68b49`)

| Gate | Result |
| --- | --- |
| Full suite | `** TEST SUCCEEDED **`: NottiSharedTests 14, NottiSDKTests 453, NottiSDKObjCTests 6, NottiSDKExtensionTests 110, NottiSDKExtensionObjCTests 3 = 586, 0 failures |
| SwiftLint 0.65.1 `--strict` (Docker) | 0 violations in 100 files |
| Guards | extension-safety ok, launch-hook-purity ok, no-url-open ok, nse-logging ok (10 files), package-graph ok, public-surface ok (71 declarations), version ok (0.1.0) |
| `check-hook-linked.sh spm` | `loadCount=1 installCount=1`, ok |
| `check-hook-linked.sh pod` | ok |
| `pod lib lint NottiSDK.podspec --platforms=ios` | passed validation |
| `pod lib lint ... --subspec=Extension` | passed validation |
| Strict device build `NottiSDK` (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `GCC_TREAT_WARNINGS_AS_ERRORS`) | rc 0 |
| Strict device build `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES` | rc 0 |

## Traceability

`traceability.md` says 586 (Shared 14, SDK 453, ObjC 6, Extension 110, Extension ObjC 3) and 6 tests in `NottiRichMediaJobDeadlineTests`; the source has exactly these counts (grep of test functions per target: 14, 453, 6, 110, 3). Section 2 file counts match the `Executed` lines of the run. All 109 distinct `XX.test_name` references resolve to a real test function (script); the only two non-resolving strings are the intentional globs `PV.test_path*` and `JB.test_*IsAttached`. The two new tests are cited under NSE-09 and NSE-10 and exist.

## Skipped or unproven

- End-to-end on a real device is still unproven (the OS does not run a Notification Service Extension in the Simulator); unchanged from round 1 and recorded in `traceability.md`.
- N1 (l4) and N2 (t8) from round 1 remain open as non-blocking; I did not re-run them.
- The 4 equivalent round-1 survivors (b1, m4, s1, t7) were not re-run.
- Nothing committed or pushed. Working tree: only the untracked `validation.md`.
