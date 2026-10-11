# NSE Rich Media Tasks

**Design**: `.specs/features/nse-rich-media/design.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: `delegate-integration` done (474 tests)
**Status**: Draft

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Generated from codebase, project guidelines and spec. Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: 474 tests (Shared 14, SDK 453, ObjC 6, Ext 1). Counts below are minimums per task; the total never drops.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| `NottiRichMediaURL` | unit | absent, non-string, empty, unparsable, `file:`, `http:`, `ftp:`, `HTTPS://`, no host, valid | `Tests/NottiSDKExtensionTests/NottiRichMediaURLTests.swift` | `-only-testing:NottiSDKExtensionTests/NottiRichMediaURLTests` |
| `NottiMediaFileType` | unit | five MIME types, mixed case, unknown MIME with and without allowlisted URL extension | `Tests/NottiSDKExtensionTests/NottiMediaFileTypeTests.swift` | same, `NottiMediaFileTypeTests` |
| `NottiHandlerGate` | unit | one call from many threads, second `fire` returns false | `Tests/NottiSDKExtensionTests/NottiHandlerGateTests.swift` | same |
| `NottiRichMediaLimits`, `NottiRichMediaDropReason` | unit | literal defaults, fixed codes, no URL in any code | `Tests/NottiSDKExtensionTests/NottiRichMediaDropReasonTests.swift` | same |
| Test support (`StubURLProtocol`, `LogSink`) and simulator spike re-proof | unit | redirect refusal needs `cancel()`, early cancel by declared length, `userInfo` equality of two copies | `Tests/NottiSDKExtensionTests/Support/`, `NottiRichMediaSpikeTests.swift` | same |
| `NottiRichMediaJob` | unit | success per type, drops, once-only handler, temp files, deadline, expiry | `Tests/NottiSDKExtensionTests/NottiRichMediaJob*Tests.swift` | same |
| `NottiRichMediaRegistry` | unit | match by `userInfo`, bound of 16, finished job still found | `Tests/NottiSDKExtensionTests/NottiRichMediaRegistryTests.swift` | same |
| `NottiNotificationServiceExtension` facade | unit | both entry points through an injected environment, no-op cases | `Tests/NottiSDKExtensionTests/NottiNotificationServiceExtensionTests.swift` | same |
| Cross-cutting (PII, handler count, temp files) | unit | sentinel and call count over every path | `Tests/NottiSDKExtensionTests/NottiRichMediaPrivacyTests.swift` | same |
| Objective-C layer | unit (ObjC) | both selectors callable | `Tests/NottiSDKExtensionObjCTests/*.m` | same, scheme `NottiSDK-Package` |
| `scripts/check-nse-logging.sh`, CI | none | run against a passing and a failing tree | - | the script |
| Packaging (`Package.swift`, `PUBLIC_SURFACE.txt`) | none | scripts and `pod lib lint` | - | the scripts, `pod lib lint` |
| Docs (`traceability.md`, specs, STATE) | none | every NSE-xx mapped to a test | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially.

## Gate Check Commands

> Generated from codebase (`.github/workflows/ci.yml`, `.specs/codebase/TESTING.md`). Xcode 27 note: run `xcodebuild test` through the watchdog in the scratchpad (`run.sh`; a failing run does not terminate), and do not pipe `xcodebuild` into `grep`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:NottiSDKExtensionTests/<Class>` |
| Full | After T8, T13 and T16 | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + the guard scripts + the strict device builds (app and `APPLICATION_EXTENSION_API_ONLY=YES` extension) + `pod lib lint NottiSDK.podspec --platforms=ios` |
| Build | Build-only checks and phase completion | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |

---

## Rules (apply to every task)

1. New code, so `write-swift` and `swift-concurrency` guidance applies, but in Swift 5 mode (AD-002): no actors, no `AsyncStream`, no `async` in the helper.
2. Everything lives in `Sources/NottiSDKExtension`. No `import UIKit`, no `UIApplication`, no dependency on `NottiSDK` (NSE-14). Logging only through `NottiLogger` category `nse`; no `NSLog`, `print`, `os_log` or `localizedDescription` (NSE-13). Errors as `"\(error.domain)#\(error.code)"`.
3. No log line, error code, test name or fixture carries a real URL. Fixtures use `example.invalid` and `fixture`. A log line never contains the URL, host, query, title or body.
4. Every job exit goes through one `finish` guarded by a lock; the handler goes through `NottiHandlerGate`. No other code calls the host's handler.
5. Tests never touch the network. `URLSession` comes from an injected configuration with `StubURLProtocol`. The temp `directory` is a per-test subdirectory removed in `tearDown`.
6. Contract values (`notti_image_url`, 10 MiB, 20 s, five types) are asserted as literals, not through the constants the code reads.
7. Do not run two `xcodebuild` processes on the same checkout. Use the watchdog.
8. Each task is one commit, conventional style, with no AI attribution.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe). Suggested split for sub-agents: T1 to T8, then T9 to T16.

### Phase 1: Building blocks

```
T1
T2
T3
T4
```

No edges: independent. They run in this order.

### Phase 2: Support and the job

```
T4 ──→ T5
T2 ──→ T6
T3 ──→ T6
T4 ──→ T6
T5 ──→ T6
T6 ──→ T7
T7 ──→ T8
```

### Phase 3: Time and expiry

```
T8 ──→ T9
T9 ──→ T10
```

### Phase 4: Facade, guards, interop, close

```
T1 ──→ T11
T10 ──→ T11
T11 ──→ T12
T11 ──→ T13
T11 ──→ T14
T4 ──→ T15
T11 ──→ T15
T12 ──→ T16
T13 ──→ T16
T14 ──→ T16
T15 ──→ T16
```

Sequential order used in Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14 → T15 → T16.

### Diagram-definition cross-check

| Task | Depends on (definition) | Edges in the diagram |
| --- | --- | --- |
| T1 | None | none |
| T2 | None | `T2 → T6` |
| T3 | None | `T3 → T6` |
| T4 | None | `T4 → T5`, `T4 → T6`, `T4 → T15` |
| T5 | T4 | `T4 → T5` |
| T6 | T2, T3, T4, T5 | `T2 → T6`, `T3 → T6`, `T4 → T6`, `T5 → T6` |
| T7 | T6 | `T6 → T7` |
| T8 | T7 | `T7 → T8` |
| T9 | T8 | `T8 → T9` |
| T10 | T9 | `T9 → T10` |
| T11 | T1, T10 | `T1 → T11`, `T10 → T11` |
| T12 | T11 | `T11 → T12` |
| T13 | T11 | `T11 → T13` |
| T14 | T11 | `T11 → T14` |
| T15 | T4, T11 | `T4 → T15`, `T11 → T15` |
| T16 | T12, T13, T14, T15 | the four edges into T16 |

All match. No `[P]` task.

---

## Task Breakdown

### T1: `NottiRichMediaURL`

**What**: Pure parser of `userInfo[NottiPayloadKeys.imageUrl]` into `absent`, `invalid` or `valid(URL)`. `valid` needs a `String`, non-empty, a parsable URL, scheme `https` (any case) and a host.
**Where**: `Sources/NottiSDKExtension/NottiRichMediaURL.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaURLTests.swift`
**Depends on**: None
**Reuses**: `NottiPayloadKeys.imageUrl`
**Requirement**: NSE-02, NSE-03

**Done when**:

- [x] Missing key and a non-`String` value give `absent`
- [x] Empty string, unparsable text, `file:`, `http:`, `ftp:`, a custom scheme and a URL with no host give `invalid`
- [x] `HTTPS://` and a valid `https` URL give `valid`
- [x] Gate check passes: quick
- [x] Test count: at least 9 new, total at least 483

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): parse and validate the rich media URL`

---

### T2: `NottiMediaFileType`

**What**: `fileExtension(mimeType:url:)`. MIME lowercased and matched to `jpg`, `png`, `gif`, `mp4`, `mp3`; else the URL extension (lowercased) when allowlisted; else `jpg`. Ports the 3 RN extension tests and adds case and unknown-MIME cases.
**Where**: `Sources/NottiSDKExtension/NottiMediaFileType.swift`, `Tests/NottiSDKExtensionTests/NottiMediaFileTypeTests.swift`
**Depends on**: None
**Reuses**: RN `fileExtension(for:fallbackFrom:)` and `fileExtension(forMimeType:)` (`52e4b55`)
**Requirement**: NSE-07

**Done when**:

- [x] Each of the five MIME types maps to its extension, also in mixed case
- [x] An unknown MIME falls back to an allowlisted URL extension, then to `jpg`
- [x] A URL extension outside the allowlist (including a path-like string) never reaches the result
- [x] Gate check passes: quick
- [x] Test count: at least 8 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): derive the attachment file type`

---

### T3: `NottiHandlerGate`

**What**: A once-only wrapper around the host's `contentHandler`. `fire(_:)` returns whether it called the handler; calls outside the lock; safe from any thread.
**Where**: `Sources/NottiSDKExtension/NottiHandlerGate.swift`, `Tests/NottiSDKExtensionTests/NottiHandlerGateTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: NSE-11 (single call), goal "never twice"

**Done when**:

- [x] Two sequential `fire` calls call the handler once and return `true`, then `false`
- [x] 50 concurrent `fire` calls call the handler exactly once
- [x] The handler is called outside the lock (a handler that calls `fire` again does not deadlock)
- [x] Gate check passes: quick
- [x] Test count: at least 3 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): once-only content handler gate`

---

### T4: `NottiRichMediaLimits` and `NottiRichMediaDropReason`

**What**: `NottiRichMediaLimits` (`maxBytes = 10 * 1024 * 1024`, `deadline = 20`, injectable) and `NottiRichMediaDropReason` with the fixed log codes from the design (`invalid_url`, `redirect_not_https`, `http_<status>`, `oversize`, `no_file`, `deadline`, `expired`, `transport:`, `move_failed:`, `attachment_rejected:` plus `domain#code`).
**Where**: `Sources/NottiSDKExtension/NottiRichMediaLimits.swift`, `Sources/NottiSDKExtension/NottiRichMediaDropReason.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaDropReasonTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: NSE-13, NSE-18

**Done when**:

- [x] Default limits asserted as literals (`10485760`, `20`)
- [x] Each reason's code is asserted as a literal string; an error reason carries only `domain#code`
- [x] No code can contain a URL: the error-carrying cases take `NSError` domain and code only
- [x] Gate check passes: quick
- [x] Test count: at least 4 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): rich media limits and drop reasons`

---

### T5: Extension test support and simulator spike re-proof

**What**: Copy and extend `StubURLProtocol` (status and headers, declared `Content-Length`, redirect, body chunks, never-finishing, served-byte counter) and `LogSink` into the extension test target, plus a helper that builds a tiny valid PNG, JPG, GIF, MP4 and MP3 byte sample. Add `NottiRichMediaSpikeTests` that re-prove on the simulator the three design spike results: refusing a redirect needs `cancel()`, an early cancel by declared length stops the body, and two `mutableCopy` contents have equal `userInfo` while a different one does not.
**Where**: `Tests/NottiSDKExtensionTests/Support/StubURLProtocol.swift`, `Support/LogSink.swift`, `Support/MediaSamples.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaSpikeTests.swift`
**Depends on**: T4
**Reuses**: `Tests/NottiSDKTests/Support/StubURLProtocol.swift`, `LogSink.swift`
**Requirement**: design Risks (spike on macOS only), NSE-04, NSE-11, NSE-17

**Done when**:

- [x] The three spike behaviors hold on the iOS simulator. **If one does not, STOP and report** (it reopens D4 or D10 in the design)
- [x] The stub never touches the network
- [x] Gate check passes: quick
- [x] Test count: at least 3 new

**Tests**: unit
**Gate**: quick
**Commit**: `test(nse): stub support and simulator re-proof of the design spike`

---

### T6: `NottiRichMediaJob` happy path and simple drops

**What**: The job class: environment, own `URLSession` (delegate, serial queue), one `finish`, gate, directory creation. `didFinishDownloadingTo` handles status 2xx (else `http_<status>`), move into `directory/<uuid>.<ext>` and `UNNotificationAttachment`; `didCompleteWithError` handles `transport` and `no_file`. Logs a drop as one `.error` line, never the URL.
**Where**: `Sources/NottiSDKExtension/NottiRichMediaJob.swift`, `Sources/NottiSDKExtension/NottiRichMediaEnvironment.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaJobTests.swift`
**Depends on**: T2, T3, T4, T5
**Reuses**: `NottiHandlerGate`, `NottiRichMediaLimits`, `NottiRichMediaDropReason`, `NottiMediaFileType`
**Requirement**: NSE-01, NSE-05

**Done when**:

- [x] PNG, JPG, GIF, MP4 and MP3 stubs each give one attachment, the other content fields equal, one handler call
- [x] 404, a transport error and no-file each give the untouched copy, one handler call, no file left in `directory`
- [x] The session is invalidated and the job released on every path (asserted with a weak reference)
- [x] Gate check passes: quick
- [x] Test count: at least 9 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): download job with attachment and simple drops`

---

### T7: Job post-download checks

**What**: In `didFinishDownloadingTo` add the final-URL scheme check (`redirect_not_https`), the size check by `URLResourceKey.fileSizeKey` (`oversize`), the `move_failed` and `attachment_rejected` paths with deletion of the moved file, and keep using `NottiMediaFileType` for the extension.
**Where**: `Sources/NottiSDKExtension/NottiRichMediaJob.swift` (modify), `Tests/NottiSDKExtensionTests/NottiRichMediaJobDropTests.swift`
**Depends on**: T6
**Reuses**: T6
**Requirement**: NSE-04 (final URL), NSE-06, NSE-08, NSE-09

**Done when**:

- [x] A stub whose final URL is `http` gives no attachment and no file left
- [x] A file over 10 MiB (no `Content-Length`) is deleted after download and not attached
- [x] A directory that cannot be written gives `move_failed` and one handler call
- [x] Bytes that `UNNotificationAttachment` rejects give `attachment_rejected` and the moved file is deleted
- [x] `directory` is empty after every drop and holds only the attachment's file after success
- [x] Gate check passes: quick
- [x] Test count: at least 6 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): validate the downloaded file before attaching`

---

### T8: Job early redirect refusal and early size abort

**What**: `willPerformHTTPRedirection` answers `nil` and finishes with `redirect_not_https` for a non-`https` target (the job cancels the task itself, spike result 3). `didWriteData` finishes with `oversize` as soon as `totalBytesExpectedToWrite` or `totalBytesWritten` exceeds `maxBytes`.
**Where**: `Sources/NottiSDKExtension/NottiRichMediaJob.swift` (modify), `Tests/NottiSDKExtensionTests/NottiRichMediaJobEarlyAbortTests.swift`
**Depends on**: T7
**Reuses**: T6, T7
**Requirement**: NSE-04, NSE-17

**Done when**:

- [x] A redirect to `http` ends with one handler call before any body byte is served, even when the stub ignores the refusal
- [x] A redirect chain that ends on `https` still attaches
- [x] A stub that declares 11 MiB is cancelled with fewer than 2 MiB served (the stub counts served bytes)
- [x] A stub with no length that sends more than 10 MiB is cancelled once the cap is crossed
- [x] Gate check passes: **full**
- [x] Test count: at least 5 new

**Tests**: unit
**Gate**: full
**Commit**: `feat(nse): refuse non-https redirects and oversize bodies early`

---

### T9: Job total deadline

**What**: A `DispatchWorkItem` on a private queue calls `finish(.dropped(.deadline))` after `limits.deadline` seconds, cancelled by `finish`. A response that keeps sending bytes does not extend it.
**Where**: `Sources/NottiSDKExtension/NottiRichMediaJob.swift` (modify), `Tests/NottiSDKExtensionTests/NottiRichMediaJobDeadlineTests.swift`
**Depends on**: T8
**Reuses**: T6
**Requirement**: NSE-10

**Done when**:

- [x] With a 0.2 s deadline, a stub that never finishes ends with one handler call, the task cancelled and no file
- [x] A stub that sends a small chunk every 50 ms still ends at the deadline
- [x] A job that finishes first cancels the timer (no second call after the deadline passes)
- [x] Gate check passes: quick
- [x] Test count: at least 3 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): enforce a total download deadline`

---

### T10: Job expiry and `NottiRichMediaRegistry`

**What**: `NottiRichMediaJob.expire(with:)` (first caller wins, cancels, cleans, logs `expired`, fires the gate with the host's content) and `NottiRichMediaRegistry` (lock, last 16 jobs including finished ones, `jobs(matching:)` by `NSDictionary.isEqual(to:)`).
**Where**: `Sources/NottiSDKExtension/NottiRichMediaJob.swift` (modify), `Sources/NottiSDKExtension/NottiRichMediaRegistry.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaRegistryTests.swift`, `Tests/NottiSDKExtensionTests/NottiRichMediaJobExpiryTests.swift`
**Depends on**: T9
**Reuses**: T3, T6
**Requirement**: NSE-11, NSE-12 (job side)

**Done when**:

- [x] `expire` on an in-flight job cancels it, calls the handler once with the host's content, and releasing the stub afterwards adds no call
- [x] `expire` on a finished job calls nothing
- [x] The registry returns only the job whose `userInfo` equals, keeps at most 16, and still returns a finished job
- [x] Two in-flight jobs with different `userInfo`: expiring one leaves the other running
- [x] `jobs(matching:)` also matches by a non-empty `delivery_id` (`NottiPayloadKeys.deliveryId`) when both sides have it, even if another `userInfo` key differs (a host that mutated its best-attempt copy); two different `delivery_id`s never match
- [x] Gate check passes: quick
- [x] Test count: at least 9 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): expiry cancels the job and the registry correlates it`

---

### T11: `NottiNotificationServiceExtension` facade

**What**: Replace the placeholder with the public `@objc(NottiNotificationServiceExtension) final class ... : NSObject` and its two `public static` entry points, plus the `internal` overloads that take an environment. `didReceive` does mutable copy, `parse`, creates and registers the job (`absent`: fire the copy; `invalid`: log once, fire the copy). The expiry entry point matches through the registry and falls back to the host's handler when no job matches; `nil` content does nothing. Update `PUBLIC_SURFACE.txt`.
**Where**: `Sources/NottiSDKExtension/NottiNotificationServiceExtension.swift` (replaces `NottiSDKExtension.swift`), `.specs/codebase/PUBLIC_SURFACE.txt`, `Tests/NottiSDKExtensionTests/NottiNotificationServiceExtensionTests.swift`
**Depends on**: T1, T10
**Reuses**: all of the above
**Requirement**: NSE-01, NSE-02, NSE-03, NSE-11, NSE-12, NSE-15

**Done when**:

- [x] Port of the 9 RN tests by intent: missing key, `file://`, `http://`, non-2xx, success, expiry with and without content, plus the 3 file-type cases already in T2
- [x] A missing key starts no request and logs nothing; an invalid value logs one line without the value
- [x] Un-copyable content calls `contentHandler(request.content)` once
- [x] Expiry through the facade cancels the right job, and with no match calls the host's handler directly
- [x] `scripts/check-public-surface.sh` passes after `--update` and the diff lists only the new class and two methods
- [x] Gate check passes: quick plus the public-surface and extension-safety scripts
- [x] Test count: at least 9 new

**Tests**: unit
**Gate**: quick
**Commit**: `feat(nse): public rich media entry points`

---

### T12: Cross-cutting sentinel, handler-count and temp-file sweep

**What**: One test class that drives every path of the facade (absent, invalid, 404, transport, oversize early and late, redirect, attachment rejected, deadline, expiry) with a sentinel in the URL host, path and query and in the title and body, then asserts: no log line contains a sentinel, the handler was called exactly once after releasing every stub and waiting, and `directory` is clean.
**Where**: `Tests/NottiSDKExtensionTests/NottiRichMediaPrivacyTests.swift`
**Depends on**: T11
**Reuses**: `LogSink`, `StubURLProtocol`, `MediaSamples`
**Requirement**: NSE-13, NSE-09, goal "never twice"

**Done when**:

- [ ] Every path above is covered in one parameterized sweep, and a deliberately logged URL makes it fail (checked once by hand, noted in the commit body)
- [ ] The sweep asserts the log level of a drop is `.error` and the category is `nse`
- [ ] Gate check passes: quick
- [ ] One `test_` method per path (no sub-test loops), so a failure names the path; test count: at least 11 new

**Tests**: unit
**Gate**: quick
**Commit**: `test(nse): sentinel, handler-count and temp-file sweep over every path`

---

### T13: `check-nse-logging.sh` and CI wiring

**What**: A textual guard that bans `NSLog`, `print(`, `debugPrint`, `dump(`, `os_log` and `localizedDescription` in `Sources/NottiSDKExtension` (comments stripped, as in `check-launch-hook-purity.sh`). Wire it into the CI `checks` job, `AGENTS.md` and `TESTING.md`.
**Where**: `scripts/check-nse-logging.sh`, `.github/workflows/ci.yml`, `AGENTS.md`, `.specs/codebase/TESTING.md`
**Depends on**: T11
**Reuses**: `scripts/check-launch-hook-purity.sh` (comment stripper)
**Requirement**: NSE-13, NSE-14

**Done when**:

- [ ] The script passes on the tree and fails on a fixture tree containing each banned token (run once per token, listed in the commit body)
- [ ] A banned word inside a comment passes
- [ ] The CI `checks` job runs it as a named step; `AGENTS.md` and `TESTING.md` mention it
- [ ] Gate check passes: **full**

**Tests**: none
**Gate**: full
**Commit**: `ci: guard the extension against logging and localizedDescription`

---

### T14: Objective-C interop test target

**What**: A new SPM test target `NottiSDKExtensionObjCTests` (Objective-C, `@import NottiSDKExtension;`) that calls both selectors: a nil-content expiry is a no-op, a request with no `notti_image_url` calls the handler once with the original content.
**Where**: `Package.swift`, `Tests/NottiSDKExtensionObjCTests/NottiExtensionObjCTests.m`, `.specs/codebase/TESTING.md`
**Depends on**: T11
**Reuses**: `Tests/NottiSDKObjCTests` layout
**Requirement**: NSE-16

**Done when**:

- [ ] The target compiles and both selectors run; removing the `@objc` names makes it fail to compile (checked once by hand)
- [ ] `scripts/check-package-graph.sh` and `pod lib lint` (all and Extension only) stay green, the pod has no new test target
- [ ] Gate check passes: quick plus the package-graph script
- [ ] Test count: at least 2 new

**Tests**: unit (ObjC)
**Gate**: quick
**Commit**: `test(nse): Objective-C smoke test of the extension entry points`

---

### T15: Contract literals

**What**: One test class that asserts the frozen values as literals, not through the constants the code reads: the key `notti_image_url`, `10485760`, `20`, the five MIME types and extensions, and the two public selector names. The registry's 16-job bound is an implementation detail, not contract.
**Where**: `Tests/NottiSDKExtensionTests/NottiRichMediaContractTests.swift`
**Depends on**: T4, T11
**Reuses**: nothing
**Requirement**: NSE-18

**Done when**:

- [ ] Changing any of the values in code makes a test fail (each checked once by a temporary edit, noted in the commit body)
- [ ] Gate check passes: quick
- [ ] Test count: at least 4 new

**Tests**: unit
**Gate**: quick
**Commit**: `test(nse): assert the rich media contract as literals`

---

### T16: Traceability, status docs and the closing gate

**What**: Write `traceability.md` mapping every NSE-xx to its tests. Update the spec statuses, `ROADMAP.md`, `STATE.md` (AD-011 for the NSE decisions D1 to D10, todos: end-to-end on a device, orphan temp files, `PrivacyInfo` over-declaration check), `AGENTS.md` layout and `TESTING.md` test-target table.
**Where**: `.specs/features/nse-rich-media/traceability.md`, `spec.md`, `design.md`, `tasks.md`, `.specs/project/ROADMAP.md`, `.specs/project/STATE.md`, `AGENTS.md`, `.specs/codebase/TESTING.md`
**Depends on**: T12, T13, T14, T15
**Reuses**: `delegate-integration/traceability.md` as the template
**Requirement**: all (NSE-01 to NSE-18)

**Done when**:

- [ ] Every NSE-xx has at least one named test; the count in `traceability.md` matches the real total
- [ ] `python3 .claude/skills/tlc-spec-driven/scripts/validate_tasks.py .specs/features/nse-rich-media/tasks.md` and `validate_state.py` exit 0
- [ ] Gate check passes: **full** (tests, SwiftLint `--strict`, every guard script, strict device builds, `pod lib lint`)
- [ ] Test count at least 474 + the sum of the minimums above, with none removed

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): nse-rich-media traceability and status`

---

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| NSE-01 | T6, T11 |
| NSE-02 | T1, T11 |
| NSE-03 | T1, T11 |
| NSE-04 | T7, T8 |
| NSE-05 | T6 |
| NSE-06 | T7 |
| NSE-07 | T2, T6 |
| NSE-08 | T7 |
| NSE-09 | T7, T12 |
| NSE-10 | T9 |
| NSE-11 | T3, T10, T11 |
| NSE-12 | T10, T11 |
| NSE-13 | T4, T12, T13 |
| NSE-14 | T11, T13 |
| NSE-15 | T11 |
| NSE-16 | T14 |
| NSE-17 | T8 |
| NSE-18 | T4, T15 |

18 requirements, 18 mapped to tasks.
