# In-App Messages Tasks

**Design**: `.specs/features/in-app-messages/design.md`
**Spec**: `.specs/features/in-app-messages/spec.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: `example-and-release` done and `0.1.0` tagged (the `Example/` app is edited in T19); a `zeep-notti` release that serves the IARM payload (OQ-6)
**Status**: Draft, waiting for approval. All open questions are closed (Julio, 2026-10-18) and the review decisions of 2026-10-19 are applied (margin from the safe-area edge, 401 vs 403 text, escape gesture, `trackEvent` cold-start window, `eligible` 429 cap, re-initialize and queue `app_id`, 408); OQ-6 (server release with the IARM payload) is only a dependency

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: **586 SDK tests after nse-rich-media (to confirm: re-count after `example-and-release`, the hosted example tests are separate)**. Counts below are minimums per task and cumulative from the baseline; the total never drops.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Model and parser (`NottiInAppMessage`, `NottiInAppMessageParser`) | unit | contract example payload field by field, unknown fields, bad message skipped, unknown format, image and action rules, buttons cap, dismiss range | `Tests/NottiSDKTests/NottiInAppMessageParserTests.swift` | `-only-testing:NottiSDKTests/NottiInAppMessageParserTests` |
| Style (`NottiInAppStyle`, `NottiInAppColor`) | unit | valid and invalid colors table, defaults for `text_align` and `margin` | `Tests/NottiSDKTests/NottiInAppStyleTests.swift` | same, `NottiInAppStyleTests` |
| Selector (`NottiInAppSelector`) | unit | session start, event match, order, once per session, visible, early names | `Tests/NottiSDKTests/NottiInAppSelectorTests.swift` | same |
| Event store (`NottiInAppEventStore`) | unit | persist, reload, cap, TTL, order, `app_id` required and purge, no secrets stored | `Tests/NottiSDKTests/NottiInAppEventStoreTests.swift` | same |
| API client (`NottiInAppApiClient`) | unit | request shape, `Retry-After`, status mapping | `Tests/NottiSDKTests/NottiInAppApiClientTests.swift` (with `StubURLProtocol`) | same |
| Flusher (`NottiInAppEventFlusher`) | unit | status table (408, 401 vs 403), FIFO, stable `event_id`, pause, other-app records, coalescing, modes | `Tests/NottiSDKTests/NottiInAppEventFlusherTests.swift` (fake scheduler) | same |
| Engine (`NottiInAppEngine`) | unit | fetch once per session, policies (`eligible` 429 cap, 408, 401 vs 403), late response, cold-start window and race, display state machine, impression, click, dismiss, timer, reset on config change | `Tests/NottiSDKTests/NottiInAppEngine*Tests.swift` (fake presenter, scheduler, clock) | same |
| Image loader (`NottiInAppImageLoader`) | unit | decode, caps, redirect, budget, no credentials | `Tests/NottiSDKTests/NottiInAppImageLoaderTests.swift` | same |
| Runtime and core hooks | unit | edges reach the engine once, adopt does not, replacement core keeps the engine, `configure` ordered before a same-thread `trackEvent`, launch-style sequence | `Tests/NottiSDKTests/NottiInAppWiringTests.swift`, existing `NottiCoreTests` untouched | same |
| Public shell, facade, ObjC | unit + ObjC compile check | `trackEvent`, listener, payload keys | `Tests/NottiSDKTests/NottiInAppPublicApiTests.swift`, `Tests/NottiSDKObjCTests/*.m` | same, `NottiSDKObjCTests` |
| Accessibility label table | unit | `en`, `pt-BR`, fallback English, no resource lookup | `Tests/NottiSDKTests/NottiInAppStringsTests.swift` | same |
| View hierarchy (`NottiInAppMessageView`, layouts) | unit (UIKit in the test host) | bounds per layout and size, gestures, verbatim text, a11y, Dynamic Type | `Tests/NottiSDKTests/NottiInAppLayout*Tests.swift` | same |
| Presenter and window | unit | non-key window, pass-through, scene move, Reduce Motion, escape gesture | `Tests/NottiSDKTests/NottiInAppPresenterTests.swift` | same |
| Privacy and source greps | unit | sentinels over every path, banned APIs in sources | `Tests/NottiSDKTests/NottiInAppPrivacyTests.swift` | same |
| Packaging (`Package.swift`, podspec, `PUBLIC_SURFACE.txt`, scripts) | none | scripts and `pod lib lint`, strict device builds | - | the scripts, `pod lib lint` |
| Example app | hosted unit (Example scheme) | `trackEvent` button wired, listener registered | `Example/` hosted tests | per `example-and-release` |
| Docs (README, CHANGELOG, TESTING, PROJECT, traceability) | none | every IAM-xx mapped to a named test | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially. New tests use synthetic values (`example.invalid`, `fixture`) and an isolated `UserDefaults` suite per test; none touches the network or `NottiRuntime.shared`.

## Gate Check Commands

> From `.github/workflows/ci.yml` and `.specs/codebase/TESTING.md`. Run `xcodebuild test` through the same watchdog as the previous features, and do not pipe `xcodebuild` into `grep`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:NottiSDKTests/<Class>` |
| Full | After T10, T12, T17, T18, T20 | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh && scripts/check-public-surface.sh && scripts/check-no-url-open.sh && scripts/check-launch-hook-purity.sh && scripts/check-nse-logging.sh` + the strict device builds (`xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -quiet`, and `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES`) + `pod lib lint NottiSDK.podspec --platforms=ios && pod lib lint NottiSDKExtension.podspec --platforms=ios` (also `--use-libraries`) + `scripts/check-hook-linked.sh spm` and `pod` |
| Build | Build-only checks | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |
| Spec docs | After editing any spec file | `python3 .claude/skills/tlc-spec-driven/scripts/validate_spec.py .specs/features/in-app-messages/spec.md` and `validate_tasks.py` on this file |

---

## Rules (apply to every task)

1. New code: `write-swift` and `swift-concurrency` guidance applies, in Swift 5 mode (AD-002 spirit): value types for state, small types, no `actor`, no `AsyncStream`; the engine is a class confined to its serial queue (design D1). Public API additions follow the `public-api` shell pattern.
2. Everything lives in `Sources/NottiSDK/InApp/` plus the listed edits. Nothing under `Sources/NottiShared` or `Sources/NottiSDKExtension` changes. UI types and anything touching `UIApplication` carry `@available(iOSApplicationExtension, unavailable)`.
3. **No source text, comments included, may contain** `openURL`, `UIApplication.shared.open` or `.open(_:options` (`check-no-url-open.sh`), nor `attributedText`, `AttributedString`, `WKWebView`, `LocalizedStringKey` in `InApp/UI` (plain text, IAM-23), nor `systemUptime`, `mach_absolute_time`, `contentModificationDate`, `fileModificationDate` (privacy manifest, D8).
4. Logging only through `NottiLogger` category `inapp`: fixed codes, `"\(error.domain)#\(error.code)"`. Never the token, device id, message id, title, body, label, URL, event name or `localizedDescription` (IAM-43).
5. Tests derive from the spec's acceptance criteria. Time, network, scenes and the presenter are injected: no real sleeps, no network, no `NottiRuntime.shared`. Contract values (paths, JSON keys, reasons, status handling, the 7 day and 100 limits, the events `Retry-After` clamp, the 60 s `eligible` cap) are asserted as literals, not through the constants the code reads (lesson from `delegate-integration` G1, as NSE-18).
6. Every `event_id` is generated when the event occurs and never regenerated (IAM-29). Every task that records events has a test of it.
7. Ported files change only where a task lists it: `NottiCore.swift` (T10, three hook calls), `NottiApiClient.swift` (T5, `percentEncodedPathComponent` from `private` to `internal`).
8. Do not run two `xcodebuild` processes on the same checkout. Each task is one commit, conventional style, no AI attribution.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe). Suggested split for sub-agents: T1 to T10 (logic, no UI), then T11 to T21.

### Phase 1: Pure logic, storage and transport

```
T1 ──→ T2
T1 ──→ T3
T4 ──→ T6
T5 ──→ T6
T1 ──→ T7
T3 ──→ T7
T5 ──→ T7
T6 ──→ T7
```

T1, T4 and T5 have no dependencies.

### Phase 2: Images and the display state machine

```
T7 ──→ T9
T8 ──→ T9
T9 ──→ T10
```

### Phase 3: Public API

```
T10 ──→ T11
T11 ──→ T12
```

### Phase 4: Native UI

```
T2 ──→ T14
T13 ──→ T14
T14 ──→ T15
T14 ──→ T16
T9 ──→ T17
T10 ──→ T17
T15 ──→ T17
T16 ──→ T17
```

T13 has no dependencies.

### Phase 5: Hardening, example, docs, device

```
T11 ──→ T18
T17 ──→ T18
T12 ──→ T19
T17 ──→ T19
T18 ──→ T20
T19 ──→ T20
T20 ──→ T21
```

Sequential order used in Execute: T1 → T2 → ... → T21.

### Diagram-definition cross-check

| Task | Depends on (definition) | Edges in the diagram |
| --- | --- | --- |
| T1 | None | none |
| T2 | T1 | `T1 → T2` |
| T3 | T1 | `T1 → T3` |
| T4 | None | `T4 → T6` |
| T5 | None | `T5 → T6`, `T5 → T7` |
| T6 | T4, T5 | `T4 → T6`, `T5 → T6` |
| T7 | T1, T3, T5, T6 | `T1 → T7`, `T3 → T7`, `T5 → T7`, `T6 → T7` |
| T8 | None | `T8 → T9` |
| T9 | T7, T8 | `T7 → T9`, `T8 → T9` |
| T10 | T9 | `T9 → T10` |
| T11 | T10 | `T10 → T11` |
| T12 | T11 | `T11 → T12` |
| T13 | None | `T13 → T14` |
| T14 | T2, T13 | `T2 → T14`, `T13 → T14` |
| T15 | T14 | `T14 → T15` |
| T16 | T14 | `T14 → T16` |
| T17 | T9, T10, T15, T16 | the four edges into T17 |
| T18 | T11, T17 | `T11 → T18`, `T17 → T18` |
| T19 | T12, T17 | `T12 → T19`, `T17 → T19` |
| T20 | T18, T19 | `T18 → T20`, `T19 → T20` |
| T21 | T20 | `T20 → T21` |

No `[P]` task.

---

## Task Breakdown

### T1: Message model and lenient parser

**What**: `NottiInAppMessage`, `NottiInAppFormat`, `NottiInAppTrigger`, `NottiInAppButton`, `NottiInAppAction` and `NottiInAppMessageParser.parse(_:)` over `JSONSerialization`. Each message is mapped independently; skip rules of IAM-16.
**Where**: `Sources/NottiSDK/InApp/Model/NottiInAppMessageParser.swift` (types in `NottiInAppMessage.swift` beside it), `Tests/NottiSDKTests/NottiInAppMessageParserTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: IAM-05, IAM-16

**Done when**:

- [ ] The example payload of `in-app-messages.mdx` (ids replaced by `fixture` values, `example.invalid` URLs) maps field by field, including `trigger`, both buttons, `image_action`, `style`, `dismiss_after_seconds`
- [ ] Unknown fields at every level are ignored; an unknown `format` becomes `center`; `style: null` and a missing `style` both give default style input
- [ ] A message with an empty `id`, with empty title and body, or with an unknown trigger type is skipped and the others survive; a non-array `messages` or a non-JSON body gives `.malformed`
- [ ] A button without `id` or `label` is dropped, a third button is dropped, `image_url` with `http`, no host or garbage is dropped, `image_action` without a valid image is dropped, `dismiss_after_seconds` 0, 301, 8.5 and a string give nil, 1 and 300 are kept
- [ ] Gate check passes: quick
- [ ] Test count: at least 12 new, total at least 598

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): parse the eligible payload leniently`

---

### T2: Style tokens and color parsing

**What**: `NottiInAppStyle` (optional tokens, `textAlign` default `left`, `margin` default `true`, built from the parser's raw `style`) and `NottiInAppColor.parse(_:)` returning `UIColor?` only for `#` plus six hex digits.
**Where**: `Sources/NottiSDK/InApp/Model/NottiInAppStyle.swift`, `Tests/NottiSDKTests/NottiInAppStyleTests.swift`
**Depends on**: T1
**Reuses**: the raw style dictionary the parser keeps
**Requirement**: IAM-20, IAM-21, IAM-22 (token side)

**Done when**:

- [ ] `#102030`, `#e94b8b`, `#FFFFFF` parse to the exact components; `#FFF`, `102030`, `#10203040`, `#GGGGGG`, empty, `red`, a number and nil give nil and no throw
- [ ] `text_align` `left`, `center`, `right` map; absent or unknown is `left`; `margin` true, false, absent (true), non-boolean (true)
- [ ] An invalid token does not affect the others in the same `style`
- [ ] Gate check passes: quick
- [ ] Test count: at least 10 new, total at least 608

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): style tokens and safe color parsing`

---

### T3: Selector

**What**: `NottiInAppSelector` value type: `load`, `track`, `noteEarly`, `reset` as designed (first session start, held event messages, exact match, oldest first, once per session, ignore while visible, early names bounded to 32 distinct with the oldest dropped, `reset(keepingEarlyNames:)`, skip a visible id, drop session-start candidates when something is visible).
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppSelector.swift`, `Tests/NottiSDKTests/NottiInAppSelectorTests.swift`
**Depends on**: T1
**Reuses**: the model types
**Requirement**: IAM-07, IAM-08, IAM-09, IAM-11, IAM-12 (OQ-2, OQ-4, OQ-9 closed by Julio, 2026-10-18)

**Done when**:

- [ ] Two session-start messages: only the first is returned and the second never is, in the same session
- [ ] Two event messages with the same name: the first `track` returns the older, the second `track` returns the other, the third returns nil; `Checkout_Done` does not match `checkout_done`; `" checkout_done"` does not match
- [ ] `track` while visible returns nil and does not consume the message
- [ ] Names noted before `load` are replayed in call order, once, returning at most one message; 33 distinct names keep the newest 32; `reset` clears everything; `track` after `reset` finds nothing
- [ ] `reset(keepingEarlyNames: true)` clears held messages and `shown` but keeps the early names, which a later `load` replays once, in call order; `reset()` and `reset(keepingEarlyNames: false)` clear them
- [ ] `load` with a visible id skips that id and returns no session-start message
- [ ] Gate check passes: quick
- [ ] Test count: at least 15 new, total at least 623

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): message selection per session`

---

### T4: Event store

**What**: `NottiInAppEventRecord` (with the required `appId`) and `NottiInAppEventStore` over `UserDefaults` (`notti_inapp_pending_events`): `enqueue`, `all`, `remove(eventId:)`, `dropOlderThan`, `purge(keepingAppId:)`, cap 100, lock, write per mutation, decode failure logged and dropped.
**Where**: `Sources/NottiSDK/InApp/Storage/NottiInAppEventStore.swift`, `Tests/NottiSDKTests/NottiInAppEventStoreTests.swift`
**Depends on**: None
**Reuses**: the shape of `NottiEventStore` (`NottiEventStore.swift:66-149`), not the type
**Requirement**: IAM-29, IAM-30 (`app_id`, purge)

**Done when**:

- [ ] Records survive a new store over the same suite, in insertion order, with the same `eventId`, `appId`, `occurredAtMs`, `buttonId`, `reason`
- [ ] The 101st record drops the oldest; `dropOlderThan` removes records of 7 days and older with an injected `now` and keeps a 6 day 23 hour one
- [ ] The stored JSON contains no `token` and no `device_id` (asserted on the raw data), carries the literal key `app_id`, and the key literal is `notti_inapp_pending_events`
- [ ] `purge(keepingAppId:)` removes the records of other apps, keeps the current app's in order, and is a no-op when all match
- [ ] A stored record without `app_id` is treated as corrupt (one `.warn` without content, empty queue); the field is required, no migration (IAM-30)
- [ ] A corrupt value logs one `.warn` without its content and yields an empty queue
- [ ] The CTR key `notti_pending_events` is untouched by every operation
- [ ] Gate check passes: quick
- [ ] Test count: at least 12 new, total at least 635

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): persistent in-app event queue`

---

### T5: API client

**What**: `NottiInAppApiClient` with `eligible(deviceId:token:completion:)` and `report(_:deviceId:token:completion:)`, non-blocking, no retry inside, `NottiInAppHTTPResult` (`success`, `retryAfter`, `permanent`, `transient`). Promote `NottiApiClient.percentEncodedPathComponent` from `private` to `internal` (one-word edit) and reuse `validatedBaseUrl`.
**Where**: `Sources/NottiSDK/InApp/Network/NottiInAppApiClient.swift` (and the one-word edit in `Sources/NottiSDK/Network/NottiApiClient.swift:142`), `Tests/NottiSDKTests/NottiInAppApiClientTests.swift`
**Depends on**: None
**Reuses**: `NottiApiClient.validatedBaseUrl`, `percentEncodedPathComponent`, `StubURLProtocol`
**Requirement**: IAM-02, IAM-04, IAM-29

**Done when**:

- [ ] `eligible` sends `POST`, the exact path `/v1/apps/<appId>/in-app-messages/eligible`, `Authorization: Bearer <key>`, JSON content type, and a body whose keys are exactly `device_id` and `token`
- [ ] `report` sends the path `/v1/apps/<appId>/in-app-messages/<messageId>/events` with a body of exactly `device_id`, `token`, `event_id`, `type` and, only when set, `button_id` (click) or `reason` (dismiss), plus `occurred_at` in RFC 3339; a path component with a space or `/` is percent-encoded
- [ ] 200 and 201 map to `success`; 429 with `Retry-After: 7` gives 7, `0` gives 0 and `120` gives 120 (unclamped, the policy is not in the client), missing, `soon`, `-5` and an HTTP-date give nil; 401, 403, 404, 422 and 400 are `permanent(status)`; 500, 503, 408 and a transport error are `transient` and carry only `domain#code`
- [ ] The existing `NottiApiClientTests` still pass unchanged
- [ ] Gate check passes: quick (`NottiInAppApiClientTests` and `NottiApiClientTests`)
- [ ] Test count: at least 13 new, total at least 648

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): non-blocking client for the in-app routes`

---

### T6: Event flusher

**What**: `NottiInAppEventFlusher` with `flush(mode:completion:)`, modes `.full` and `.singleAttempt`, an injected scheduler, the 7 day drop first, strict FIFO, the status table of IAM-31 (including `408` transient and the `401` session halt), the records-of-other-apps skip, the `429` pause deadline, backoff 2/4/8/16 s with 5 attempts, coalescing of concurrent triggers.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEventFlusher.swift`, `Tests/NottiSDKTests/NottiInAppEventFlusherTests.swift`
**Depends on**: T4, T5
**Reuses**: the store and the client; defines `NottiInAppScheduling` (`schedule(after:work:)`) used by later tasks
**Requirement**: IAM-30, IAM-31 (408, 401 vs 403), IAM-32, IAM-33

**Done when**:

- [ ] 201 and 200 remove the record and continue; 404 and 422 remove it and continue; 403 stops and keeps everything; each is a separate test with the exact status
- [ ] 401 stops the flush for the session and keeps everything: later triggers in the same session send no request, the captured logger has one generic fixed code per session and **no** line with the registration text, and after `sessionStarted` the flush sends again
- [ ] On 403 the captured logger has exactly one `.warn` with the fixed text `Notti: in-app messages are inactive on this device until the next registration (HTTP 403)`, even when several flush passes hit 403 in the same session, and it contains no id, token, URL or body (sentinels in the stub response)
- [ ] 408 on the head is transient exactly like 503 (same delays, same `event_id`, queue intact)
- [ ] 503 on the head: `.full` retries the same record with the delays 2, 4, 8, 16 s on the fake scheduler, the **same `event_id` in all five bodies**, then stops with the queue intact; `.singleAttempt` stops after one attempt
- [ ] A record whose `app_id` differs from the current app id is never sent and does not block the records behind it; with only other-app records no request is made
- [ ] A failing head is never skipped: with impression then click queued and the impression failing, the click is never sent
- [ ] 429 with `Retry-After: 30` pauses all sends until the fake clock passes 30 s, then resumes; a value of 0 is clamped to 1 and 9999 to 300; no header gives 60 (the 60 s `eligible` give-up cap of IAM-04 does not apply to events)
- [ ] Ten triggers during one run produce at most one extra pass; records older than 7 days are removed without a request
- [ ] No `Thread.sleep` or real delay is used (the test would hang otherwise)
- [ ] Gate check passes: quick
- [ ] Test count: at least 18 new, total at least 666

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): ordered, resumable event flush`

---

### T7: Engine, session fetch and selection

**What**: `NottiInAppEngine` core: queue confinement, `configure`, `sessionStarted`, `sessionEnded`, `deviceRegistered`, `networkAvailable`, `appBecameActive`, `trackEvent`, fetch rule `maybeFetch` (once per session, either signal order), flush before fetch (`.singleAttempt`), fetch error policy (IAM-04: the `eligible` 429 cap of 60 s, `408` transient, `401` silent stop vs `403` warning), generation check for late responses, the `awaitingFirstSession` flag and the `trackEvent` rule of D12 (`configure` reaches the queue before a same-thread `trackEvent`), `resetForNewConfig()` (reset, invalidate, purge other apps' records), and the hand-off of the chosen message to a `NottiInAppPresenting` protocol (defined here, with the fake used in tests). The display lifecycle is T9; here a presented message is only recorded.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift`, `Tests/NottiSDKTests/NottiInAppEngineFetchTests.swift`
**Depends on**: T1, T3, T5, T6
**Reuses**: selector, client, flusher, store, `NottiMainDispatcher`
**Requirement**: IAM-01, IAM-03, IAM-04, IAM-06, IAM-07, IAM-08, IAM-10, IAM-11 (engine side), IAM-30 (purge on config change)

**Done when**:

- [ ] Session signal then registration signal gives one `eligible`; registration then session gives one; a second registration (token refresh) or a second `sessionStarted` of the same session adds none; `sessionEnded` then `sessionStarted` gives a second call
- [ ] The first session-start message is handed to the presenter; an event message is held and handed only on a matching `trackEvent`; nothing is sent to the server for `trackEvent` (asserted on the stub's request list)
- [ ] With a non-empty queue the flush request precedes the `eligible` request and a failing flush does not prevent `eligible` (503, 429, 403 and a transport error in the flush each still lead to one `eligible` request)
- [ ] A `401` in the pre-`eligible` flush skips `eligible` for the session: the stub saw no `eligible` request, the captured logger has one generic fixed code and no registration text, the queue is kept, and after the next `sessionStarted` both the flush and `eligible` run again
- [ ] 403 on `eligible` logs exactly one `.warn` with the fixed text `Notti: in-app messages are inactive on this device until the next registration (HTTP 403)` (captured logger, sentinel-free) and the engine stays inactive for the session; 422 stops with no retry
- [ ] 401 on `eligible` stops for the session with no retry, no re-registration request and the queue kept, logs only one generic fixed code and **no line containing the registration text** (asserted on the captured logger; the 403 test asserts the opposite)
- [ ] `eligible` 429 with `Retry-After: 120` gives up for the session: no wait is scheduled and the stub saw exactly one `eligible` request; with `Retry-After: 2` the retry fires at 2 s on the fake scheduler (not before); `Retry-After: 0` waits 1 s; absent, `soon` and `-5` wait 60 s; `61` gives up and `60` waits 60 s; at most 3 waits, then the engine stops
- [ ] 503, 408 and a transport error retry with 2/4/8/16 s (5 attempts) then stop
- [ ] A late response after `sessionEnded` is ignored: nothing held, nothing presented, a later `trackEvent` matches nothing; the same for a response issued under session 1 that arrives after session 2 started; a held event message is gone after `sessionEnded`
- [ ] A new engine over the same suite shows the same message again (no persisted shown state)
- [ ] `configure` with a different appId, clientKey or baseUrl resets held messages, remembered names, the fetch and the backoff and 429 deadlines, ignores an in-flight response and purges the queue records of other apps without touching the current app's; a same-config `configure` changes none of it (held messages and names kept, no new fetch)
- [ ] Cold-start window: `configure` then `trackEvent("fixture_event")` (no session yet) then `sessionStarted` and the response with a matching event message presents it once; names before the first `configure`, and names reported after `sessionEnded` while no session is open, are ignored and never appear in a captured log line; a name reported while `awaitingFirstSession` survives the first `sessionStarted`; 33 distinct early names keep the newest 32; a re-initialize after the first session does not re-arm the flag
- [ ] Race test: `configure` immediately followed by `trackEvent` on the same thread (no wait between them), then `sessionStarted` and `deviceRegistered` in either order, still matches once; and a `didFinishLaunching`-style sequence (`configure`, `trackEvent`, a long gap with no session, then `sessionStarted`) with the fake app state inactive does too
- [ ] The test asserts the engine never runs its network or storage work on the main thread
- [ ] Gate check passes: quick
- [ ] Test count: at least 24 new, total at least 690

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): fetch eligible messages once per session`

---

### T8: Image loader

**What**: `NottiInAppImageLoader` with an ephemeral session (no cache, no cookies), delegate-based data task that cancels over 5 MiB (declared or received) and refuses a redirect to non-`https`, 10 s request timeout, ImageIO downsampling, `NSCache` limited to 8, and an API that returns `UIImage?` through a completion.
**Where**: `Sources/NottiSDK/InApp/Image/NottiInAppImageLoader.swift`, `Tests/NottiSDKTests/NottiInAppImageLoaderTests.swift`
**Depends on**: None
**Reuses**: the redirect and early-cancel technique proved in `nse-rich-media` (`NottiRichMediaJob`), `StubURLProtocol`
**Requirement**: IAM-40, IAM-41 (loader side), IAM-42

**Done when**:

- [ ] A synthetic PNG decodes and is downsampled to the requested max pixel size
- [ ] A stub declaring 6 MiB, and one sending 6 MiB without a length, are cancelled early and return nil
- [ ] A redirect to an `http` URL returns nil; a non-image body returns nil; a transport error returns nil
- [ ] The captured request has no `Authorization` header and no cookies; the loader's initializer takes no credentials
- [ ] The second request for the same URL is served from the cache (one request in the stub), the ninth distinct URL evicts per `countLimit`
- [ ] Gate check passes: quick
- [ ] Test count: at least 10 new, total at least 700

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): bounded, credential-free image loading`

---

### T9: Engine, display state machine and timer

**What**: Add to the engine: `NottiInAppDisplay`, the image preload with the 3 s budget (through the loader and scheduler), `becameVisible`, `userTapped`, `userDismissed`, `sceneAvailabilityChanged`, `appStateChanged`, the auto-dismiss timer by remaining wall-clock time, `ensureImpression`, the event recording into the store plus a flush trigger, and the click emission through an injected closure. `resetForNewConfig()` teardown of a visible display. Invariants of the design.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift` (extension in `NottiInAppEngine+Display.swift`), `Tests/NottiSDKTests/NottiInAppEngineDisplayTests.swift`
**Depends on**: T7, T8
**Reuses**: everything above
**Requirement**: IAM-09, IAM-12, IAM-19 (resolution of the body tap), IAM-25, IAM-26, IAM-27, IAM-28, IAM-29, IAM-30, IAM-34, IAM-35, IAM-41 (engine side), IAM-06 (teardown on config change)

**Done when**:

- [ ] `becameVisible` three times records one `impression`; a tap or dismiss before `becameVisible` records the `impression` first (queue order asserted)
- [ ] A button tap records `click` with that `button_id`, emits one click, asks the presenter to dismiss, records no `dismiss`; an image tap records `click` with `image`; a body tap records the first button's id; a second tap in the same turn is ignored; a body tap with no buttons does nothing
- [ ] Dismiss reasons `close_button`, `swipe`, `outside_tap` are recorded as given; the timer records `auto`
- [ ] `dismiss_after_seconds: 8` fires at 8 s on the fake clock; a 3 s background pause moves it to 11 s; a close at 2 s cancels the timer and records `close_button`; null, 0, 301 give no timer
- [ ] An image that never loads makes the message present without the image after 3 s on the fake scheduler, with `image_action` dropped (so no `image` click is possible); a late image does nothing
- [ ] Every recorded event has a UUID `event_id` generated at record time; two events never share one; the same id is used by the retried send
- [ ] At most one display exists at any time; an event while visible is ignored; a message id is presented once per session
- [ ] A config change while a message is visible tears the display down with **no** event recorded (queue unchanged, no `impression`, `click` or `dismiss`), the presenter is asked to dismiss, the pending auto-dismiss timer never fires, and a late `becameVisible`, tap or close for the old display id is ignored; a same-config `configure` leaves the display and its timer untouched
- [ ] Gate check passes: quick
- [ ] Test count: at least 19 new, total at least 719

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): display lifecycle, events and auto dismiss`

---

### T10: Core hooks and runtime wiring

**What**: Add `NottiInAppHooks` (three optional closures, no-op default) to `NottiCore.init` and call them: `onSessionStarted` in the `tryOpen() == true` branch (`NottiCore.swift:1005-1007`), `onSessionEnded` after `sessionGate.close()` (`:1045`), `onDeviceRegistered` after the success bookkeeping in `registerDevice` (`:722`). `NottiRuntime` owns the engine (built with the production client factory, the `NottiDeviceStore` identity reader, a placeholder no-op presenter until T17), passes the hooks in `makeCore()`, calls `configure` in `start`, and forwards `onNetworkAvailable` and `didBecomeActive` flush triggers. `start` enqueues `configure` on the engine queue synchronously, before `core.initialize` (D12), so a `trackEvent` from the same thread is ordered after it.
**Where**: `Sources/NottiSDK/Core/NottiCore.swift`, `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiInAppWiringTests.swift`
**Depends on**: T9
**Reuses**: `NottiCore.SessionGate`, the runtime's observers
**Requirement**: IAM-01, IAM-06, IAM-11 (launch ordering), IAM-33

**Done when**:

- [ ] A core with a fake gate and fake registration calls `onSessionStarted` once per real session and never for the adopted session, once `onSessionEnded` per background, and `onDeviceRegistered` after each registration `.success` and not after a failure
- [ ] An isolated runtime delivers the three edges to its engine; replacing the core (`start` with a different config) keeps the same engine instance, and the engine's session state is reset only for a changed config
- [ ] `runtime.onNetworkAvailable()` triggers an engine flush
- [ ] Race test at runtime level: `runtime.start(...)` immediately followed by `engine.trackEvent` on the same thread with an app-state provider that reports inactive: no session yet, the name is kept; flipping the provider to active (the `didBecomeActive` of a launch) opens the session through the core hook, and the response then matches the name once
- [ ] Re-initialize through `start`: the same config leaves the engine state untouched; a different config resets it and purges other apps' queue records (the persisted suite is inspected)
- [ ] The existing `NottiCoreTests`, `NottiRuntimeTests` and `NottiContinuityTests` pass unchanged, and the diff of `NottiCore.swift` is the init parameter plus the three call lines
- [ ] Gate check passes: **full**
- [ ] Test count: at least 11 new, total at least 730

**Tests**: unit
**Gate**: full
**Commit**: `feat(inapp): wire the session and registration edges to the engine`

---

### T11: Public API (Swift)

**What**: `Notti.trackEvent(_:)`, `Notti.InAppMessages.addClickListener`, `NottiInAppClick` and `NottiInAppAction`, the `NottiFacade` methods, a `NottiListenerHub<NottiInAppClick>` attached to the engine's click handler, the allowlist entry for the two value types in `scripts/check-public-surface.sh`, and the regenerated `PUBLIC_SURFACE.txt`. Empty name ignored with one `.warn`.
**Where**: `Sources/NottiSDK/Public/NottiInAppMessages.swift`, `Sources/NottiSDK/Facade/NottiFacade.swift` (extension in `NottiFacade+InApp.swift`), `scripts/check-public-surface.sh`, `.specs/codebase/PUBLIC_SURFACE.txt`, `Tests/NottiSDKTests/NottiInAppPublicApiTests.swift`
**Depends on**: T10
**Reuses**: `NottiListenerHub`, `NottiFacade.setSharedForTesting`, `check-public-surface.sh --update`
**Requirement**: IAM-08, IAM-11 (no-op before initialize), IAM-24, IAM-25 (delivery), IAM-44

**Done when**:

- [ ] `Notti.trackEvent("fixture_event")` reaches the engine through an isolated facade; an empty string does not and logs one `.warn` without the name; before `Notti.initialize` the call is a no-op (the engine remembers nothing and no log line contains the name)
- [ ] A listener receives `NottiInAppClick` on the main thread with `messageId`, `buttonId`, `action.kind` and the untouched `value`; two listeners both receive it in order; `remove()` stops delivery; with no listener nothing crashes and the engine logs one `.warn`
- [ ] The public declarations are in `PUBLIC_SURFACE.txt`; `scripts/check-public-surface.sh` passes; `NottiInAppClick` and `NottiInAppAction` need no availability attribute (allowlisted), every other new public type has it
- [ ] `scripts/check-no-url-open.sh` passes
- [ ] Gate check passes: quick plus `scripts/check-public-surface.sh` and `scripts/check-no-url-open.sh`
- [ ] Test count: at least 9 new, total at least 739

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): trackEvent and the click listener`

---

### T12: Objective-C mirror

**What**: `NottiObjC.trackEvent(_:)` (`@objc(trackEvent:)`) and `NottiInAppMessagesObjC` (`@objc(NottiInAppMessages)`) with `addClickListener:` delivering an `NSDictionary` (`messageId`, `buttonId`, optional `actionType`, `actionValue`); ObjC compile check and smoke test; surface file regenerated.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `.specs/codebase/PUBLIC_SURFACE.txt`
**Depends on**: T11
**Reuses**: the `objcDictionary` pattern (`NottiObjC.swift:190-199`)
**Requirement**: IAM-44

**Done when**:

- [ ] The Objective-C test calls `[Notti trackEvent:]` and `[NottiInAppMessages addClickListener:]` and compiles only with these selector names
- [ ] The bridge test checks the dictionary keys and that `actionType` and `actionValue` are absent when the action is nil
- [ ] `scripts/check-public-surface.sh` passes
- [ ] Gate check passes: **full**
- [ ] Test count: at least 4 new, total at least 743

**Tests**: unit (Swift bridge) + ObjC compile check
**Gate**: full
**Commit**: `feat(inapp): Objective-C mirror of the in-app API`

---

### T13: Accessibility label table

**What**: `NottiInAppStrings`: an in-code table with the close and image-link labels for `en` and `pt-BR`, selected from `Locale.preferredLanguages` (primary subtag), fallback English. No `.strings`, no lproj, no `defaultLocalization`, no `resource_bundles`, no change to `Package.swift` or the podspecs (design D11).
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppStrings.swift`, `Tests/NottiSDKTests/NottiInAppStringsTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: IAM-38 (labels)

**Done when**:

- [ ] `en` and `pt-BR` (also `pt-PT` and `pt` by primary subtag) return their own text; an unknown language and an empty list fall back to English
- [ ] The labels are asserted as literals; the file has no `NSLocalizedString`, `Bundle`, `LocalizedStringKey` (grep test)
- [ ] `Package.swift` and both podspecs are unchanged by this task (no `pod lib lint` is needed for it; the full gate runs later)
- [ ] Gate check passes: quick
- [ ] Test count: at least 4 new, total at least 747

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): in-code accessibility labels`

---

### T14: Message view base, appearance and layout metrics

**What**: `NottiInAppLayout` (pure bounds), `NottiInAppAppearance` (tokens to colors and fonts, defaults of OQ-5), and the part of `NottiInAppMessageView` shared by all layouts: title and body labels (plain text, text alignment), the scrolling text region, the 44 pt close control, buttons with the shared or default styling, optional image, accessibility identifiers and traits, Dynamic Type.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppMessageView.swift` (with `NottiInAppLayout.swift`, `NottiInAppAppearance.swift`), `Tests/NottiSDKTests/NottiInAppMessageViewTests.swift`
**Depends on**: T2, T13
**Reuses**: `NottiInAppStyle`, the label table
**Requirement**: IAM-14, IAM-17, IAM-20, IAM-21, IAM-22, IAM-23, IAM-38 (element side), IAM-39

**Done when**:

- [ ] Title `**bold** <b>x</b> [l](https://example.invalid)` and a body with newlines are displayed verbatim: the labels' `text` equals the input and `attributedText` carries no link, bold or paragraph attribute from markup
- [ ] Valid tokens color the background, text, close tint, button background and label; an invalid token falls back to its default; with `button_color` set both buttons share it; without tokens the first button is filled and the second tinted (defaults of OQ-5)
- [ ] `text_align` is applied to both labels; the close control is at least 44 x 44 and is not inside the scroll view
- [ ] A 500-character body at the largest accessibility content size gives a scroll content size larger than its viewport and nothing clipped (the close control and buttons remain visible)
- [ ] The image view is not an accessibility element unless an `image_action` exists; title and body are one element with both texts; buttons have the `.button` trait
- [ ] A grep test over `Sources/NottiSDK/InApp/UI` finds none of `attributedText`, `AttributedString`, `WKWebView`, `LocalizedStringKey`, `openURL`
- [ ] Gate check passes: quick
- [ ] Test count: at least 14 new, total at least 761

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): message view with plain text, style and accessibility`

---

### T15: `top` and `bottom` layouts

**What**: The bar layouts in `NottiInAppMessageView`: placement under or above the safe area, the `margin` inset measured from the safe-area edge (IAM-21: constants on `safeAreaLayoutGuide`, 16 or 0, never the window edge), height at most 40% of the window, thumbnail, buttons side by side wrapping to a column, swipe up or down recognizer, body tap recognizer (excluding controls, no recognizer behavior without buttons), non-accessible body tap target.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppBarLayout.swift`, `Tests/NottiSDKTests/NottiInAppBarLayoutTests.swift`
**Depends on**: T14
**Reuses**: `NottiInAppLayout`
**Requirement**: IAM-13 (top, bottom), IAM-15, IAM-18, IAM-19, IAM-21 (margin)

**Done when**:

- [ ] At 390 x 844 and 844 x 390 with notch insets: `top` sits at the safe area top, `bottom` at the safe area bottom, heights at most 40% of the window with a 500-character body; with `margin: true` or absent the bar is 16 pt from the safe-area edge (top or bottom, leading and trailing); with `margin: false` its frame touches the safe-area edges on those sides and never overlaps the notch, status bar or home indicator region
- [ ] In landscape with left and right safe-area insets (for example 59 pt): the leading and trailing edges are at the insets plus 16 (`margin: true`) or at the insets exactly (`margin: false`), never inside the inset
- [ ] Two buttons are side by side at 390 pt and in a column at the largest Dynamic Type size
- [ ] `top` has a swipe-up recognizer and no swipe-down; `bottom` the mirror; invoking the handler yields the reasons `swipe`; the close control yields `close_button`
- [ ] A body tap yields the first button action target; with no buttons the body has no tap effect; a tap on a button or the close control does not also fire the body tap
- [ ] Re-layout (rotation sizes in sequence) leaves one view hierarchy and reports `becameVisible` zero times from the view (the view never reports impressions)
- [ ] Gate check passes: quick
- [ ] Test count: at least 13 new, total at least 774

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): top and bottom bar layouts`

---

### T16: `center` and `full` layouts

**What**: `center`: backdrop at 50% black, card at most 90% of the width, outside-tap recognizer that ignores taps inside the card, `margin` ignored, image above the text. `full`: edge to edge inside the safe areas, the `margin` inset measured from the safe-area edge, image above the text, buttons pinned to the bottom, no dismiss gesture.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppCardLayout.swift`, `Tests/NottiSDKTests/NottiInAppCardLayoutTests.swift`
**Depends on**: T14
**Reuses**: `NottiInAppLayout`
**Requirement**: IAM-13 (center, full), IAM-15, IAM-18, IAM-21 (margin)

**Done when**:

- [ ] `center`: the card width is at most 90% of the window at portrait and landscape, centered, the backdrop alpha is 0.5 black, `margin: false` changes nothing; the outside-tap handler yields `outside_tap` and a tap inside the card yields nothing
- [ ] `full`: the frame equals the safe area inset by 16 (`margin: true` or absent) or 0 (`margin: false`, touching the safe-area edges on all sides and never under the notch or home indicator), also in landscape with left and right safe-area insets; buttons are at the bottom of the safe area while a long body scrolls, no swipe and no backdrop recognizer exists
- [ ] The close control is present and at least 44 pt in both, also with a 500-character body at the largest Dynamic Type
- [ ] Gate check passes: quick
- [ ] Test count: at least 13 new, total at least 787

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): center and full layouts`

---

### T17: Presenter, window and scene handling

**What**: `NottiInAppWindow` (level just under `.alert`, pass-through `hitTest`, never key), `NottiInAppViewController` (hosts the layout, animations, Reduce Motion, accessibility focus and notifications, the `accessibilityPerformEscape()` override, `.all` orientations), `NottiInAppPresenter` implementing `NottiInAppPresenting` with an injected scene provider, scene and app lifecycle observation (move to another active scene without a new impression, timer pause signals), the legacy no-scene fallback, and production wiring in `NottiRuntime` replacing the T10 placeholder.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppPresenter.swift` (with `NottiInAppWindow.swift`, `NottiInAppViewController.swift`), `Tests/NottiSDKTests/NottiInAppPresenterTests.swift`
**Depends on**: T9, T10, T15, T16
**Reuses**: the layouts, the engine's presenter protocol
**Requirement**: IAM-18, IAM-36, IAM-37, IAM-38, IAM-39

**Done when**:

- [ ] The window is not the key window; `windowLevel` is below `.alert` and above `.normal`; for a bar the `hitTest` outside the bar returns nil and inside returns the bar; for `center` and `full` the backdrop returns a view
- [ ] `accessibilityViewIsModal` is true for `center` and `full`, false for bars; the `.screenChanged` or `.announcement` notification is posted per layout (recorded through an injected poster)
- [ ] `accessibilityPerformEscape()` on a `center` and on a `full` presentation returns true and reports `userDismissed(displayId, close_button)` (one `dismiss` with `close_button`, none when the display is already closing); on a `top` and on a `bottom` presentation it returns false and reports nothing
- [ ] With Reduce Motion on, entrance and exit use the cross-fade path; the dismissal still completes
- [ ] A fake scene provider that loses and regains a scene keeps the same display id, creates no `impression` and no `dismiss`, and reports `sceneAvailabilityChanged` both ways; a provider with no scenes uses the screen-sized fallback window
- [ ] The presenter reports `becameVisible` exactly once per presentation (the engine ignores repeats anyway)
- [ ] The production `NottiRuntime` uses the real presenter; no other test touches `UIApplication.shared`
- [ ] Gate check passes: **full**
- [ ] Test count: at least 14 new, total at least 801

**Tests**: unit
**Gate**: full
**Commit**: `feat(inapp): present messages in a dedicated window`

---

### T18: Privacy sweep and guards

**What**: One test class with sentinels in token, device id, message id, title, body, button labels, image and action URLs and event name run through every path (fetch ok, each error status including 401 and 408, queue flush, tap, dismiss, image failure, no listener, `trackEvent` before `initialize`) asserting no captured `NottiLogger` line contains any of them; source greps for the banned strings (rule 3); `PrivacyInfo.xcprivacy` comment extended for In-App events (keys unchanged); re-check of required-reason APIs in the new code.
**Where**: `Tests/NottiSDKTests/NottiInAppPrivacyTests.swift`, `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy` (comment only)
**Depends on**: T11, T17
**Reuses**: `LogSink`, `NottiLoggingPrivacyTests` patterns
**Requirement**: IAM-23, IAM-24, IAM-43, IAM-45, IAM-46

**Done when**:

- [ ] Every sentinel is absent from every captured line on every listed path (each path is its own test method)
- [ ] On the `401` path (eligible and events) no captured line contains the registration text of the `403` warning, and the `trackEvent` name never appears in a line when it is ignored (before `initialize`, or after a session ended)
- [ ] The source grep tests fail on a temporary mutant containing each banned string (noted in the commit body)
- [ ] `PrivacyManifestTests` pass unchanged; the manifest diff is the comment only
- [ ] `scripts/check-no-url-open.sh`, `check-extension-safety.sh`, `check-package-graph.sh`, `check-public-surface.sh` pass
- [ ] Gate check passes: **full**
- [ ] Test count: at least 9 new, total at least 810

**Tests**: unit
**Gate**: full
**Commit**: `test(inapp): privacy sentinel sweep and source guards`

---

### T19: Example app

**What**: A button "Track event" that calls `Notti.trackEvent("example_event")` and a click listener registered at launch that logs only the action kind (never the value) to the on-screen log; a hosted test that the button and the listener are wired.
**Where**: `Example/App/ExampleApp.swift`, `Example/ExampleTests/InAppExampleTests.swift`
**Depends on**: T12, T17
**Reuses**: the `example-and-release` structure and hosted tests
**Requirement**: IAM-47

**Done when**:

- [ ] The example builds for the simulator and device with the strict flags and the hosted test passes
- [ ] The sample config in `Example/Config/Example.xcconfig.sample` is unchanged (no real keys)
- [ ] Gate check passes: Example build and hosted tests plus quick
- [ ] Test count: at least 2 new hosted tests (not counted in the SDK total)

**Tests**: unit (hosted)
**Gate**: quick
**Commit**: `feat(example): track an event and handle in-app clicks`

---

### T20: Docs, traceability and status

**What**: README section (what In-App does, `trackEvent`, the click listener and the sentence that without it no link opens, Dynamic Type and accessibility notes, a data collection line), `CHANGELOG.md` `[Unreleased]` (the feature, and the divergence: on `403` the SDK does not re-register as the server contract says, it warns and stays inactive until the next registration), `TESTING.md` (new layers and counts), `PROJECT.md` (remove the In-App out-of-scope line, add the scope item), `ROADMAP.md` status, `traceability.md` for IAM-01..48, spec statuses.
**Where**: `.specs/features/in-app-messages/traceability.md`, `README.md`, `CHANGELOG.md`, `.specs/codebase/TESTING.md`, `.specs/project/PROJECT.md`, `.specs/project/ROADMAP.md`, `.specs/features/in-app-messages/spec.md`
**Depends on**: T18, T19
**Reuses**: `nse-rich-media/traceability.md` as the template
**Requirement**: IAM-47 and the mapping of all requirements

**Done when**:

- [ ] Every IAM-xx has at least one named test or check in `traceability.md`; the total matches the real count
- [ ] `CHANGELOG.md` `[Unreleased]` contains the 403 divergence line
- [ ] `validate_spec.py` and `validate_tasks.py` pass (the open-questions warning aside); `AGENTS.md` layout line mentions `Sources/NottiSDK/InApp/`
- [ ] Gate check passes: **full**
- [ ] Test count at least the baseline plus the minimums above, none removed

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): in-app-messages traceability and status`

---

### T21: Device validation and Verifier

**What**: Run the device checklist below on a real iPhone and an iPad against a real or staging `zeep-notti` with a message per layout, record pass, fail or not run per line in `validation.md`, then the independent Verifier (`tlc-spec-driven` Validate: author is not verifier, evidence or zero, mutants listed in the design).
**Where**: `.specs/features/in-app-messages/validation.md`
**Depends on**: T20
**Reuses**: `nse-rich-media/validation.md` format
**Requirement**: IAM-48 and all

**Done when**:

- [ ] Every checklist line is marked pass, fail or not run with the device, OS version and server release
- [ ] A fail is either fixed with a regression test or recorded as a todo in `STATE.md` with the owner's decision
- [ ] `python3 .claude/skills/tlc-spec-driven/scripts/validate_state.py .specs/features/in-app-messages` exits 0
- [ ] Gate check passes: **full**

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): in-app-messages validation`

---

## Device validation checklist (T21, manual; nothing here is claimed as tested by this spec)

Use synthetic content; one message per line where needed. Record device, iOS version, server release.

1. Cold start, registered device, one `session_start` message: shown once; `eligible` called once (server log or proxy); `impression` appears in the dashboard once.
2. Background and foreground: new session, new `eligible`; a message the server returns again is shown again; the visible message at background stays and the countdown pauses.
3. Rotation of an open message in each layout (portrait, landscape left and right): no second impression, bounds respected, close control reachable.
4. `top`: swipe up reports `swipe`; touch outside the bar reaches the app; a long body scrolls; the status bar and the Dynamic Island are not covered (safe area); with `margin: true` the bar is 16 pt below the safe-area top and 16 pt from the sides, with `margin: false` it touches the safe-area top and sides (never under the notch or Dynamic Island).
5. `bottom`: swipe down reports `swipe`; with the keyboard open in the host, record whether the bar is above or below it and whether it is tappable (window level, [Incerto]).
6. `center`: backdrop tap reports `outside_tap`; tap inside the card does nothing; VoiceOver focus moves into the card and cannot reach the app behind.
7. `full`: only the close control dismisses; buttons stay pinned with the largest Dynamic Type; text scrolls.
8. Two buttons: side by side on an iPhone, column at a large Dynamic Type or an iPhone SE width; first button primary style, second secondary; with `button_color` both identical.
9. A button with a `deeplink` and one with an `https` URL: the Example listener receives the action, the SDK opens nothing, the display closes, `click` is in the dashboard with the right button, no `dismiss`.
10. Image: with `image_action`, tap reports `click` `image`; an unreachable image host shows the message without the image after about 3 s; a 6 MiB image is not shown.
11. Auto dismiss 8 s: closes at about 8 s with `auto`; after a 5 s background the remaining time resumes; a manual close at 2 s reports `close_button`.
12. `trackEvent`: with an event-triggered message, the exact name shows it; a different case does not; two calls show the second message only on the second call; early call before the fetch completes (OQ-2) behaves as decided; a call before `Notti.initialize`, and a call while the app is in the background after a session ran, show nothing and log no name.
13. Offline: put the device in airplane mode, tap and dismiss, restore: queued events arrive in order with the original `occurred_at`; no duplicates in the dashboard after a forced retry.
14. `429` (staging with a lowered limit) and `5xx` (proxy): the SDK waits, the app stays responsive, login and tags are not delayed; `eligible` `429` with `Retry-After` over 60 s shows no message that session and sends no second request, and `401` (a wrong client key) logs no registration text.
15. VoiceOver reading order, close control label in English and Brazilian Portuguese, the escape gesture (two-finger Z) closing a `center` and a `full` message with `close_button` and doing nothing on `top` and `bottom`, Reduce Motion cross-fade, dark mode default colors, server colors unchanged in dark mode.
16. A non-scene (legacy) app and an iPad with two windows (Split View, Stage Manager): the message appears on one scene; moving the app between scenes does not duplicate impressions.
17. Markdown and HTML in `title` and `body` of a test message are shown verbatim.
18. CocoaPods consumers (static, static libraries, dynamic): the close control label resolves and the message shows.
19. Launch ordering of the `trackEvent` cold-start window ([Provável], the point the owner asked to validate): call `Notti.initialize` and `Notti.trackEvent("fixture_event")` back to back (a) in `application(_:didFinishLaunchingWithOptions:)` and (b) in a SwiftUI `App` `init`, on a cold start with an event-triggered message for that name; record whether the message appears once the first session opens and `eligible` answers, whether `UIApplication.applicationState` was `.inactive` at the call, and the order of `trackEvent`, the `tryOpen()` edge and `didBecomeActive` (breakpoints or a temporary print in the host app, never a log line in the SDK). Also a launch in the background (silent push) followed by a foreground: the name is kept until the first foreground session.
20. Margin on a notch iPhone, portrait and landscape: `margin: true` insets 16 pt from the safe-area edge on `top`, `bottom` and `full`; `margin: false` touches the safe-area edges (horizontally too) without going under the notch or Dynamic Island, the status bar or the home indicator, and in landscape stays inside the left and right insets; `center` is unchanged by `margin`.

---

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| IAM-01 | T7, T10 |
| IAM-02 | T5 |
| IAM-03 | T6, T7 |
| IAM-04 | T5, T6, T7 |
| IAM-05 | T1 |
| IAM-06 | T7, T9, T10 |
| IAM-07 | T3, T7 |
| IAM-08 | T3, T7, T11 |
| IAM-09 | T3, T9 |
| IAM-10 | T7 |
| IAM-11 | T3, T7, T10, T11 |
| IAM-12 | T3, T9 |
| IAM-13 | T15, T16 |
| IAM-14 | T14, T15, T16 |
| IAM-15 | T15, T16 |
| IAM-16 | T1 |
| IAM-17 | T14 |
| IAM-18 | T15, T16, T17 |
| IAM-19 | T9, T15 |
| IAM-20 | T2, T14 |
| IAM-21 | T2, T14, T15, T16 |
| IAM-22 | T2, T14 |
| IAM-23 | T14, T18 |
| IAM-24 | T11, T18 |
| IAM-25 | T9, T11 |
| IAM-26 | T9 |
| IAM-27 | T9 |
| IAM-28 | T9 |
| IAM-29 | T4, T5, T9 |
| IAM-30 | T4, T6, T7, T9 |
| IAM-31 | T6 |
| IAM-32 | T6 |
| IAM-33 | T6, T10 |
| IAM-34 | T9 |
| IAM-35 | T9 |
| IAM-36 | T17 |
| IAM-37 | T17 |
| IAM-38 | T13, T14, T17 |
| IAM-39 | T14, T17 |
| IAM-40 | T8 |
| IAM-41 | T8, T9 |
| IAM-42 | T8 |
| IAM-43 | T18 |
| IAM-44 | T11, T12 |
| IAM-45 | T18 |
| IAM-46 | T18 |
| IAM-47 | T19, T20 |
| IAM-48 | T21 |

48 requirements, 48 mapped to tasks.
