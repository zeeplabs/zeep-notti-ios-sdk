# In-App Messages Tasks

**Design**: `.specs/features/in-app-messages/design.md`
**Spec**: `.specs/features/in-app-messages/spec.md`
**Testing**: `.specs/codebase/TESTING.md`
**Depends on feature**: none blocking. Part of M1 / `0.1.0` (AD-017): T19 edits the existing `Example/` app, T20 the `[0.1.0]` release notes. Server: `zeep-notti` v0.23.0 or later serves the payload (OQ-6 closed). Recorded dependency, not a task: the `zeep-notti` per-SDK minimum for `push_permission` (AD-019 decision 4). The AD-018 core fixes land first as separate commits
**Status**: Approved by Julio 2026-10-24 (scope and the four AD-019 decisions), reconciled with `react-native-notti` 0.8.0. Not started

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`): **activate it by name and follow its Execute flow and Critical Rules.** Project rules are in `AGENTS.md`.

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

## Test Coverage Matrix

> Guidelines found: `AGENTS.md`, `.specs/codebase/TESTING.md`, `.swiftlint.yml`, `.github/workflows/ci.yml`. Baseline: **`NottiSDKTests` 458 on branch `fix/swiftui-adaptor-delegate`; the core-parity fixes (AD-018) running in parallel add some, so re-count at T1 and call that number `B`**. Counts below are minimum new tests per task and cumulative totals of `NottiSDKTests` from `B`; the total never drops. The ObjC and Example hosted tests are counted separately.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Model and parser (`NottiInAppMessage`, `NottiInAppMessageParser`) | unit | contract example payload field by field, unknown fields, bad message skipped, unknown format, blank text, action narrowing and `push_permission`, image rules, buttons cap, dismiss range | `Tests/NottiSDKTests/NottiInAppMessageParserTests.swift` | `-only-testing:NottiSDKTests/NottiInAppMessageParserTests` |
| Style (`NottiInAppStyle`, `NottiInAppColor`) | unit | valid and invalid colors table, defaults for `text_align` and `margin` | `Tests/NottiSDKTests/NottiInAppStyleTests.swift` | same, `NottiInAppStyleTests` |
| Selector (`NottiInAppSelector`) | unit | session start, event match, order, once per session, visible, early names (first 32) | `Tests/NottiSDKTests/NottiInAppSelectorTests.swift` | same |
| Event store (`NottiInAppEventStore`) | unit | RN key and schema, persist, reload, cap, TTL boundary, order, `appId` purge, self-heal, no secrets stored | `Tests/NottiSDKTests/NottiInAppEventStoreTests.swift` | same |
| API client (`NottiInAppApiClient`) | unit | request shape, `Retry-After`, status mapping | `Tests/NottiSDKTests/NottiInAppApiClientTests.swift` (with `StubURLProtocol`) | same |
| Flusher (`NottiInAppEventFlusher`) | unit | status table (2xx, other 4xx, 408, 401 vs 403), FIFO, stable `eventId`, purge, expiry, modes | `Tests/NottiSDKTests/NottiInAppEventFlusherTests.swift` (fake scheduler) | same |
| Engine (`NottiInAppEngine`) | unit | fetch once per session, registered flag, policies (`eligible` 429 cap and cross-session pause, 408, 401 vs 403), events pause and coalescing, network resume, foreground session, late response, cold-start window, display state machine, `push_permission` click, timer, reset on config change | `Tests/NottiSDKTests/NottiInAppEngine*Tests.swift` (fake presenter, scheduler, clock) | same |
| Image loader (`NottiInAppImageLoader`) | unit | decode bounds and orientation, caps, redirect, status, budget, LRU, no credentials | `Tests/NottiSDKTests/NottiInAppImageLoaderTests.swift` | same |
| Runtime and core hooks | unit | two hooks reach the engine once, adopt does not, process observers open and end sessions, replacement core keeps the engine, `configure` ordered before a same-thread `trackEvent` | `Tests/NottiSDKTests/NottiInAppWiringTests.swift`, existing `NottiCoreTests` untouched | same |
| Push permission action (`NottiPushPermissionAction`) | unit | state table, the one allowlisted open | `Tests/NottiSDKTests/NottiPushPermissionActionTests.swift` | same |
| Public shell, facade, ObjC | unit + ObjC compile check | `trackEvent`, listener, payload keys, `action` or `NSNull` | `Tests/NottiSDKTests/NottiInAppPublicApiTests.swift`, `Tests/NottiSDKObjCTests/*.m` | same, `NottiSDKObjCTests` |
| Accessibility label table | unit | `Close` / `Fechar` by primary subtag, fallback English, no resource lookup | `Tests/NottiSDKTests/NottiInAppStringsTests.swift` | same |
| View hierarchy (`NottiInAppMessageView`, layouts) | unit (UIKit in the test host) | bounds per layout and size, close inset and chip, image sizing, buttons into scroll, pan threshold, verbatim text, absolute alignment, a11y, Dynamic Type | `Tests/NottiSDKTests/NottiInApp*LayoutTests.swift`, `NottiInAppMessageViewTests.swift` | same |
| Presenter and window | unit | non-key window, pass-through, host orientation, scene move, Reduce Motion, escape gesture | `Tests/NottiSDKTests/NottiInAppPresenterTests.swift` | same |
| Privacy and source greps | unit | sentinels over every path, banned APIs in sources outside the allowlisted file | `Tests/NottiSDKTests/NottiInAppPrivacyTests.swift` | same |
| Scripts (`check-no-url-open.sh`, `check-public-surface.sh`) | script | passing tree and failing fixtures | `scripts/` | the scripts |
| Packaging (`Package.swift`, podspec, `PUBLIC_SURFACE.txt`) | none | scripts and `pod lib lint`, strict device builds | - | the scripts, `pod lib lint` |
| Example app | hosted unit (Example scheme) | `trackEvent` button wired, listener registered | `Example/Tests/` | per `example-and-release` |
| Docs (README, CHANGELOG, TESTING, ROADMAP, release PR, traceability) | none | every IAM-xx mapped to a named test | - | - |

`...` = `-scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO`. Tests are not parallel-safe in one checkout (TESTING.md): run tasks sequentially. New tests use synthetic values (`example.invalid`, `fixture`) and an isolated `UserDefaults` suite per test; none touches the network or `NottiRuntime.shared`.

## Gate Check Commands

> From `.github/workflows/ci.yml` and `.specs/codebase/TESTING.md`. Run `xcodebuild test` through the same watchdog as the previous features, and do not pipe `xcodebuild` into `grep`.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests only | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:NottiSDKTests/<Class>` |
| Full | After T10, T22, T12, T17, T18, T20 | `xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO` + `docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict` + `scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh && scripts/check-public-surface.sh && scripts/check-no-url-open.sh && scripts/check-launch-hook-purity.sh && scripts/check-nse-logging.sh` + the strict device builds (`xcodebuild build -scheme NottiSDK -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES -quiet`, and `NottiSDKExtension` with `APPLICATION_EXTENSION_API_ONLY=YES`) + `pod lib lint NottiSDK.podspec --platforms=ios && pod lib lint NottiSDKExtension.podspec --platforms=ios` (also `--use-libraries`) + `scripts/check-hook-linked.sh spm` and `pod` |
| Build | Build-only checks | `xcodebuild build -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -quiet` + SwiftLint + scripts |
| Spec docs | After editing any spec file | `python3 .claude/skills/tlc-spec-driven/scripts/validate_spec.py .specs/features/in-app-messages/spec.md` and `validate_tasks.py` on this file |

---

## Rules (apply to every task)

1. New code: `write-swift` and `swift-concurrency` guidance applies, in Swift 5 mode (AD-002 spirit): value types for state, small types, no `actor`, no `AsyncStream`; the engine is a class confined to its serial queue (design D1). Public API additions follow the `public-api` shell pattern. Behavior follows RN 0.8.0 (AD-017, AD-019): when a task is unclear, read the RN file the design cites and copy its behavior.
2. Everything lives in `Sources/NottiSDK/InApp/` plus the listed edits. Nothing under `Sources/NottiShared` or `Sources/NottiSDKExtension` changes. UI types and anything touching `UIApplication` carry `@available(iOSApplicationExtension, unavailable)`.
3. **No source text, comments included, may contain** `openURL`, `UIApplication.shared.open` or `.open(_:options` (`check-no-url-open.sh`), except `Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift` (T22, the one allowlisted file, AD-019); nor `attributedText`, `AttributedString`, `WKWebView`, `LocalizedStringKey` in `InApp/UI` (plain text, IAM-23); nor `systemUptime`, `mach_absolute_time`, `contentModificationDate`, `fileModificationDate` (privacy manifest, D8).
4. Logging only through `NottiLogger` category `inapp`: fixed codes, `"\(error.domain)#\(error.code)"`. Never the token, device id, message id, title, body, label, URL, event name or `localizedDescription` (IAM-43).
5. Tests derive from the spec's acceptance criteria. Time, network, scenes, permission state and the presenter are injected: no real sleeps, no network, no `NottiRuntime.shared`. Contract and continuity values (paths, JSON keys, the queue key `notti_pending_inapp_events` and its record keys, reasons, status handling, the 7 day and 100 limits, the events `Retry-After` clamp, the 60 s `eligible` cap, the RN layout metrics) are asserted as literals, not through the constants the code reads (lesson from `delegate-integration` G1, as NSE-18).
6. Every `event_id` is generated when the event occurs and never regenerated (IAM-29). Every task that records events has a test of it.
7. Ported files change only where a task lists it: `NottiCore.swift` (T10, the hooks parameter and two hook calls), `NottiRuntime.swift` (T10 observers and engine, T17 presenter, T22 port), `NottiApiClient.swift` (T5, `percentEncodedPathComponent` from `private` to `internal`).
8. Do not run two `xcodebuild` processes on the same checkout. Each task is one commit, conventional style, no AI attribution.

---

## Execution Plan

All tasks run sequentially (TESTING.md: not parallel-safe). Suggested split for sub-agents: T1 to T10 plus T22 (logic, no UI), then T11 to T21.

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
T10 ──→ T22
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
T22 ──→ T18
T12 ──→ T19
T17 ──→ T19
T18 ──→ T20
T19 ──→ T20
T20 ──→ T21
```

Sequential order used in Execute: T1 → ... → T10 → T22 → T11 → ... → T21.

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
| T22 | T10 | `T10 → T22` |
| T11 | T10 | `T10 → T11` |
| T12 | T11 | `T11 → T12` |
| T13 | None | `T13 → T14` |
| T14 | T2, T13 | `T2 → T14`, `T13 → T14` |
| T15 | T14 | `T14 → T15` |
| T16 | T14 | `T14 → T16` |
| T17 | T9, T10, T15, T16 | the four edges into T17 |
| T18 | T11, T17, T22 | `T11 → T18`, `T17 → T18`, `T22 → T18` |
| T19 | T12, T17 | `T12 → T19`, `T17 → T19` |
| T20 | T18, T19 | `T18 → T20`, `T19 → T20` |
| T21 | T20 | `T20 → T21` |

No `[P]` task.

---

## Task Breakdown

### T1: Message model and lenient parser

**What**: `NottiInAppMessage`, `NottiInAppFormat`, `NottiInAppTrigger`, `NottiInAppButton`, `NottiInAppButtonAction` (`.link(type, value)` or `.pushPermission`) and `NottiInAppMessageParser.parse(_:)` over `JSONSerialization`, a port of RN `NottiInAppModels.swift:81-244`. Each message is mapped independently; rules of IAM-16.
**Where**: `Sources/NottiSDK/InApp/Model/NottiInAppMessageParser.swift` (types in `NottiInAppMessage.swift` beside it), `Tests/NottiSDKTests/NottiInAppMessageParserTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: IAM-05, IAM-16, IAM-49 (parse side)

**Done when**:

- [x] The example payload of `docs/en/sdks/in-app-messages.md` (ids replaced by `fixture` values, `example.invalid` URLs) maps field by field, including `trigger`, both buttons, `image_action`, `style`, `dismiss_after_seconds`
- [x] Unknown fields at every level are ignored; an unknown `format` becomes `center`; `style: null` and a missing `style` both give default style input
- [x] A message with an empty `id`, with blank title and body (empty or whitespace only), with an unknown trigger type, or with an `event` trigger without `name` is not renderable and the others survive; a non-object body or a non-array `messages` gives nil
- [x] A button without `id` or `label` is dropped and a third button is dropped; an action `url` or `deeplink` with an empty or missing `value` is nil while its button is kept; an unknown action type is nil; `push_permission` on a button gives `.pushPermission` (no value read); `push_permission` as `image_action` is dropped
- [x] `image_url` with `http`, `https://` alone or garbage is dropped; `image_action` without a valid image is dropped; `dismiss_after_seconds` 0, 301, 8.5, `true` and a string give nil, 1, 8.0 and 300 are kept; `margin: 1` is not read as a boolean (default `true`)
- [x] Gate check passes: quick
- [x] Test count: at least 14 new, total at least B + 14

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): parse the eligible payload leniently`

---

### T2: Style tokens and color parsing

**What**: `NottiInAppStyle` (optional tokens, `textAlign` default `left`, `margin` default `true`, built from the parser's raw `style`) and `NottiInAppColor.parse(_:)` returning `0xFFRRGGBB` only for `#` plus six hex digits, checked byte by byte (RN `parseHexColor`).
**Where**: `Sources/NottiSDK/InApp/Model/NottiInAppStyle.swift`, `Tests/NottiSDKTests/NottiInAppStyleTests.swift`
**Depends on**: T1
**Reuses**: the raw style dictionary the parser keeps
**Requirement**: IAM-20, IAM-21, IAM-22 (token side)

**Done when**:

- [ ] `#102030`, `#e94b8b`, `#FFFFFF` parse to the exact components; `#FFF`, `102030`, `#10203040`, `#GGGGGG`, `#+12345`, empty, `red`, a number and nil give nil and no throw
- [ ] `text_align` `left`, `center`, `right` map; absent or unknown is `left`; `margin` true, false, absent (true), non-boolean (true)
- [ ] An invalid token does not affect the others in the same `style`
- [ ] Gate check passes: quick
- [ ] Test count: at least 10 new, total at least B + 24

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): style tokens and safe color parsing`

---

### T3: Selector

**What**: `NottiInAppSelector` value type: `load`, `track`, `noteEarly`, `startSession`, `endSession`, `reset` as designed (first session start, held event messages, exact match, oldest first, once per session, ignore while visible, early names distinct with the first 32 kept, skip a visible id, drop session-start candidates when something is visible), a port of RN `NottiInAppSession.swift:156-242,298-315`.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppSelector.swift`, `Tests/NottiSDKTests/NottiInAppSelectorTests.swift`
**Depends on**: T1
**Reuses**: the model types
**Requirement**: IAM-07, IAM-08, IAM-09, IAM-11, IAM-12

**Done when**:

- [ ] Two session-start messages: only the first is returned and the second never is, in the same session
- [ ] Two event messages with the same name: the first `track` returns the older, the second `track` returns the other, the third returns nil; `Checkout_Done` does not match `checkout_done`; `" checkout_done"` does not match
- [ ] `track` while visible returns nil and does not consume the message
- [ ] Names noted before `load` are replayed in call order, once, returning at most one message; a repeated name is kept once; 33 distinct names keep the **first** 32 (the 33rd is ignored)
- [ ] `startSession` clears held messages and `shown`, keeps the early names (replayed by a later `load`), and adds a visible id to `shown`; `endSession(wasOpen: true)` clears the early names, `endSession(wasOpen: false)` keeps them; `reset()` clears everything
- [ ] `load` with a visible id skips that id and returns no session-start message
- [ ] Gate check passes: quick
- [ ] Test count: at least 15 new, total at least B + 39

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): message selection per session`

---

### T4: Event store

**What**: `NottiInAppEventRecord` (Codable, exactly `id`, `eventId`, `appId`, `messageId`, `type`, `buttonId?`, `reason?`, `occurredAtMs`) and `NottiInAppEventStore` over `UserDefaults` key `notti_pending_inapp_events` as JSON `Data`: `enqueue`, `all`, `all(forApp:)`, `remove(id:)`, `expire(now:)`, `purgeOtherApps`, cap 100, process-wide lock, write per mutation, self-heal on decode failure. A port of RN `NottiInAppEventStore.swift` (AD-019 decision 2).
**Where**: `Sources/NottiSDK/InApp/Storage/NottiInAppEventStore.swift`, `Tests/NottiSDKTests/NottiInAppEventStoreTests.swift`
**Depends on**: None
**Reuses**: the shape of RN `NottiInAppEventStore.swift`, not `NottiEventStore`
**Requirement**: IAM-29, IAM-30

**Done when**:

- [ ] Records survive a new store over the same suite, in insertion order, with the same `id`, `eventId`, `appId`, `occurredAtMs`, `buttonId`, `reason`; `id` and `eventId` are distinct lowercase UUID strings
- [ ] A JSON fixture written byte for byte in RN 0.8.0's format (literal keys `id`, `eventId`, `appId`, `messageId`, `type`, `buttonId`, `reason`, `occurredAtMs`) under the literal key `notti_pending_inapp_events` decodes into the same records; the data the store writes has exactly those keys
- [ ] The 101st record drops the oldest; `expire` with an injected `now` drops a record 7 days plus 1 ms old and keeps one exactly 7 days old; `enqueue` drops expired records first
- [ ] The stored JSON contains no `token` and no `device_id`
- [ ] `purgeOtherApps` removes the records of other apps, keeps the current app's in order, and is a no-op when all match
- [ ] A value that does not decode (corrupt bytes, a record without `appId`) is removed, the queue reads empty, and one `.warn` without content is logged
- [ ] The CTR key `notti_pending_events` is untouched by every operation
- [ ] Gate check passes: quick
- [ ] Test count: at least 13 new, total at least B + 52

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): persistent in-app event queue compatible with react-native-notti`

---

### T5: API client

**What**: `NottiInAppApiClient` with `eligible(deviceId:token:completion:)` and `report(_:deviceId:token:completion:)`, non-blocking, one attempt each, results mapped as RN `NottiApiClient.swift:269-311` (eligible: `messages`, `rateLimited`, `unauthorized`, `forbidden`, `terminal`, `transient`; events: `recorded`, `drop`, `rateLimited`, `unauthorized`, `forbidden`, `transient`). Promote `NottiApiClient.percentEncodedPathComponent` from `private` to `internal` (one-word edit) and reuse `validatedBaseUrl`.
**Where**: `Sources/NottiSDK/InApp/Network/NottiInAppApiClient.swift` (and the one-word edit in `Sources/NottiSDK/Network/NottiApiClient.swift:142`), `Tests/NottiSDKTests/NottiInAppApiClientTests.swift`
**Depends on**: None
**Reuses**: `NottiApiClient.validatedBaseUrl`, `percentEncodedPathComponent`, `StubURLProtocol`
**Requirement**: IAM-02, IAM-04, IAM-29, IAM-31

**Done when**:

- [ ] `eligible` sends `POST`, the exact path `/v1/apps/<appId>/in-app-messages/eligible`, `Authorization: Bearer <key>`, `Content-Type: application/json; charset=utf-8`, and a body whose keys are exactly `device_id` and `token`
- [ ] `report` sends the path `/v1/apps/<appId>/in-app-messages/<messageId>/events` with a body of exactly `device_id`, `token`, `event_id`, `type`, `occurred_at` (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` UTC) and, only when set, `button_id` (click only) or `reason` (dismiss only); a path component with a space or `/` is percent-encoded as one segment
- [ ] Eligible: a 2xx with a valid body gives `messages`, a 2xx with an unparseable body gives `transient`; 401 `unauthorized`, 403 `forbidden`, 404, 422 and 400 `terminal(status)`, 408, 500, 503 and a transport error `transient`. Events: 200, 201 and 204 `recorded`, 400, 404, 409, 422 `drop`, 401, 403, 408 as above
- [ ] 429 with `Retry-After: 7` gives 7, `0` gives 0, ` 120 ` gives 120 (unclamped), `99999999999` gives `Int32.max`; missing, `soon`, `-5`, `1.5` and an HTTP-date give nil
- [ ] The existing `NottiApiClientTests` still pass unchanged
- [ ] Gate check passes: quick (`NottiInAppApiClientTests` and `NottiApiClientTests`)
- [ ] Test count: at least 13 new, total at least B + 65

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): non-blocking client for the in-app routes`

---

### T6: Event flusher

**What**: `NottiInAppEventFlusher`: one pass (`runPass(appId:identity:singleAttempt:headFailures:) -> Outcome`), a port of RN `runFlushPass` (`NottiInAppCoordinator.swift:568-603`): purge other apps, expire (one fixed log line), oldest first for the current app, the status table of IAM-31, outcomes `done`, `paused(seconds)`, `unauthorized`, `forbidden`, `failed`, `backoff(failures)`. Defines `NottiInAppScheduling` (`execute`, `schedule(after:)`) used by later tasks. The engine owns the outcome handling (T7).
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEventFlusher.swift`, `Tests/NottiSDKTests/NottiInAppEventFlusherTests.swift`
**Depends on**: T4, T5
**Reuses**: the store and the client
**Requirement**: IAM-30, IAM-31, IAM-32

**Done when**:

- [ ] 201, 200 and 204 remove the record and continue; 404, 422 and 400 remove it, log one fixed code and continue; each is a separate test with the exact status
- [ ] 401 returns `unauthorized` and 403 returns `forbidden` with the queue intact; no line contains a token, id, URL or body (sentinels in the stub response)
- [ ] 408 on the head behaves exactly like 503: full mode returns `backoff(1)`..`backoff(4)` across calls with the **same `eventId` in all five bodies**, then `failed` with the queue intact; single-attempt mode returns `failed` after one request
- [ ] 429 returns `paused` with the unclamped seconds (nil when absent) and sends nothing more in that pass
- [ ] A record of another app is purged before sending and never sent; with only other-app records no request is made
- [ ] A failing head is never skipped: with impression then click queued and the impression failing, the click is never sent
- [ ] Records older than 7 days are removed without a request
- [ ] Gate check passes: quick
- [ ] Test count: at least 19 new, total at least B + 84

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): ordered, resumable event flush`

---

### T7: Engine, sessions, fetch and selection

**What**: `NottiInAppEngine` core, a port of the fetch, flush and session parts of RN `NottiInAppCoordinator.swift` and `NottiInAppSession.swift`: queue confinement; `configure`; `sessionStarted` (idempotent, deferred while in background); `appForegrounded` (opens later sessions, D14); `sessionEnded`; `appBackgrounded`; `deviceRegistered` (`registeredInProcess`); `networkAvailable` (resume a transient give-up once); `trackEvent` (rule of D12, blank no-op); `maybeFetch` with the `eligible` pause that outlives the session; pre-fetch single-attempt flush skipped during an events pause, owning the flag only when free; `eligible` result policy (IAM-04); flush requests with coalescing, backoff rescheduling, events pause deadline and its scheduled resume, `401` key rejection, `403` warning once per session per route; generation checks; `resetForNewConfig()` (D13). The chosen message is handed to a `NottiInAppPresenting` protocol (defined here with the fake used in tests). The display lifecycle is T9.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift`, `Tests/NottiSDKTests/NottiInAppEngineFetchTests.swift`
**Depends on**: T1, T3, T5, T6
**Reuses**: selector, client, flusher, store, `NottiMainDispatcher`
**Requirement**: IAM-01, IAM-03, IAM-04, IAM-06, IAM-07, IAM-08, IAM-10, IAM-11 (engine side), IAM-30 (purge on config change), IAM-31 (outcome handling), IAM-33, IAM-51 (engine side), IAM-52

**Done when**:

- [ ] Session then registration gives one `eligible`; registration then session gives one; a second registration or a repeated `sessionStarted` adds none; `sessionEnded` then `appForegrounded` gives a second call; no `eligible` is sent while `registeredInProcess` is false (a session with only a persisted device id sends none); `registeredInProcess` survives `sessionEnded`, so the next session fetches without a new registration
- [ ] `sessionStarted` while a session is open is ignored; `sessionStarted` after `appBackgrounded` opens nothing, and the next `appForegrounded` opens that session; `appForegrounded` before any session has opened (and with no deferred report) opens nothing
- [ ] The first session-start message is handed to the presenter; an event message is held and handed only on a matching `trackEvent`; nothing is sent to the server for `trackEvent` (stub request list)
- [ ] With a non-empty queue the flush request precedes the `eligible` request and a failing flush does not prevent `eligible` (503, 429, 403, transport); while an events `429` pause is active the pre-fetch flush is skipped and `eligible` is sent directly; a pre-fetch pass during a running full flush does not clear that flush's flag
- [ ] A `401` in the pre-`eligible` flush skips `eligible` for the session: no `eligible` request, one generic fixed code and no registration text, the queue kept, no flush either until the next session, after which both run again
- [ ] 403 on `eligible` logs exactly one `.warn` with the fixed text `Notti: in-app messages are inactive on this device until the next registration (HTTP 403)` (sentinel-free) and stops for the session; 401 stops with no retry and **no line containing the registration text**; 422 stops with no retry
- [ ] `eligible` 429 with `Retry-After: 120` gives up: no wait scheduled, one request; `2` retries at 2 s on the fake scheduler; `0` waits 1 s; absent, `soon` and `-5` wait 60 s; `61` gives up and `60` waits 60 s; at most 3 waits. With `Retry-After: 30`, `sessionEnded` at 10 s and a new session at 15 s: no request before 30 s, one at 30 s; a config change clears the pause
- [ ] 503, 408, a transport error and an unparseable 2xx retry with 2/4/8/16 s (5 attempts) then give up; a later `networkAvailable` resumes the fetch once (one more request), a second `networkAvailable` with no new failure sends nothing; after a `403`, `422` or `401` give-up `networkAvailable` sends no `eligible`
- [ ] Events outcomes: 429 pauses every flush trigger until clamp(value, 1...300) s (0 → 1, 9999 → 300, absent → 60) and then flushes once; ten triggers during one run produce at most one extra pass; a full-mode transient head is retried after 2/4/8/16 s with the same `eventId`
- [ ] A late response after `sessionEnded` is ignored: nothing held, nothing presented, a later `trackEvent` matches nothing; the same for a response issued under session 1 that arrives after session 2 opened; held event messages are gone after `sessionEnded`
- [ ] A new engine over the same suite shows the same message again (no persisted shown state)
- [ ] `configure` with a different appId, clientKey or baseUrl resets held messages, names, the fetch, `registeredInProcess`, the key-rejected flag and both pause deadlines, ignores an in-flight response and purges other apps' records; a same-config `configure` changes none of it
- [ ] Cold-start window: `configure` then `trackEvent("fixture_event")` then `sessionStarted`, `deviceRegistered` and a matching response presents it once; names before the first `configure`, after `sessionEnded` while no session is open, and blank names are ignored and never logged (no warning); 33 distinct early names keep the first 32; a re-initialize after the first session does not re-arm the flag
- [ ] Race test: `configure` immediately followed by `trackEvent` on the same thread, then `sessionStarted` and `deviceRegistered` in either order, still matches once
- [ ] The engine never runs its network or storage work on the main thread
- [ ] Gate check passes: quick
- [ ] Test count: at least 30 new, total at least B + 114

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): fetch eligible messages once per session`

---

### T8: Image loader

**What**: `NottiInAppImageLoader`, a port of RN `NottiInAppImageLoader.swift`: credential-free ephemeral session, delegate-based download that ends once (non-`https` redirect refused, non-2xx or declared length over 5 MiB refused, abort past 5 MiB, whole call bounded to 10 s), `decode(_:maxSidePx:)` always through `CGImageSourceCreateThumbnailAtIndex` with transform and `min(longest side, maxSidePx)`, LRU cache of 5 cleared on a memory warning, `load(url:maxSidePx:done:)`.
**Where**: `Sources/NottiSDK/InApp/Image/NottiInAppImageLoader.swift`, `Tests/NottiSDKTests/NottiInAppImageLoaderTests.swift`
**Depends on**: None
**Reuses**: the redirect and early-cancel technique proved in `nse-rich-media` (`NottiRichMediaJob`), `StubURLProtocol`
**Requirement**: IAM-40, IAM-41 (loader side), IAM-42

**Done when**:

- [ ] A synthetic 4000 x 1000 PNG decoded with `maxSidePx: 1000` has a longest side of 1000; a 200 x 100 PNG with `maxSidePx: 1000` stays 200 x 100 (never upscaled); a small JPEG with EXIF orientation 6 decodes upright (width and height swapped)
- [ ] A stub declaring 6 MiB, and one sending 6 MiB without a length, are cancelled early and return nil; a 404 returns nil; a response that never ends returns nil at 10 s
- [ ] A redirect to an `http` URL returns nil; a non-image body returns nil; a transport error returns nil
- [ ] The captured request has no `Authorization` header and no cookies; the session configuration has no URL cache, cookie storage or credential storage; the initializer takes no credentials
- [ ] The second request for the same URL is served from the cache (one request in the stub); the sixth distinct URL evicts the least recently used; a memory warning empties the cache
- [ ] Gate check passes: quick
- [ ] Test count: at least 12 new, total at least B + 126

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): bounded, credential-free image loading`

---

### T9: Engine, display state machine and timer

**What**: Add to the engine: `NottiInAppDisplay` (states `preparing`, `visible`, `closed`), `displayAttached`, `becameVisible`, `userTapped(displayId:buttonId:action:)`, `userDismissed`, `displayFailed`, the clock by remaining wall-clock time (paused while detached or in background), taps and dismisses ignored until `visible` (RN), event recording plus a flush request, the click emission through the injected closure, the `push_permission` path (listener gets `action: nil`, no warning, close, then `pushPermissionPort` on main; nil port: report and close only) and `setPushPermissionPort`. `resetForNewConfig()` and `sessionEnded()` teardown of a display (visible kept at session end, preparing dropped). Invariants of the design.
**Where**: `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift` (extension in `NottiInAppEngine+Display.swift`), `Tests/NottiSDKTests/NottiInAppEngineDisplayTests.swift`
**Depends on**: T7, T8
**Reuses**: everything above
**Requirement**: IAM-09, IAM-12, IAM-19 (click of the body target), IAM-25, IAM-26, IAM-27, IAM-28, IAM-29, IAM-30, IAM-34, IAM-35, IAM-41 (engine side), IAM-06 (teardown on config change), IAM-49

**Done when**:

- [ ] `becameVisible` three times records one `impression`; a tap or dismiss before `becameVisible` is ignored and queues nothing (RN `NottiInAppSession.swift:258-262`)
- [ ] A button tap records `click` with that `button_id`, emits one click with the link action, asks the presenter to close, records no `dismiss`; an image tap records `click` with `image`; a second tap in the same turn is ignored; a tap with an unknown action emits `action: nil`
- [ ] With no listener (`emitClick` returns false) a link tap logs exactly one fixed `.warn`; a `push_permission` tap logs nothing
- [ ] A `push_permission` tap records `click` with the button id, emits `action: nil`, closes, then calls the port exactly once on the main dispatcher (call order recorded: enqueue, emit, close, port); with no port set it only records, emits and closes; a port set through `setPushPermissionPort` is read on the engine queue
- [ ] Dismiss reasons `close_button`, `swipe`, `outside_tap` are recorded as given; the timer records `auto`
- [ ] `dismiss_after_seconds: 8` fires at 8 s on the fake clock; a 3 s background pause (`appBackgrounded` / `appForegrounded`) moves it to 11 s; `displayAttached(false)` pauses it too; a close at 2 s cancels the timer and records `close_button`; null, 0, 301 give no timer
- [ ] Every recorded event has a lowercase UUID `eventId` generated at record time; two events never share one
- [ ] At most one display exists at any time; an event while visible is ignored; a message id is presented once per session; `sessionEnded` keeps a visible display and drops a preparing one with no event
- [ ] A config change while a message is visible tears the display down with **no** event recorded, the pending timer never fires, and a late `becameVisible`, tap or close for the old display id is ignored; a same-config `configure` leaves the display untouched
- [ ] Gate check passes: quick
- [ ] Test count: at least 22 new, total at least B + 148

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): display lifecycle, events and auto dismiss`

---

### T10: Core hooks and runtime wiring

**What**: Add `NottiInAppHooks` (two optional closures, no-op default) to `NottiCore.init` and call them: `onSessionStarted` in the `tryOpen() == true` branch (`NottiCore.swift:1020`), `onDeviceRegistered` after the success bookkeeping in `registerDevice` (after `:722`). `NottiRuntime` owns the engine (production client factory, `NottiDeviceStore` identity reader, a placeholder no-op presenter until T17), passes the hooks in `makeCore()`, calls `configure` in `start` before `core.initialize` (D12), extends the existing `didEnterBackground` observer (`NottiRuntime.swift:74-83`) to call `engine.sessionEnded()` then `engine.appBackgrounded()` after `gate.close()`, adds a process `willEnterForeground` observer that calls `engine.appForegrounded()`, and forwards `onNetworkAvailable` to the engine (RN `NottiImpl.swift:46-85`, `NottiNetworkObserver.swift:66-67`).
**Where**: `Sources/NottiSDK/Core/NottiCore.swift`, `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiInAppWiringTests.swift`
**Depends on**: T9
**Reuses**: `NottiCore.SessionGate`, the runtime's observers
**Requirement**: IAM-01, IAM-06, IAM-11 (launch ordering), IAM-33, IAM-51

**Done when**:

- [ ] A core with a fake gate and fake registration calls `onSessionStarted` once per real session and never for the adopted session, and `onDeviceRegistered` after each registration `.success` and not after a failure
- [ ] An isolated runtime delivers both hooks to its engine; replacing the core (`start` with a different config) keeps the same engine instance, and the engine's session state is reset only for a changed config
- [ ] Posting `didEnterBackground` to the runtime's notification center ends the engine session even with no live core; posting `willEnterForeground` after a first session opens the next one and sends `eligible` while the fake core's work queue is blocked (a semaphore held for the whole test step), and the core's late `onSessionStarted` adds no request
- [ ] `runtime.onNetworkAvailable()` triggers an engine flush and the transient-resume path
- [ ] Race test at runtime level: `runtime.start(...)` immediately followed by `engine.trackEvent` on the same thread with an app-state provider that reports inactive: no session yet, the name is kept; flipping the provider to active opens the session through the core hook, and the response then matches the name once
- [ ] Re-initialize through `start`: the same config leaves the engine state untouched; a different config resets it and purges other apps' queue records (the persisted suite is inspected)
- [ ] The existing `NottiCoreTests`, `NottiRuntimeTests` and `NottiContinuityTests` pass unchanged, and the diff of `NottiCore.swift` is the init parameter plus the two call lines
- [ ] Gate check passes: **full**
- [ ] Test count: at least 14 new, total at least B + 162

**Tests**: unit
**Gate**: full
**Commit**: `feat(inapp): wire the session and registration edges to the engine`

---

### T22: Push permission platform action and the URL-open allowlist

**What**: `NottiPushPermissionAction` (design D15), a port of RN `NottiPushPermissionAction.swift`: `State` from `UNAuthorizationStatus`, `run()` with injected `readState`, `requestPermission`, `openNotificationSettings`, `logger`; production statics (`getNotificationSettings`; on main, `UIApplication.openNotificationSettingsURLString` on iOS 16+ else `openSettingsURLString`, then the open call). `NottiRuntime.start` builds it with `requestPermission` going to the runtime's current core (`NottiCore.requestPermission`, `NottiCore.swift:365`) and hands it to the engine through `setPushPermissionPort` (RN `396d320`). `scripts/check-no-url-open.sh` gains an exact-path allowlist of this one file; the AGENTS.md bullet "The SDK never opens a URL" (section "Delegate integration and the launch hook") states the exception (AD-019).
**Where**: `Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift`, `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `scripts/check-no-url-open.sh`, `AGENTS.md`, `Tests/NottiSDKTests/NottiPushPermissionActionTests.swift`
**Depends on**: T10
**Reuses**: RN `NottiPushPermissionActionTests.swift` cases, `NottiCore.requestPermission`
**Requirement**: IAM-45, IAM-50, IAM-49 (wiring)

**Done when**:

- [ ] `notDetermined` calls `requestPermission` once and nothing else; `denied` calls `openNotificationSettings` once; `authorized`, `provisional` and `ephemeral` call nothing; `unknown` logs exactly one fixed line with no values; a state answered on a background thread still runs the row
- [ ] A source test reads `NottiPushPermissionAction.swift` and asserts that the only URL sources are `openNotificationSettingsURLString` and `openSettingsURLString` (no `URL(string:` over anything else, no message or payload type referenced)
- [ ] An isolated runtime after `start` gives the engine a port; a `push_permission` tap with a fake permission reader in state `notDetermined` reaches the fake core's `requestPermission`; after a core replacement the port reaches the new core
- [ ] `scripts/check-no-url-open.sh` passes on the tree; a fixture tree with an open call in `Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift` fails; a fixture with the allowlisted file only passes; a fixture where the allowlisted path is moved fails
- [ ] AGENTS.md names the exception and the allowlisted path
- [ ] Gate check passes: **full**
- [ ] Test count: at least 8 new, total at least B + 170

**Tests**: unit
**Gate**: full
**Commit**: `feat(inapp): push permission button action with one allowlisted settings URL`

---

### T11: Public API (Swift)

**What**: `Notti.trackEvent(_:)`, `Notti.InAppMessages.addClickListener`, `NottiInAppClick` (`messageId`, `buttonId`, `action: NottiInAppAction?`) and `NottiInAppAction` (`type: ActionType` `url`/`deeplink`, `value`), the `NottiFacade` methods, a `NottiListenerHub<NottiInAppClick>` attached to the engine's click handler (returning whether a listener exists), the allowlist entry for the two value types in `scripts/check-public-surface.sh`, and the regenerated `PUBLIC_SURFACE.txt`.
**Where**: `Sources/NottiSDK/Public/NottiInAppMessages.swift`, `Sources/NottiSDK/Facade/NottiFacade.swift` (extension in `NottiFacade+InApp.swift`), `scripts/check-public-surface.sh`, `.specs/codebase/PUBLIC_SURFACE.txt`, `Tests/NottiSDKTests/NottiInAppPublicApiTests.swift`
**Depends on**: T10
**Reuses**: `NottiListenerHub`, `NottiFacade.setSharedForTesting`, `check-public-surface.sh --update`
**Requirement**: IAM-08, IAM-11 (no-op before initialize, blank no-op), IAM-24, IAM-25 (delivery), IAM-44

**Done when**:

- [ ] `Notti.trackEvent("fixture_event")` reaches the engine through an isolated facade; an empty or whitespace-only string is a silent no-op (no log line at any level); before `Notti.initialize` the call is a no-op and no log line contains the name
- [ ] A listener receives `NottiInAppClick` on the main thread with `messageId`, `buttonId`, `action.type` and the untouched `value`; a `push_permission` click arrives with `action == nil`; two listeners both receive it in order; `remove()` stops delivery; with no listener nothing crashes and the engine is told no listener received it
- [ ] The public declarations are in `PUBLIC_SURFACE.txt`; `scripts/check-public-surface.sh` passes; `NottiInAppClick` and `NottiInAppAction` need no availability attribute (allowlisted), every other new public type has it
- [ ] `scripts/check-no-url-open.sh` passes
- [ ] Gate check passes: quick plus `scripts/check-public-surface.sh` and `scripts/check-no-url-open.sh`
- [ ] Test count: at least 9 new, total at least B + 179

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): trackEvent and the click listener`

---

### T12: Objective-C mirror

**What**: `NottiObjC.trackEvent(_:)` (`@objc(trackEvent:)`) and `NottiInAppMessagesObjC` (`@objc(NottiInAppMessages)`) with `addClickListener:` delivering an `NSDictionary` with exactly `messageId`, `buttonId` and `action` (`{type, value}` or `NSNull`, never absent, RN `InAppClick.payload`); ObjC compile check and smoke test; surface file regenerated.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `.specs/codebase/PUBLIC_SURFACE.txt`
**Depends on**: T11
**Reuses**: the `objcDictionary` pattern (`NottiObjC.swift:190-199`)
**Requirement**: IAM-24 (ObjC payload), IAM-44

**Done when**:

- [ ] The Objective-C test calls `[Notti trackEvent:]` and `[NottiInAppMessages addClickListener:]` and compiles only with these selector names
- [ ] The bridge test checks that the dictionary has exactly three keys, that `action` is `@{type, value}` for a link and `NSNull` for a nil action
- [ ] `scripts/check-public-surface.sh` passes
- [ ] Gate check passes: **full**
- [ ] Test count: at least 4 new, total at least B + 183

**Tests**: unit (Swift bridge) + ObjC compile check
**Gate**: full
**Commit**: `feat(inapp): Objective-C mirror of the in-app API`

---

### T13: Accessibility label table

**What**: `NottiInAppStrings.closeLabel(languages:)`: an in-code table, `Close`, and `Fechar` for a first preferred language whose primary subtag (split on `-` or `_`, lowercased) is `pt`; any other language or an empty list gives `Close` (RN `NottiInAppViews.swift:546-560`). No other SDK string. No `.strings`, no lproj, no `defaultLocalization`, no `resource_bundles`, no change to `Package.swift` or the podspecs (design D11).
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppStrings.swift`, `Tests/NottiSDKTests/NottiInAppStringsTests.swift`
**Depends on**: None
**Reuses**: nothing
**Requirement**: IAM-38 (label)

**Done when**:

- [ ] `en` gives `Close`; `pt-BR`, `pt-PT`, `pt_BR` and `pt` give `Fechar`; `fr`, `es` and an empty list give `Close`
- [ ] The labels are asserted as literals; the file has no `NSLocalizedString`, `Bundle`, `LocalizedStringKey` (grep test)
- [ ] `Package.swift` and both podspecs are unchanged by this task
- [ ] Gate check passes: quick
- [ ] Test count: at least 4 new, total at least B + 187

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): in-code accessibility label`

---

### T14: Message view base, appearance and layout metrics

**What**: `NottiInAppLayout` (pure bounds, port of RN `computeFrame` and `InAppMetrics`), `NottiInAppAppearance` (RN `resolveStyle`; fonts `headline`, `subheadline`, bold `subheadline`), and the part of `NottiInAppMessageView` shared by all layouts: title and body labels (plain text, absolute alignment, hidden when blank), the scrolling content region, the button row (side by side or stacked, measured), the move of the buttons into the scroll view when they exceed the card's room, the 44 pt close control at the 8 pt inset with its scrim chip over an image, the optional image, accessibility identifiers, traits and labels, Dynamic Type.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppMessageView.swift` (with `NottiInAppLayout.swift`, `NottiInAppAppearance.swift`), `Tests/NottiSDKTests/NottiInAppMessageViewTests.swift`
**Depends on**: T2, T13
**Reuses**: `NottiInAppStyle`, the label table
**Requirement**: IAM-14, IAM-15 (buttons), IAM-17, IAM-20, IAM-21, IAM-22, IAM-23, IAM-38 (element side), IAM-39

**Done when**:

- [ ] Title `**bold** <b>x</b> [l](https://example.invalid)` and a body with newlines are displayed verbatim: the labels' `text` equals the input and `attributedText` carries no link, bold or paragraph attribute from markup; a blank title label is hidden
- [ ] Valid tokens color the background, text, close tint, button background and label; an invalid token falls back to its default; with `button_color` set both buttons are filled with it; without tokens the first button is filled and the second tinted; fonts are `headline` (title), `subheadline` (body) and bold `subheadline` (buttons)
- [ ] `text_align: right` gives `.right` and `left` gives `.left` with `semanticContentAttribute = .forceRightToLeft` (absolute, never `.natural`)
- [ ] The close control is 44 x 44, its frame is 8 pt from the card's top and trailing edges (top-leading under right-to-left), it is not inside the scroll view, and with an image on `center` its glyph is white on a black 40% capsule
- [ ] Two short labels sit side by side; a label longer than half the width stacks both; each button is at least 44 pt tall
- [ ] A 500-character body at the largest accessibility content size gives a scroll content size larger than its viewport and the close control and buttons remain visible; two buttons taller than the card's room move into the scroll view after the text (`buttonsScroll`), and back out when the room grows
- [ ] The title has the `.header` trait and is a separate element from the body; buttons have the `.button` trait and their label; the image is not an element unless tappable, then it is `[.button, .image]` labeled with the title (nil for a blank title)
- [ ] A grep test over `Sources/NottiSDK/InApp/UI` finds none of `attributedText`, `AttributedString`, `WKWebView`, `LocalizedStringKey`, `openURL`
- [ ] Gate check passes: quick
- [ ] Test count: at least 15 new, total at least B + 202

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): message view with plain text, style and accessibility`

---

### T15: `top` and `bottom` layouts

**What**: The bar layouts: placement under or above the safe area with the `margin` inset measured from the safe-area edge, height capped at min(40% of the container, safe height minus the margins), the 56 pt leading thumbnail, the pan swipe (begins only when mostly vertical, in the dismiss direction, and the text cannot scroll that way; follows the finger; dismisses at min(card height / 3, 44 pt); snaps back otherwise), the body tap recognizer (bars with buttons only, excluding the close control, buttons and a tappable image; acts as the first button), all with handlers callable by tests (RN `NottiInAppViews.swift:415-529`).
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppBarLayout.swift`, `Tests/NottiSDKTests/NottiInAppBarLayoutTests.swift`
**Depends on**: T14
**Reuses**: `NottiInAppLayout`
**Requirement**: IAM-13 (top, bottom), IAM-15 (thumbnail), IAM-18, IAM-19, IAM-21 (margin)

**Done when**:

- [ ] At 390 x 844 and 844 x 390 with notch insets: `top` sits at the safe area top, `bottom` at the safe area bottom, heights at most min(40% of the window, safe height minus 32) with a 500-character body; with `margin: true` or absent the bar is 16 pt from the safe-area edge (top or bottom, leading and trailing); with `margin: false` its frame touches the safe-area edges on those sides
- [ ] In landscape with left and right safe-area insets (for example 59 pt): the leading and trailing edges are at the insets plus 16 (`margin: true`) or at the insets exactly (`margin: false`)
- [ ] The thumbnail is 56 x 56 at the leading edge (trailing under right-to-left)
- [ ] `top` dismisses with `swipe` on a pan ending at -44 pt for a 300 pt card and at -20 pt for a 60 pt card (one third), snaps back at -43 pt for the 300 pt card, and ignores a downward pan; `bottom` the mirror; a pan does not begin while the text can still scroll in that direction; the close control yields `close_button`
- [ ] A body tap yields the first button's id and action; with no buttons there is no body recognizer; a tap on a button or the close control does not also fire the body tap
- [ ] Re-layout (rotation sizes in sequence) leaves one view hierarchy and the view never reports an impression
- [ ] Gate check passes: quick
- [ ] Test count: at least 13 new, total at least B + 215

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): top and bottom bar layouts`

---

### T16: `center` and `full` layouts

**What**: `center`: backdrop at 50% black, card centered in the safe area with width min(90% of the container, 560 pt, safe width) and height capped at 90% of the safe height, outside-tap recognizer that ignores taps inside the card, `margin` ignored, image filling the width above the text (aspect fill, 180 pt cap). `full`: inside the safe areas with the `margin` inset, image aspect-fit taking the free height the text leaves, buttons pinned to the bottom, no dismiss gesture, corner radius 0 with `margin: false`.
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppCardLayout.swift`, `Tests/NottiSDKTests/NottiInAppCardLayoutTests.swift`
**Depends on**: T14
**Reuses**: `NottiInAppLayout`
**Requirement**: IAM-13 (center, full), IAM-15 (image), IAM-17, IAM-18, IAM-21 (margin)

**Done when**:

- [ ] `center`: the card width is 351 pt at 390 pt wide (90%), 560 pt on a 1024 x 1366 iPad, and never wider than the safe width in landscape; it is centered in the safe area with asymmetric insets; its height never exceeds 90% of the safe height with a 500-character body; the backdrop is 0.5 black; `margin: false` changes nothing; the outside-tap handler yields `outside_tap` and a tap inside the card yields nothing
- [ ] `center` image: a 2:1 image is `inner width` wide and `inner / 2` tall with `.scaleAspectFill`; a 1:2 image is capped at 180 pt
- [ ] `full`: the frame equals the safe area inset by 16 (`margin: true` or absent) or 0 (`margin: false`), also in landscape; with a short text the image is `.scaleAspectFit` and taller than its natural height (it takes the free room); buttons are at the bottom of the card while a long body scrolls; no swipe and no backdrop recognizer exists
- [ ] The close control is present and 44 pt in both, also with a 500-character body at the largest Dynamic Type
- [ ] Gate check passes: quick
- [ ] Test count: at least 14 new, total at least B + 229

**Tests**: unit
**Gate**: quick
**Commit**: `feat(inapp): center and full layouts`

---

### T17: Presenter, window and scene handling

**What**: `NottiInAppWindow` (level `.alert` like RN, `canBecomeKey == false`, pass-through `hitTest`), `NottiInAppViewController` (clear container, follows the host key window's root view controller for orientations and status bar, animations, Reduce Motion, accessibility notifications), the overlay's `accessibilityPerformEscape()` override, `NottiInAppPresenter` implementing `NottiInAppPresenting` with an injected scene provider, image wait (3 s, `maxSidePx` = screen long side times scale), scene and app lifecycle observation (`didBecomeActive`, `UIScene.didActivateNotification`, `UIScene.didDisconnectNotification`), re-attach without a new impression, `becameVisible` after a layout pass while active, the legacy no-scene fallback, and production wiring in `NottiRuntime` replacing the T10 placeholder (RN `NottiInAppPresenter.swift`).
**Where**: `Sources/NottiSDK/InApp/UI/NottiInAppPresenter.swift` (with `NottiInAppWindow.swift`, `NottiInAppViewController.swift`), `Tests/NottiSDKTests/NottiInAppPresenterTests.swift`
**Depends on**: T9, T10, T15, T16
**Reuses**: the layouts, the engine's presenter protocol, the image loader
**Requirement**: IAM-18, IAM-36, IAM-37, IAM-38, IAM-39, IAM-40 (`maxSidePx`)

**Done when**:

- [ ] The window is not the key window and cannot become key; `windowLevel` is `.alert`; for a bar the `hitTest` outside the bar returns nil and inside returns the bar; for `center` and `full` the backdrop returns a view
- [ ] The root view controller reports the host root view controller's `supportedInterfaceOrientations` and status bar values (a portrait-only host gives `.portrait`)
- [ ] `accessibilityViewIsModal` is true for `center` and `full`, false for bars; `.screenChanged` with the title (the card when the title is hidden) or `.announcement` with "title. body" is posted once per display (injected poster)
- [ ] `accessibilityPerformEscape()` on a `center` and on a `full` presentation returns true and reports one `dismiss` with `close_button` (none when already closing); on a `top` and on a `bottom` presentation it returns false and reports nothing
- [ ] With Reduce Motion on, entrance and exit use the cross-fade path and the swipe snap-back is not animated; the dismissal still completes
- [ ] The image is requested with `maxSidePx` equal to the screen's long side times its scale (injected screen); with no image in 3 s the message presents without it and a late image is ignored
- [ ] A fake scene provider that loses and regains a scene keeps the same display id, creates no `impression` and no `dismiss`, and reports `displayAttached` both ways; a provider with no scenes in an active app uses the screen-sized fallback window; with nothing active the display waits for `didBecomeActive`
- [ ] The presenter reports `becameVisible` exactly once per display, only after a layout pass while the app is active
- [ ] The production `NottiRuntime` uses the real presenter; no other test touches `UIApplication.shared`
- [ ] Gate check passes: **full**
- [ ] Test count: at least 15 new, total at least B + 244

**Tests**: unit
**Gate**: full
**Commit**: `feat(inapp): present messages in a dedicated window`

---

### T18: Privacy sweep and guards

**What**: One test class with sentinels in token, device id, message id, title, body, button labels, image and action URLs and event name run through every path (fetch ok, each error status including 401 and 408, queue flush, tap, dismiss, `push_permission` tap in every state, image failure, no listener, `trackEvent` before `initialize` and blank) asserting no captured `NottiLogger` line contains any of them; source greps for the banned strings (rule 3) outside the allowlisted file; `PrivacyInfo.xcprivacy` comment extended for In-App events (keys unchanged); re-check of required-reason APIs in the new code.
**Where**: `Tests/NottiSDKTests/NottiInAppPrivacyTests.swift`, `Sources/NottiSDK/Resources/PrivacyInfo.xcprivacy` (comment only)
**Depends on**: T11, T17, T22
**Reuses**: `LogSink`, `NottiLoggingPrivacyTests` patterns
**Requirement**: IAM-23, IAM-24, IAM-43, IAM-45, IAM-46

**Done when**:

- [ ] Every sentinel is absent from every captured line on every listed path (each path is its own test method)
- [ ] On the `401` path (eligible and events) no captured line contains the registration text of the `403` warning, and the `trackEvent` name never appears in a line when it is ignored
- [ ] The source grep tests fail on a temporary mutant containing each banned string in a non-allowlisted file (noted in the commit body)
- [ ] `PrivacyManifestTests` pass unchanged; the manifest diff is the comment only
- [ ] `scripts/check-no-url-open.sh`, `check-extension-safety.sh`, `check-package-graph.sh`, `check-public-surface.sh` pass
- [ ] Gate check passes: **full**
- [ ] Test count: at least 10 new, total at least B + 254

**Tests**: unit
**Gate**: full
**Commit**: `test(inapp): privacy sentinel sweep and source guards`

---

### T19: Example app

**What**: Edit the existing Example app (`example-and-release`): a button "Track event" that calls `Notti.trackEvent("example_event")` and a click listener registered at launch that logs only the action type (`url`, `deeplink` or `none`, never the value) to the on-screen log; a hosted test that the button and the listener are wired.
**Where**: `Example/App/ExampleApp.swift`, `Example/Tests/InAppExampleTests.swift`
**Depends on**: T12, T17
**Reuses**: the `example-and-release` structure and hosted tests (`ExampleSDKClient`, `ExampleLog`)
**Requirement**: IAM-47

**Done when**:

- [ ] The example builds for the simulator and device with the strict flags and the hosted test passes; `check-example-coverage.sh` and `check-example-config.sh` pass
- [ ] The sample config in `Example/Config/Example.xcconfig.sample` is unchanged (no real keys)
- [ ] Gate check passes: Example build and hosted tests plus quick
- [ ] Test count: at least 2 new hosted tests (not counted in the SDK total)

**Tests**: unit (hosted)
**Gate**: quick
**Commit**: `feat(example): track an event and handle in-app clicks`

---

### T20: Docs, release notes, traceability and status

**What**: README section (what In-App does, minimum `zeep-notti` v0.23.0, `trackEvent`, the click listener with `action` nullable and the sentence that without it no link opens, the `push_permission` button and its settings jump, Dynamic Type and accessibility notes, a data collection line, `notti_pending_inapp_events` in the storage keys table); `CHANGELOG.md` `[0.1.0]`: first line becomes a native port of `react-native-notti` 0.8.0 with In-App Messages (was 0.6.0), the feature, the `403` divergence line, the `push_permission` settings exception, and the migration note's key list gains `notti_pending_inapp_events` (RN's key, so pending events carry over); `example-and-release/release-pr.md`: the In-App device checklist (this file, T21) as a pre-tag gate; `TESTING.md` (new layers and counts); `ROADMAP.md` status; `traceability.md` for IAM-01..52; spec statuses.
**Where**: `.specs/features/in-app-messages/traceability.md`, `README.md`, `CHANGELOG.md`, `.specs/features/example-and-release/release-pr.md`, `.specs/codebase/TESTING.md`, `.specs/project/ROADMAP.md`, `.specs/features/in-app-messages/spec.md`
**Depends on**: T18, T19
**Reuses**: `nse-rich-media/traceability.md` as the template
**Requirement**: IAM-47 and the mapping of all requirements

**Done when**:

- [ ] Every IAM-xx has at least one named test or check in `traceability.md`; the total matches the real count
- [ ] `CHANGELOG.md` `[0.1.0]` names RN 0.8.0, contains the 403 divergence line, the `push_permission` exception and the new storage key; `scripts/check-version.sh` (CHANGELOG check) passes
- [ ] `release-pr.md` lists the In-App device checklist gate
- [ ] `check-readme-snippets.sh` passes with the new README snippets
- [ ] `validate_spec.py` and `validate_tasks.py` pass; `AGENTS.md` layout line mentions `Sources/NottiSDK/InApp/`
- [ ] Gate check passes: **full**
- [ ] Test count at least the baseline plus the minimums above, none removed

**Tests**: none
**Gate**: full
**Commit**: `docs(specs): in-app-messages traceability, release notes and status`

---

### T21: Device validation and Verifier

**What**: Run the device checklist below on a real iPhone and an iPad against a real or staging `zeep-notti` (v0.23.0 or later) with a message per layout, record pass, fail or not run per line in `validation.md`, then the independent Verifier (`tlc-spec-driven` Validate: author is not verifier, evidence or zero, mutants listed in the design).
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
3. Rotation of an open message in each layout (portrait, landscape left and right): no second impression, bounds respected, close control reachable; a portrait-only host app keeps the message in portrait.
4. `top`: swipe up reports `swipe` (a short drag snaps back); touch outside the bar reaches the app; a long body scrolls before a swipe starts; the status bar and the Dynamic Island are not covered; with `margin: true` the bar is 16 pt below the safe-area top and 16 pt from the sides, with `margin: false` it touches the safe-area top and sides.
5. `bottom`: swipe down reports `swipe`; with the keyboard open in the host, record whether the bar is above or below it and whether it is tappable (window level, [Incerto]); note any difference from an RN 0.8.0 app (RN uses `.alert`).
6. `center`: backdrop tap reports `outside_tap`; tap inside the card does nothing; VoiceOver focus moves to the title and cannot reach the app behind; on an iPad the card is at most 560 pt wide.
7. `full`: only the close control dismisses; buttons stay pinned with the largest Dynamic Type; text scrolls; an image with short text grows into the free space, uncropped.
8. Two buttons: side by side on an iPhone, stacked at a large Dynamic Type or an iPhone SE width; in landscape at an accessibility size the buttons scroll with the text and stay tappable; first button primary style, second secondary; with `button_color` both identical.
9. A button with a `deeplink` and one with an `https` URL: the Example listener receives the action, the SDK opens nothing, the display closes, `click` is in the dashboard with the right button, no `dismiss`.
10. Image: with `image_action`, tap reports `click` `image`; the close control over the image is a white glyph on a dark chip; an unreachable image host shows the message without the image after about 3 s; a 6 MiB image is not shown; a portrait phone photo with EXIF rotation shows upright.
11. Auto dismiss 8 s: closes at about 8 s with `auto`; after a 5 s background the remaining time resumes; a manual close at 2 s reports `close_button`.
12. `trackEvent`: with an event-triggered message, the exact name shows it; a different case does not; two calls show the second message only on the second call; an early call before the fetch completes shows the message on arrival; a call before `Notti.initialize`, a blank name, and a call while the app is in the background after a session ran show nothing and log nothing.
13. Offline: put the device in airplane mode, tap and dismiss, restore: queued events arrive in order with the original `occurred_at`; no duplicates in the dashboard after a forced retry; a session started offline fetches once the network returns.
14. `429` (staging with a lowered limit) and `5xx` (proxy): the SDK waits, the app stays responsive, login and tags are not delayed; `eligible` `429` with `Retry-After` over 60 s shows no message that session and sends no second request; a background and foreground inside a short pause does not fetch before it ends; `401` (a wrong client key) logs no registration text.
15. VoiceOver reading order (title as a heading, then body, then buttons), close label in English and in Portuguese (`pt-BR` and `pt-PT`), the tappable image read with the message title, the escape gesture (two-finger Z) closing a `center` and a `full` message with `close_button` and doing nothing on `top` and `bottom`, Reduce Motion cross-fade, dark mode default colors, server colors unchanged in dark mode, `text_align: right` in an Arabic or Hebrew device language stays right.
16. A non-scene (legacy) app and an iPad with two windows (Split View, Stage Manager): the message appears on one scene; moving the app between scenes does not duplicate impressions.
17. Markdown and HTML in `title` and `body` of a test message are shown verbatim.
18. CocoaPods consumers (static, static libraries, dynamic): the close control label resolves and the message shows.
19. Launch ordering of the `trackEvent` cold-start window ([Provável]): call `Notti.initialize` and `Notti.trackEvent("fixture_event")` back to back (a) in `application(_:didFinishLaunchingWithOptions:)` and (b) in a SwiftUI `App` `init`, on a cold start with an event-triggered message for that name; record whether the message appears once the first session opens and `eligible` answers, whether `UIApplication.applicationState` was `.inactive` at the call, and the order of `trackEvent`, the `tryOpen()` edge and `didBecomeActive` (breakpoints or a temporary print in the host app, never a log line in the SDK). Also a launch in the background (silent push) followed by a foreground: the name is kept until the first foreground session.
20. Margin on a notch iPhone, portrait and landscape: `margin: true` insets 16 pt from the safe-area edge on `top`, `bottom` and `full`; `margin: false` touches the safe-area edges without going under the notch or Dynamic Island, the status bar or the home indicator; `center` is unchanged by `margin`.
21. `push_permission` (needs a server that serves it: a staging build with `MinSDKVersionPushPermission` set, AD-019 decision 4): fresh install, tap → the system prompt appears and the subscribed state reaches the server after "Allow"; with permission denied, tap → the app's notification settings page opens (iOS 16+) or the app settings page (iOS 15); with permission granted, tap → nothing beyond the close; in every case `click` is in the dashboard and the Example listener logs `none`.
22. Foreground session while the core is busy: block registration with a proxy that delays `PUT /devices` long enough for the core to retry, background and foreground the app: the In-App session opens and `eligible` is called at foreground, not after the core's retries end.
23. RN-to-native continuity: an app on `react-native-notti` 0.8.0 with queued In-App events (airplane mode, tap a message), replaced by a build on this SDK with the same bundle id: the queued events are sent with their original `event_id` once online.

---

## Requirement Coverage

| Requirement | Tasks |
| --- | --- |
| IAM-01 | T7, T10 |
| IAM-02 | T5 |
| IAM-03 | T7 |
| IAM-04 | T5, T7 |
| IAM-05 | T1 |
| IAM-06 | T7, T9, T10 |
| IAM-07 | T3, T7 |
| IAM-08 | T3, T7, T11 |
| IAM-09 | T3, T9 |
| IAM-10 | T7 |
| IAM-11 | T3, T7, T10, T11 |
| IAM-12 | T3, T9 |
| IAM-13 | T15, T16 |
| IAM-14 | T14 |
| IAM-15 | T14, T15, T16 |
| IAM-16 | T1 |
| IAM-17 | T14, T16 |
| IAM-18 | T15, T16, T17 |
| IAM-19 | T9, T15 |
| IAM-20 | T2, T14 |
| IAM-21 | T2, T14, T15, T16 |
| IAM-22 | T2, T14 |
| IAM-23 | T14, T18 |
| IAM-24 | T11, T12, T18 |
| IAM-25 | T9, T11 |
| IAM-26 | T9 |
| IAM-27 | T9 |
| IAM-28 | T9 |
| IAM-29 | T4, T5, T9 |
| IAM-30 | T4, T6, T7, T9 |
| IAM-31 | T5, T6, T7 |
| IAM-32 | T6 |
| IAM-33 | T7, T10 |
| IAM-34 | T9 |
| IAM-35 | T9 |
| IAM-36 | T17 |
| IAM-37 | T17 |
| IAM-38 | T13, T14, T17 |
| IAM-39 | T14, T17 |
| IAM-40 | T8, T17 |
| IAM-41 | T8, T9 |
| IAM-42 | T8 |
| IAM-43 | T18 |
| IAM-44 | T11, T12 |
| IAM-45 | T18, T22 |
| IAM-46 | T18 |
| IAM-47 | T19, T20 |
| IAM-48 | T21 |
| IAM-49 | T1, T9, T22 |
| IAM-50 | T22 |
| IAM-51 | T7, T10 |
| IAM-52 | T7 |

52 requirements, 52 mapped to tasks.
