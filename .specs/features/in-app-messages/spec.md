# In-App Messages Specification

## Problem Statement

`zeep-notti` can author In-App messages (four layouts, style tokens, tappable image, auto dismiss, event triggers) and serves them to devices, but `NottiSDK` cannot show them: it has no fetch, no UI and no event reporting for the route. The server side is implemented and its device contract is frozen in `zeep-notti/docs/content/sdks/in-app-messages.mdx` (the contract page, source of truth) with the decisions of `zeep-notti/.specs/features/in-app-rich-messages/` (IARM-01..10, approved by the owner on 2026-10-18). The contract is server-driven and render-on-client: the server decides eligibility (audience, platform, schedule, frequency) and counts the events; the SDK fetches once per session, renders natively, and reports `impression`, `click` and `dismiss` reliably, because a lost impression makes a `once` message eligible again.

This is a **new feature, after M1**. `PROJECT.md` lists In-App Messages as out of scope for v1 and AD-002 makes M1 a port of RN 0.6.0, so this feature does not belong to M1 or `0.1.0` (`ROADMAP.md`: M3, "Future Considerations" until now). It needs the AD-001 spec first (this document), and it requires: M1 tagged `0.1.0` (`example-and-release` done, because the `Example/` app is updated here), and a `zeep-notti` release that contains IARM (the contract is implemented on `main` of `zeep-notti` since 2026-10-18; the release number is an open item, OQ-6).

Constraint from the contract that shapes the design: the SDK must **not** keep its own "already shown" state (the server is the authority), must report impressions reliably (persistent queue), and must never open a link: `scripts/check-no-url-open.sh` bans `UIApplication.shared.open` in `Sources/NottiSDK` (DEL-18). A link action therefore leaves the SDK as data, delivered to the host through a listener (IAM-24).

`zeep-notti-react-native` has no In-App spec yet (another agent is writing it at the same time). The points that must be checked between the two specs are listed in `design.md` ("Parity checklist with the React Native spec").

## Goals

- [ ] One `POST .../in-app-messages/eligible` per foreground session, after the device registered, never per screen, with the Client key and the device's `device_id` + push token.
- [ ] The first renderable `session_start` message appears right away; `event` messages are held in memory and appear on `Notti.trackEvent(name)` by exact local match; at most one message is visible; each message shows at most once per session.
- [ ] The four layouts (`top`, `center`, `bottom`, `full`) render natively inside the contract bounds, with the dismiss gestures of the table and a close control that is always visible.
- [ ] `title` and `body` are always plain text; style tokens are applied with safe fallbacks; an unparsable color never fails.
- [ ] `impression` is reported exactly once per display and always before `click` or `dismiss`; every event has a client-generated `event_id` that survives retries and restarts.
- [ ] A link action (`url` or `deeplink`) reaches the host app through a public listener; the SDK never opens it.
- [ ] No token, device id, title, body, URL or event name in any log line; the privacy manifest stays accurate; nothing of this reaches `NottiShared` or `NottiSDKExtension`.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Opening links inside the SDK | `check-no-url-open.sh` (DEL-18). The host decides what a link means. The SDK delivers the action (IAM-24) |
| Evaluating targeting (segment, platform, schedule, frequency) on the device | The contract: the server is the authority and the payload carries no targeting |
| A persistent "already shown" store, or any client-side frequency cap | The contract forbids it. The only persisted In-App state is the event queue |
| Sending event names to the server, or any key-value trigger conditions | The contract: names are matched locally and discarded at session end |
| HTML, Markdown or web-view content; custom fonts and sizes; carousel; per-locale content; test send | Out of scope of the contract (IARM Out of Scope) |
| SwiftUI view API (`.notti...` modifier), or a host-provided view for the message | Rendering is SDK-owned. A host view hook is a later feature |
| Display lifecycle callbacks (`willDisplay`, `didDismiss`) | Not in the contract. The only host-facing callback here is the click/action listener |
| Reusing `NottiEventStore` (CTR queue) for In-App events | Decided in design (D2): different schema, key, TTL and ordering needs; the CTR key must stay byte-compatible with RN 0.6.0 |
| Changing `NottiApiClient`'s retry policy or adding `Retry-After` to the existing routes | `queue-resilience` (M3) owns that. In-App gets its own non-blocking client |
| macOS / Mac Catalyst, visionOS, app extensions | App-only, iOS 15+. All UI is `@available(iOSApplicationExtension, unavailable)` |
| Running the real UI in a Notification Service Extension | An NSE has no UI |
| Android, Flutter | Separate repos |
| Unit tests for pixel-exact rendering across devices | The contract gives bounds, not pixels. Layout is tested by hierarchy and frame bounds, and proved by the device checklist |

---

## Assumptions & Open Questions

Legend: `y` confirmed, `n` proposed here and waiting for Julio. Evidence tags: [Certo] verified in code or contract, [Provável] reasonable inference, [Incerto] needs validation.

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Server contract | `in-app-messages.mdx` is normative: routes, bodies, error table, limits (eligible 30/min, events 120/min per device), layouts table, triggers, style, auto dismiss, plain text rule, additive-only evolution | Frozen by IARM, approved 2026-10-18 [Certo] | y (Julio, 2026-10-18) |
| Contract defaults | `text_align` absent = `left`; `margin` absent = `true` (16 pt inset on `top`, `bottom`, `full`; `center` ignores it); a button color token applies to every button; `style: null` = SDK defaults; unknown `format` = `center`; unknown fields ignored | Approved by the owner on 2026-10-18 | y (Julio, 2026-10-18) |
| What "session" means | The SDK's existing foreground session: the transition that wins `NottiCore.SessionGate.tryOpen()` in `handleAppDidBecomeActive` (cold start, or background to foreground). A repeat `didBecomeActive` (Control Center, permission alert, app switcher peek) and a core replacement that adopts the open session do not start one. It ends at `didEnterBackground` (`NottiCore.swift:983-1048`) | The contract says "session start"; the SDK already defines it for telemetry [Certo, code]. Reusing it keeps one definition | n (OQ-3) |
| "Device registered" | The registration of **this process** succeeded (`registerDevice` `.success`, `NottiCore.swift:697-722`), so the persisted `notti_device_id` and `notti_last_token` are the ones the server just accepted | A device id persisted from an earlier launch with a rotated token would answer `403`. Registration runs on every launch [Certo, code] | y (derived from the contract: "holds a `device_id`") |
| Where the engine lives | A process-level `NottiInAppEngine` owned by `NottiRuntime`, own serial queue `app.notti.sdk.inapp`, never `NottiCore.workQueue` and never the main thread | `NottiApiClient` blocks `workQueue` for minutes (retry + backoff, `NottiCore.swift:25-39`); an eligible fetch there would stall login and tags. Same ownership model as `sessionGate` and `eventBuffer` (`NottiRuntime.swift:29-31`) | y (design D1) |
| UI technology | UIKit (a dedicated `UIWindow` per display), not SwiftUI | Plain-text-by-construction (`UILabel.text`), no `openURL`/`Link` (the grep guard bans `openURL` text), hierarchy inspectable without third-party snapshot tools, pass-through hit testing for the bars, `accessibilityViewIsModal`, safe areas by layout guides on iOS 15 | y (design D3, AD-013) |
| Link action delivery | `Notti.InAppMessages.addClickListener { NottiInAppClick }` (and the `@objc` mirror). The click carries `messageId`, `buttonId` and the action (`url` or `deeplink`, `value` untouched). It is analogous to `addClickedListener` for a tapped push | The SDK never opens a URL; a listener is the existing idiom (`NottiListenerHub`, main-thread delivery) and needs no new host protocol | y (Julio, 2026-10-18, OQ-1: the integrator handles `url` and `deeplink`) |
| `click` reporting when the host does not handle the link | The SDK **always** reports `click` for a tap, even with no listener registered or a listener that ignores it. The metric is "the user tapped", not "a link opened" (the SDK cannot know the latter) | Matches the contract: a button tap sends `click`. Opening is the host's business | y (Julio, 2026-10-18, OQ-1: the integrator handles `url` and `deeplink`) |
| Which taps close the message | Every button tap, image tap and body tap that has an action closes the display after the listener ran; the close reports only `click` (no `dismiss`) | Contract: "When a click closes the message, report the click". Closing first would cover the host's navigation | y (Julio, 2026-10-18, OQ-1: the integrator handles `url` and `deeplink`) |
| `trackEvent` placement and name | `Notti.trackEvent(_ name: String)` (top level, not under `InAppMessages`); ObjC `+[Notti trackEvent:]`. The contract calls it `trackEvent(name)`; a generic name leaves room for non-In-App uses | Contract wording; RN has to expose the same name | n (OQ-7) |
| `trackEvent` before the fetch has completed | Event names reported earlier **in the same session** are remembered in memory (distinct names, at most 32, oldest dropped) and matched once when the held messages arrive. No replay across sessions, none after a message is shown | Without it, `trackEvent("home_viewed")` at launch races the network and the message is lost whenever the app is faster than the fetch. Matches the contract's intent (the event happened this session) but is a client nuance the contract does not state | y (Julio, 2026-10-18, OQ-2; limit 32 aligned with RN) |
| Other `session_start` messages beyond the first | Not shown this session (neither queued nor re-fetched). They stay eligible for the next session | Contract: "Show the **first** session-start message the SDK can render". A launch-time queue of cards is a worse experience; the server frequency rules still apply next time | n (OQ-4) |
| An event fires while a message is visible | The event is ignored (not queued, not replayed after the close) | Contract: show "only when no message is visible". Queueing would show stale messages later | y (contract), replay rule n |
| A message is visible when the session ends | The display survives the background (the auto-dismiss timer pauses, contract) and stays one visible message. The next session's fetch skips that message id; its `session_start` candidates are dropped for that session; `event` candidates are held normally | The contract pauses the timer in the background, so the display is expected to survive it. Dropping instead of queueing keeps the state machine small | n (OQ-9) |
| Defaults for colors and typography | Semantic system colors (adapt to dark mode): background `secondarySystemBackground`, text `label`; first button filled (`systemBlue` / `white`), second button tinted (`tertiarySystemFill` / `label`); with any button token set, all buttons share one style. Fonts: `headline` for the title, `body` for the text | The contract says "SDK default" without values. Server-authored colors are fixed and have no dark variant [Certo]. Final palette needs the owner and RN | y (Julio, 2026-10-18, OQ-5) |
| Image wait | The message is presented after the image loads or after 3 s; on timeout it is shown without the image (and without `image_action`, which cannot be tapped), and a late image is dropped | Avoids layout jumps and an indefinitely delayed message; "image failure never blocks the message" | y (Julio, 2026-10-18: 3 s and 5 MiB kept; RN aligns to 5 MiB) |
| In-App event queue | New, separate: `UserDefaults` key `notti_inapp_pending_events` in the `notti_prefs` suite, cap 100 (oldest dropped), drop at 7 days of age, FIFO with stop-on-transient-failure | The CTR queue has a fixed schema, a 32 cap, no TTL, and its key is part of the RN continuity contract (`NottiEventStore.swift:66-76`). Impression must precede click, so skip-ahead is not allowed | y (design D2) |
| Client retry constants | Eligible and events: 5 attempts, backoff 2/4/8/16 s (same numbers as `NottiApiClient`, `NottiApiClient.swift:62-63`), non-blocking. `429`: wait `Retry-After` (clamped to 1...300 s, 60 s when absent or invalid), up to 3 waits per operation | The contract says "wait for Retry-After and retry with the same `event_id`". The clamp and the count are proposals | y (Julio, 2026-10-18; the constants are tunable, kept in one place, and may be adjusted) |
| `403` on either route | No retry. Eligible: stop for this session. Events: stop the flush and keep the queue (a later registration can fix the token pair). The SDK does not trigger a re-registration itself | The contract: "Re-register the device, do not retry as is". Registration already runs on every launch and on foreground retry. Forcing it here risks a loop | y (Julio, 2026-10-18) |
| Privacy manifest | `PrivacyInfo.xcprivacy` keys unchanged; only the comment mentioning Product Interaction is extended. No required-reason API is added: wall-clock `Date` for the timer (not `ProcessInfo.systemUptime`, `mach_absolute_time` or file timestamps), `UserDefaults` is already declared (CA92.1), the image cache is in memory | AD-005; PKG-13. In-App events are Product Interaction linked to the device, already declared [Certo, manifest]. To re-check in the task that adds the code | y (verify in T18) |

**Open questions** (each has a recommendation; none blocks writing Design and Tasks, but OQ-7 changes public API and must be answered before the public-API task):

- **OQ-1 Link mechanism and click rule. CLOSED (Julio, 2026-10-18):** the integrator handles `url` and `deeplink`; the click listener of IAM-24, always-report-click, click closes the display without `dismiss`. With no listener registered: `click` is still reported, nothing opens, the display closes, one `.warn` (no values). README must carry a prominent warning (IAM-47). RN adopts the same listener name and payload.
- **OQ-2 `trackEvent` before the fetch completes. CLOSED (Julio, 2026-10-18):** remember the session's distinct names (limit 32, aligned with RN) and re-evaluate on arrival.
- **OQ-3 Session granularity (still open).** Every foreground transition is a session, so `eligible` runs on every resume. The server limits (30/min) and frequency rules bound the cost. Recommendation: keep the SDK's session (one definition, as the contract says). If product wants fewer fetches (for example only after N minutes in the background), that is a new rule to add to both SDKs, not a local choice.
- **OQ-4 Extra `session_start` messages (still open).** Recommendation: first only (above).
- **OQ-5 Default palette and fonts. CLOSED (Julio, 2026-10-18):** semantic system colors as in the table.
- **OQ-6 Server release.** Which `zeep-notti` release first serves the IARM payload (`format` in four values, `style`, `trigger`). [Provável] a release after v0.20.0; to confirm. An older server returns `modal` / `banner`, which this SDK renders as `center` (unknown format rule), so it degrades safely. Julio is aware (2026-10-18); stays recorded as a dependency.
- **OQ-7 `trackEvent` placement.** Recommendation: `Notti.trackEvent(_:)`. RN must use the same name.
- **OQ-8 Image wait budget. CLOSED (Julio, 2026-10-18):** 3 s then show without image; 5 MiB cap kept, RN aligns.
- **OQ-9 Visible message across sessions (still open).** Recommendation: as in the table.

---

## User Stories

### P1: Fetch once per session ⭐ MVP

**User Story**: As an integrator, I want the SDK to ask the server for eligible messages once per session, after the device is registered, so that messages appear without per-screen calls or rate-limit trouble.

**Why P1**: Nothing else works without it, and the route is rate limited per device.

**Acceptance Criteria**:

1. IAM-01: WHEN a foreground session starts (the `tryOpen()` transition) AND the registration of this process has succeeded, in either order, THEN the engine SHALL call `eligible` exactly once for that session. A repeat `didBecomeActive`, a token-refresh registration, a core replacement that adopts the open session, and `trackEvent` SHALL NOT start another call.
2. IAM-02: WHEN `eligible` is called THEN the SDK SHALL send `POST {baseUrl}/v1/apps/{appId}/in-app-messages/eligible` with `Authorization: Bearer <client key>`, `Content-Type: application/json` and a body of exactly `device_id` and `token` (the persisted device id and last push token), SHALL percent-encode the path components, and SHALL NOT send any other field.
3. IAM-03: WHEN the In-App event queue is not empty at that moment THEN the engine SHALL try to flush it first, one attempt per event with no backoff, stopping at the first failure, and SHALL then call `eligible` regardless of the flush outcome (decided, Julio 2026-10-18).
4. IAM-04: WHEN `eligible` answers `429` THEN the engine SHALL wait `Retry-After` seconds (clamped to 1...300, 60 when absent or invalid) and retry, at most 3 waits; WHEN it answers `401`, `403` or `422` THEN it SHALL NOT retry and SHALL stop for the session; WHEN it answers `5xx` or the transport fails THEN it SHALL retry with backoff 2/4/8/16 s, 5 attempts in total, then stop for the session. Every wait SHALL be non-blocking (no thread sleeps).
5. IAM-05: WHEN the response is parsed THEN unknown fields SHALL be ignored, a message that cannot be rendered SHALL be skipped without discarding the others, and an unknown `format` SHALL become `center` (see IAM-16 for what "renderable" means).
6. IAM-06: WHEN the session ends (`didEnterBackground`) before the response arrives THEN the late response SHALL be discarded; WHEN it ends after THEN the held `event` messages SHALL be discarded. The engine SHALL NOT run on `NottiCore.workQueue` or on the main thread for network or queue I/O.

**Independent Test**: A fake session and registration signal plus a stubbed `URLProtocol` count calls: two signals in either order give one call; a second session gives a second call; each status code gives its policy.

---

### P1: Choose what to show ⭐ MVP

**User Story**: As a product owner, I want the right message at the right moment, one at a time, so that the app is never covered by stacked cards.

**Why P1**: This is the selection contract; getting it wrong either spams users or loses impressions.

**Acceptance Criteria**:

1. IAM-07: WHEN the response arrives and no message is visible THEN the engine SHALL present the first renderable message with `trigger.type == "session_start"`, in server order, and SHALL NOT present any other `session_start` message in that session.
2. IAM-08: WHEN a message has `trigger.type == "event"` THEN the engine SHALL hold it in memory, and WHEN `Notti.trackEvent(name)` is called with a string equal to `trigger.name` (exact, case-sensitive, no trimming) and no message is visible THEN the engine SHALL present the oldest held message with that name (server order). The event name SHALL NOT be sent to the server, written to disk or logged.
3. IAM-09: WHEN a message is presented or visible THEN no other message SHALL be presented; each message id SHALL be presented at most once per session; and an event arriving while a message is visible SHALL be ignored.
4. IAM-10: WHEN the app restarts, or a new engine is built over the same `UserDefaults` suite, THEN no record of what was shown SHALL exist except the pending event queue, and a message the server returns SHALL be eligible to show again.
5. IAM-11: WHEN `trackEvent(name)` is called after the session started but before the held messages arrived THEN the engine SHALL remember the name (at most 32 distinct names, oldest dropped), and WHEN the messages arrive THEN it SHALL match the remembered names in call order, once, and present at most one message (OQ-2 closed). Names SHALL NOT be remembered across sessions.
6. IAM-12: WHEN a message is visible at the moment a new session's response arrives THEN the engine SHALL skip a candidate with that id, SHALL drop the `session_start` candidates, and SHALL hold the `event` candidates as usual (pending OQ-9).

**Independent Test**: A pure selector test with fixed lists (two session-start, two event with the same name) asserts which message is picked, once-per-session, and the ignore-while-visible rule, with no UI.

---

### P1: Render the four layouts ⭐ MVP

**User Story**: As an end user, I want the message to look native and fit my screen, and I want to be able to close it, whatever the layout.

**Why P1**: The visible part of the feature.

**Acceptance Criteria**:

1. IAM-13: WHEN a message is presented THEN its layout SHALL follow the contract table: `top` is a bar under the top safe area and at most 40% of the screen height, no backdrop, closable by the close control or a swipe up; `bottom` the mirror above the bottom safe area, swipe down; `center` a card centered, at most 90% of the width, over a 50% black backdrop, closable by the close control or a tap outside the card; `full` edge to edge inside the safe areas, buttons pinned to the bottom, closable by the close control only.
2. IAM-14: WHEN any layout is shown THEN a close control SHALL be visible and operable at all times, including during an auto-dismiss countdown and with long content, with a hit area of at least 44 x 44 pt.
3. IAM-15: WHEN the message has an image THEN it SHALL be a small leading thumbnail in `top` and `bottom`, and above the text in `center` and `full`; WHEN it has two buttons THEN `top` and `bottom` SHALL place them side by side and wrap them into a column when they do not fit (narrow screen or large Dynamic Type); `full` SHALL pin the buttons to the bottom of the safe area while the text scrolls.
4. IAM-16: WHEN a message is parsed THEN it SHALL be renderable only if it has a non-empty string `id`, at least one non-empty `title` or `body`, and a `trigger` of a known type; a button SHALL be kept only with a non-empty `id` and `label` (at most the first two); an `image_url` that is not an `https` URL SHALL be ignored (and an `image_action` without an image too); an unknown `format` SHALL render `center`.
5. IAM-17: WHEN content is taller than its bound (40% bars, the screen for `center`) THEN the text region SHALL scroll, the close control and the buttons SHALL stay reachable, and nothing SHALL be clipped without a way to reach it.
6. IAM-18: WHEN the device rotates, the size class changes or Dynamic Type changes THEN the layout SHALL re-flow within the same bounds and SHALL NOT report another impression or restart the countdown.
7. IAM-19: WHEN the message is on a `top` or `bottom` layout and the user taps the body (outside the close control, the buttons and a tappable image) AND the message has at least one button THEN the SDK SHALL run the action of the **first** button and report `click` with that button's id; WHEN it has no button THEN the body SHALL NOT be tappable.

**Independent Test**: A view controller built for a fixed size (for example 390 x 844 and 844 x 390) is laid out offscreen; the test walks the hierarchy by accessibility identifier and asserts frames against the bounds, the gesture recognizers present per layout, and the close control's frame.

---

### P1: Style and plain text ⭐ MVP

**User Story**: As a marketer, I want my colors and alignment honored, and as a security reviewer I want the text never interpreted as markup.

**Why P1**: Style is the second visible gap IARM closed; plain text is a contract security rule.

**Acceptance Criteria**:

1. IAM-20: WHEN `style` carries `background_color`, `text_color`, `button_color` or `button_text_color` as `#RRGGBB` THEN the SDK SHALL apply it (card or bar background, title and body, button background, button label, and the close control tint from `text_color`); WHEN a value cannot be parsed (wrong length, no `#`, non-hex, alpha form, non-string) THEN that token SHALL use its default and nothing SHALL fail or log the value.
2. IAM-21: WHEN `text_align` is `left`, `center` or `right` THEN title and body SHALL use it; absent or unknown SHALL mean `left`. WHEN `margin` is `false` THEN the card or bar SHALL touch the screen edges horizontally (still under the safe area); absent SHALL mean `true` (16 pt inset on `top`, `bottom`, `full`); `center` SHALL ignore `margin`.
3. IAM-22: WHEN `button_color` or `button_text_color` is set THEN every button SHALL use it (the absent one keeps its default) and the secondary button SHALL NOT be drawn in a different style; WHEN `style` is `null` or absent THEN the defaults of the Assumptions table SHALL apply.
4. IAM-23: WHEN `title` or `body` contains HTML tags, Markdown (`**x**`, `[x](https://example.invalid)`, `# x`), entities or newlines THEN it SHALL be displayed character for character (newlines kept) with no styling, link detection or attributed parsing. The implementation SHALL use `UILabel.text` (never `attributedText` from markup, never `AttributedString(markdown:)`, never a web view). Text SHALL NOT be truncated at 100 / 500 characters (the server enforces it) and SHALL NOT be written to a log.

**Independent Test**: Parse and style tests with a table of valid and invalid colors; a hierarchy test sets title `**bold** <b>x</b> [l](https://example.invalid)` and asserts the label's `text` equals it and `attributedText` has no link or bold attribute.

---

### P1: Link actions and clicks ⭐ MVP

**User Story**: As an integrator, I want to decide what a tapped link does inside my app, and as a marketer I want every tap counted once.

**Why P1**: Buttons without actions are decoration; and the SDK cannot open URLs (DEL-18).

**Acceptance Criteria**:

1. IAM-24: WHEN the user taps a button, a tappable image or the body of a `top` / `bottom` message THEN the SDK SHALL deliver, on the main thread, a `NottiInAppClick` (`messageId`, `buttonId`, `action` with `type` `url` or `deeplink` and the untouched `value`; `action` is nil for an action type the SDK does not know) to every listener added through `Notti.InAppMessages.addClickListener`, SHALL NOT call any URL-opening API, and SHALL NOT validate, rewrite or log the value. `scripts/check-no-url-open.sh` SHALL stay green.
2. IAM-25: WHEN a tap happens THEN the SDK SHALL report exactly one `click` with `button_id` set to the button's id, to `image` for the image (only when the message has an `image_action`), or to the first button's id for a body tap; it SHALL do so even when no listener is registered, and SHALL then close the display without a `dismiss`.
3. IAM-26: WHEN a click closes the message THEN the order SHALL be: impression already reported, `click` queued, listeners called, display closed. WHEN two taps arrive in the same run loop turn THEN only the first SHALL count (the display is already closing).

**Independent Test**: A fake presenter drives `tap(button:)`; assertions on the queue (one `click`, correct `button_id`, no `dismiss`), on a recording listener, and a grep over the new sources for the banned open APIs.

---

### P1: Impressions, dismissals and the event queue ⭐ MVP

**User Story**: As a marketer, I want reliable counts, and as an integrator I want events to survive offline periods and retries without double counting.

**Why P1**: The server counts what the SDK sends; frequency (`once`, `n_times`, `interval`) depends on impressions.

**Acceptance Criteria**:

1. IAM-27: WHEN a message becomes visible THEN the engine SHALL record exactly one `impression` for that display, and re-layout, rotation, Dynamic Type change, scene re-attachment and a late image SHALL NOT record another. The `impression` SHALL be queued before any `click` or `dismiss` of the same display (the engine records it first if it is somehow missing).
2. IAM-28: WHEN the user closes the message without a click THEN the engine SHALL record `dismiss` with `reason` `close_button` (close control), `swipe` (swipe gesture of `top` / `bottom`) or `outside_tap` (tap on the backdrop of `center`); WHEN the auto-dismiss timer closes it THEN `reason` SHALL be `auto`.
3. IAM-29: WHEN an event occurs THEN the SDK SHALL generate its `event_id` (UUID) at that moment, store it in the queue record, and reuse it for every retry and every app restart; the body SHALL carry `device_id`, `token`, `event_id`, `type`, `button_id` (click only), `reason` (dismiss only) and `occurred_at` (RFC 3339, the real time of the event) and nothing else.
4. IAM-30: WHEN an event is recorded THEN it SHALL be persisted before the first send attempt in `notti_inapp_pending_events` (record: `event_id`, `message_id`, `type`, `button_id?`, `reason?`, `occurred_at`; no token, no device id), the queue SHALL be flushed oldest first, SHALL drop an event older than 7 days at flush time, and SHALL hold at most 100 records (oldest dropped).
5. IAM-31: WHEN the server answers an event THEN `201` and `200` (duplicate) SHALL remove it; `404` and `422` SHALL remove it and log one fixed code; `429` SHALL pause the flush for `Retry-After` (same clamp as IAM-04) and keep the queue; `5xx` or a transport error SHALL retry the same event with backoff 2/4/8/16 s (5 attempts) and then stop the flush keeping the queue; `401` and `403` SHALL stop the flush and keep the queue.
6. IAM-32: WHEN the queue is flushed THEN the order SHALL be strict FIFO (a failed head blocks the rest, so impression always precedes click), and the flush SHALL run on the engine queue, independent of the CTR queue and of `NottiCore.workQueue` (a stuck In-App flush SHALL NOT delay login, tags or CTR events, and the reverse).
7. IAM-33: WHEN any of these happens THEN the engine SHALL start a flush: an event is recorded, registration succeeds, the app becomes active, the network returns (`NottiRuntime.onNetworkAvailable`), and just before `eligible`. At most one flush SHALL run at a time; a request arriving during a run SHALL be coalesced into one more pass.

**Independent Test**: A fake clock and scheduler plus a stubbed `URLProtocol`: queue three events, fail the first with 503, assert only one `event_id` was used across the retries and the order was never broken; reload the store from the same suite and assert the ids survive.

---

### P1: Auto dismiss ⭐ MVP

**User Story**: As a marketer, I want a tip to close by itself, and as a user I want to still close it earlier.

**Acceptance Criteria**:

1. IAM-34: WHEN `dismiss_after_seconds` is an integer from 1 to 300 THEN the countdown SHALL start when the message becomes visible and, at zero, the SDK SHALL close it and record `dismiss` with `reason: "auto"`; any other value (null, 0, 301, non-integer) SHALL mean no timer.
2. IAM-35: WHILE the app is in the background (`didEnterBackground` to `didBecomeActive`), or no foreground scene is available, the countdown SHALL be paused and SHALL resume with the remaining time; the close control SHALL remain available; a manual close during the countdown SHALL cancel the timer and report the gesture's own reason.

**Independent Test**: An injected clock and scheduler advance time: 8 s timer fires at 8 s; with a 3 s pause the fire moves by 3 s; a close at 2 s reports `close_button` and no `auto`.

---

### P1: Presentation, accessibility and safety ⭐ MVP

**User Story**: As an end user with assistive technology, and as an integrator who owns the app's windows, I want the message to be accessible and not interfere with the app.

**Acceptance Criteria**:

1. IAM-36: WHEN a message is presented THEN the SDK SHALL show it in a dedicated `UIWindow` on a foreground-active `UIWindowScene` (a legacy app without scenes: a window sized to the screen), above the host's windows, WITHOUT making it the key window and without resigning the host's first responder; WHEN the layout is `top` or `bottom` THEN touches outside the bar SHALL pass through to the host; WHEN it is `center` or `full` THEN the backdrop SHALL block them.
2. IAM-37: WHEN the scene backgrounds, disconnects or another scene becomes active THEN the window SHALL be torn down or moved to the active scene WITHOUT a new impression and WITHOUT a dismiss event; the display SHALL stay the same display (countdown paused while no scene is active).
3. IAM-38: WHEN VoiceOver is on THEN the title and body SHALL be one readable element in order, buttons SHALL carry the `.button` trait and their label, the image SHALL be decorative unless it has an `image_action` (then a button with a label), the close control SHALL have a localized label (`en`, `pt-BR`), `center` and `full` SHALL set `accessibilityViewIsModal` and move focus to the message (`.screenChanged`), and `top` / `bottom` SHALL announce title and body (`.announcement`) without trapping focus; WHEN Reduce Motion is on THEN the entrance, exit and swipe animations SHALL be a cross-fade or none.
4. IAM-39: WHEN the system appearance changes THEN default colors SHALL follow it; server-authored colors SHALL stay fixed. WHEN Dynamic Type is large THEN fonts SHALL scale (`UIFontMetrics`) and layouts SHALL stay inside IAM-13 / IAM-17.

**Independent Test**: A presenter test builds a window in the test host (no real scene needed through an injected scene provider), asserts `isKeyWindow == false`, pass-through `hitTest` for a bar, `accessibilityViewIsModal` per layout, and the translations of the close label. VoiceOver ordering is checked on a device (checklist).

---

### P1: Images ⭐ MVP

**User Story**: As a marketer, I want the picture to show when it can, and never to block or leak anything when it cannot.

**Acceptance Criteria**:

1. IAM-40: WHEN the message has an `https` `image_url` THEN the SDK SHALL download it with a dedicated ephemeral `URLSession` (no `Authorization` header, no cookies, no disk cache), a 10 s request timeout, and at most 5 MiB (declared length or bytes received, cancelled early), decode it downsampled to the display size, and keep at most 8 decoded images in an in-memory cache.
2. IAM-41: WHEN the download fails, is too large, is not decodable, redirects to a non-`https` URL, or does not finish within the 3 s presentation budget THEN the message SHALL still be presented without the image and the `image_action` SHALL be dropped; a late image SHALL NOT change a visible message.
3. IAM-42: WHEN the image is requested THEN the Client key, the push token and the device id SHALL NOT be sent to the image host, and the image URL SHALL NOT be logged.

**Independent Test**: A stubbed `URLProtocol` serves a PNG, an 11 MiB declared length, a redirect to `http`, a never-finishing response; assertions on the request headers (no `Authorization`) and on the presentation outcome.

---

### P1: Privacy, public surface and extension safety ⭐ MVP

**User Story**: As a compliance owner and as the maintainer, I want the feature to leak nothing, to be visible in the public surface, and to stay out of the extension.

**Acceptance Criteria**:

1. IAM-43: WHEN the engine, client, queue, presenter or image loader logs THEN it SHALL use `NottiLogger` (category `inapp`), fixed codes and `"\(error.domain)#\(error.code)"`, and SHALL NOT include the token, device id, message id, title, body, button labels, URLs, event names or `localizedDescription`. A sentinel in each of those fields SHALL NOT appear in any captured line on any path. Fixtures use `example.invalid` and `fixture`.
2. IAM-44: WHEN the public surface changes THEN `.specs/codebase/PUBLIC_SURFACE.txt` SHALL list `Notti.trackEvent`, `Notti.InAppMessages` with `addClickListener`, the `NottiInAppClick` and `NottiInAppAction` types and their `@objc` mirrors (`NottiObjC.trackEvent:`, `NottiInAppMessages` with `addClickListener:`), all app-only types SHALL carry `@available(iOSApplicationExtension, unavailable)` (plain value types are added to the allowlist of `check-public-surface.sh`), and `scripts/check-public-surface.sh` SHALL pass.
3. IAM-45: WHEN the package is built THEN nothing under `Sources/NottiShared` or `Sources/NottiSDKExtension` SHALL reference the new code, `scripts/check-extension-safety.sh`, `check-package-graph.sh`, `check-no-url-open.sh` and `check-launch-hook-purity.sh` SHALL stay green (no new source text contains `openURL`, `UIApplication.shared.open` or `.open(_:options`, comments included), both podspecs SHALL compile the new sources and the localized strings, and the strict device builds and `pod lib lint` SHALL pass.
4. IAM-46: WHEN the privacy manifest is reviewed THEN `PrivacyInfo.xcprivacy` SHALL keep its data types and reasons (no required-reason API added: no `systemUptime`, `mach_absolute_time`, file timestamp or disk-space call in the new code) and `PrivacyManifestTests` SHALL pass.

**Independent Test**: The sentinel sweep and the guard scripts (passing and failing fixture trees as in the existing scripts' proofs).

---

### P2: Documentation and example

**Acceptance Criteria**:

1. IAM-47: WHEN the feature ships THEN `README.md` SHALL document `trackEvent` and the click listener, with a prominent warning near the top of the In-App section that without a registered listener `click` is still reported but no link opens, `CHANGELOG.md` `[Unreleased]` SHALL list the feature, `.specs/codebase/TESTING.md` SHALL list the new layers, `PROJECT.md` SHALL no longer list In-App Messages as out of scope, and `Example/` SHALL have a button that calls `trackEvent` and a listener that logs the action kind only.
2. IAM-48: WHEN the manual device checklist (tasks.md, "Device validation checklist") runs THEN each line SHALL be marked pass, fail or not run in `validation.md`; the feature SHALL NOT be called verified before it does.

---

## Edge Cases

- WHEN `eligible` returns `{"messages": []}` or the App is disabled THEN nothing is shown, no event is created, and no retry runs.
- WHEN the response is `200` with a body that is not JSON, or `messages` is not an array THEN the engine SHALL treat it as a failed fetch (one fixed log code) and apply the `5xx` retry policy.
- WHEN two `event` messages name the same event THEN the older shows on the first call and the second one waits for the next call of that event (it has not been shown yet this session).
- WHEN `trackEvent("")` is called THEN the SDK SHALL ignore it with one `.warn` (no name in the line).
- WHEN `trackEvent` is called before `Notti.initialize` THEN the name SHALL be remembered per IAM-11 only if a session is open; otherwise ignored.
- WHEN `Notti.initialize` is called again with a different app id, client key or base URL THEN the engine SHALL reset its session state (held messages, remembered names, current fetch) and invalidate any in-flight response.
- WHEN a message has `image_action` but its image failed to load THEN the click `image` SHALL be impossible (no tappable image).
- WHEN the host registers no click listener and the user taps a button THEN `click` is reported, the display closes and the SDK logs one `.warn` (no values).
- WHEN the app is killed while a message is visible THEN the persisted `impression` stays queued, no `dismiss` is created, and the message may return next session according to the server.
- WHEN the device clock is wrong THEN `occurred_at` follows the device (the server ignores values outside 7 days past / 5 minutes future and stores its own time).
- WHEN the push token is nil or the device id is missing at send time THEN the flush and the fetch SHALL skip (nothing sent) and try again at the next trigger.
- WHEN the scene count is zero in a legacy (non-scene) app THEN the window SHALL fall back to a screen-sized window [Incerto, device checklist].
- WHEN iPad multitasking shows two scenes THEN the display attaches to one foreground-active scene only.
- WHEN the server's rate limit answers `429` on `events` THEN `eligible` is not blocked by it and vice versa (separate pauses).

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| IAM-01 | P1: Fetch once per session (trigger, once) | Specify | Pending |
| IAM-02 | P1: Fetch once per session (request shape) | Specify | Pending |
| IAM-03 | P1: Fetch once per session (flush before fetch) | Specify | Pending |
| IAM-04 | P1: Fetch once per session (error and retry policy) | Specify | Pending |
| IAM-05 | P1: Fetch once per session (lenient parsing) | Specify | Pending |
| IAM-06 | P1: Fetch once per session (session end, threading) | Specify | Pending |
| IAM-07 | P1: Choose what to show (session start) | Specify | Pending |
| IAM-08 | P1: Choose what to show (event trigger, local match) | Specify | Pending |
| IAM-09 | P1: Choose what to show (one visible, once per session) | Specify | Pending |
| IAM-10 | P1: Choose what to show (no persisted shown state) | Specify | Pending |
| IAM-11 | P1: Choose what to show (early events, OQ-2) | Specify | Pending |
| IAM-12 | P1: Choose what to show (visible across sessions, OQ-9) | Specify | Pending |
| IAM-13 | P1: Render the four layouts (placement, gestures) | Specify | Pending |
| IAM-14 | P1: Render the four layouts (close control) | Specify | Pending |
| IAM-15 | P1: Render the four layouts (image, buttons) | Specify | Pending |
| IAM-16 | P1: Render the four layouts (renderable rules, unknown format) | Specify | Pending |
| IAM-17 | P1: Render the four layouts (overflow) | Specify | Pending |
| IAM-18 | P1: Render the four layouts (rotation, no duplicate impression) | Specify | Pending |
| IAM-19 | P1: Render the four layouts (body tap on bars) | Specify | Pending |
| IAM-20 | P1: Style and plain text (colors) | Specify | Pending |
| IAM-21 | P1: Style and plain text (alignment, margin) | Specify | Pending |
| IAM-22 | P1: Style and plain text (button token, defaults) | Specify | Pending |
| IAM-23 | P1: Style and plain text (plain text only) | Specify | Pending |
| IAM-24 | P1: Link actions and clicks (listener, no URL open) | Specify | Pending |
| IAM-25 | P1: Link actions and clicks (click reporting) | Specify | Pending |
| IAM-26 | P1: Link actions and clicks (ordering, double tap) | Specify | Pending |
| IAM-27 | P1: Impressions, dismissals and the queue (impression once, first) | Specify | Pending |
| IAM-28 | P1: Impressions, dismissals and the queue (dismiss reasons) | Specify | Pending |
| IAM-29 | P1: Impressions, dismissals and the queue (event_id, body) | Specify | Pending |
| IAM-30 | P1: Impressions, dismissals and the queue (persistent queue) | Specify | Pending |
| IAM-31 | P1: Impressions, dismissals and the queue (server responses) | Specify | Pending |
| IAM-32 | P1: Impressions, dismissals and the queue (FIFO, independence) | Specify | Pending |
| IAM-33 | P1: Impressions, dismissals and the queue (flush triggers) | Specify | Pending |
| IAM-34 | P1: Auto dismiss (timer, reason auto) | Specify | Pending |
| IAM-35 | P1: Auto dismiss (pause, close available) | Specify | Pending |
| IAM-36 | P1: Presentation (window, pass-through, key window) | Specify | Pending |
| IAM-37 | P1: Presentation (scene lifecycle) | Specify | Pending |
| IAM-38 | P1: Presentation (accessibility, reduce motion) | Specify | Pending |
| IAM-39 | P1: Presentation (dark mode, Dynamic Type) | Specify | Pending |
| IAM-40 | P1: Images (download rules) | Specify | Pending |
| IAM-41 | P1: Images (failure never blocks) | Specify | Pending |
| IAM-42 | P1: Images (no credentials to the image host) | Specify | Pending |
| IAM-43 | P1: Privacy and surface (logging, sentinels) | Specify | Pending |
| IAM-44 | P1: Privacy and surface (PUBLIC_SURFACE, ObjC mirror) | Specify | Pending |
| IAM-45 | P1: Privacy and surface (extension safety, scripts, packaging) | Specify | Pending |
| IAM-46 | P1: Privacy and surface (privacy manifest) | Specify | Pending |
| IAM-47 | P2: Documentation and example | Specify | Pending |
| IAM-48 | P2: Documentation and example (device checklist) | Specify | Pending |

**Coverage:** 48 total, mapped to stories; task mapping in `tasks.md`.

---

## Success Criteria

- [ ] A stubbed server returns two `session_start` and two `event` messages: exactly one `eligible` call, one message shown at launch, the right event message on `trackEvent`, none twice, and the queue holds `impression` before `click` or `dismiss` with stable `event_id`s.
- [ ] Every status code of the contract's error table produces the behavior of IAM-04 and IAM-31, proven with a fake clock (no real sleeps).
- [ ] The four layouts stay inside their bounds at portrait and landscape sizes, with the largest Dynamic Type and a 500-character body, and the close control is always reachable.
- [ ] A title with Markdown and HTML is displayed verbatim.
- [ ] The tap of a `deeplink` button reaches a test listener with the untouched value and the SDK calls no open API (`check-no-url-open.sh` green).
- [ ] The sentinel sweep finds no token, device id, title, body, URL or event name in any log line.
- [ ] `check-public-surface.sh`, `check-extension-safety.sh`, `check-package-graph.sh`, `check-no-url-open.sh`, SwiftLint `--strict`, strict device builds and `pod lib lint` (both pods) are green, and the test count is at or above the baseline.
- [ ] The device checklist (`tasks.md`) is run on a real iPhone and an iPad before the feature is called verified. Until then rendering on devices, VoiceOver, window level over the keyboard and legacy (non-scene) apps are listed as unproven.
