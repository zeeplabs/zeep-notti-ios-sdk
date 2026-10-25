# In-App Messages Specification

**Status**: Approved by Julio 2026-10-24 (scope and the four AD-019 decisions), reconciled with `react-native-notti` 0.8.0 (tag `v0.8.0`, `291d5a7`). Execute done 2026-10-25 (T1-T20, T22); not verified until the device checklist (T21) and the Verifier pass.

## Problem Statement

`zeep-notti` can author In-App messages (four layouts, style tokens, tappable image, auto dismiss, event triggers, `push_permission` buttons) and serves them to devices, but `NottiSDK` cannot show them: it has no fetch, no UI and no event reporting for the route. The server side is implemented and its device contract is frozen in `zeep-notti/docs/en/sdks/in-app-messages.md` (the contract page at `zeep-notti` v0.24.0, source of truth; the older `docs/content/sdks/in-app-messages.mdx` path is gone) with the decisions of `zeep-notti/.specs/features/in-app-rich-messages/` (IARM-01..10, approved by the owner on 2026-10-18). The backend serves the payload since `zeep-notti` v0.23.0 (2026-10-22), unchanged in v0.24.0. The contract is server-driven and render-on-client: the server decides eligibility (audience, platform, schedule, frequency) and counts the events; the SDK fetches once per session, renders natively, and reports `impression`, `click` and `dismiss` reliably, because a lost impression makes a `once` message eligible again.

This feature is part of **M1 and `0.1.0`** (AD-017, 2026-10-24): 0.1.0 ships In-App Messages the way `react-native-notti` shipped them in 0.7.0/0.8.0. The parity baseline is RN 0.8.0 (RN repo `zeep-notti-react-native`, `ios/NottiInApp*.swift`, `ios/NottiPushPermissionAction.swift`, `ios/NottiApiClient.swift`, spec `.specs/features/in-app-messages/`). Where this spec and RN 0.8.0 differed, AD-019 aligns this spec with RN; the owner's four choices are recorded there and below. It needs the AD-001 spec first (this document). It does not wait for a tagged `0.1.0`: the `Example/` app and the release notes are edited by this feature's own tasks (T19, T20).

Constraint from the contract that shapes the design: the SDK must **not** keep its own "already shown" state (the server is the authority), must report impressions reliably (persistent queue), and must never open an author link: `scripts/check-no-url-open.sh` bans `UIApplication.shared.open` in `Sources/NottiSDK` (DEL-18). A link action therefore leaves the SDK as data, delivered to the host through a listener (IAM-24). The one exception (AD-019 decision 1) is the built-in `push_permission` button: with permission denied, the SDK opens the iOS notification settings through a fixed system constant, never author data, from one allowlisted file (IAM-50).

## Goals

- [ ] One `POST .../in-app-messages/eligible` per foreground session, after this process registered the device, never per screen, with the Client key and the device's `device_id` + push token.
- [ ] The first renderable `session_start` message appears right away; `event` messages are held in memory and appear on `Notti.trackEvent(name)` by exact local match; at most one message is visible; each message shows at most once per session.
- [ ] The four layouts (`top`, `center`, `bottom`, `full`) render natively inside the contract bounds and the RN 0.8.0 metrics, with the dismiss gestures of the table and a close control that is always visible.
- [ ] `title` and `body` are always plain text; style tokens are applied with safe fallbacks; an unparsable color never fails.
- [ ] `impression` is reported exactly once per display and always before `click` or `dismiss`; every event has a client-generated `event_id` that survives retries, restarts and an RN-to-native engine swap (same queue key and schema as RN).
- [ ] A link action (`url` or `deeplink`) reaches the host app through a public listener; the SDK never opens it. A `push_permission` button runs the OS permission flow itself.
- [ ] No token, device id, title, body, URL or event name in any log line; the privacy manifest stays accurate; nothing of this reaches `NottiShared` or `NottiSDKExtension`.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Opening author links (`url`, `deeplink`) inside the SDK | `check-no-url-open.sh` (DEL-18). The host decides what a link means. The SDK delivers the action (IAM-24). The only URL the SDK opens is the iOS notification-settings constant of a `push_permission` button (IAM-50) |
| Evaluating targeting (segment, platform, schedule, frequency) on the device | The contract: the server is the authority and the payload carries no targeting |
| A persistent "already shown" store, or any client-side frequency cap | The contract forbids it. The only persisted In-App state is the event queue |
| Sending event names to the server, or any key-value trigger conditions | The contract: names are matched locally and discarded at session end |
| HTML, Markdown or web-view content; custom fonts and sizes; carousel; per-locale content; test send | Out of scope of the contract (IARM Out of Scope) |
| SwiftUI view API (`.notti...` modifier), or a host-provided view for the message | Rendering is SDK-owned. A host view hook is a later feature |
| Display lifecycle callbacks (`willDisplay`, `didDismiss`) | Not in the contract. The only host-facing callback here is the click/action listener |
| Reusing `NottiEventStore` (CTR queue) for In-App events | Decided in design (D2): different schema, key, TTL and ordering needs; the CTR key stays byte-compatible with RN |
| Changing `NottiApiClient`'s retry policy or adding `Retry-After` to the existing routes | `queue-resilience` (M3) owns that. In-App gets its own non-blocking client |
| The backend's per-SDK minimum version for `push_permission` | A `zeep-notti` todo (AD-019 decision 4). Recorded as a dependency in the Assumptions table, no task here |
| macOS / Mac Catalyst, visionOS, app extensions | App-only, iOS 15+. All UI is `@available(iOSApplicationExtension, unavailable)` |
| Running the real UI in a Notification Service Extension | An NSE has no UI |
| Android, Flutter | Separate repos |
| Unit tests for pixel-exact rendering across devices | The contract gives bounds, not pixels. Layout is tested by hierarchy and frame bounds, and proved by the device checklist |

---

## Assumptions & Open Questions

Legend: `y` confirmed. Evidence tags: [Certo] verified in code or contract, [Provável] reasonable inference, [Incerto] needs validation. RN references are to `zeep-notti-react-native` at `v0.8.0`.

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Server contract | `docs/en/sdks/in-app-messages.md` (`zeep-notti` v0.24.0) is normative: routes, bodies, error table, limits (eligible 30/min, events 120/min per device), layouts table, triggers, style, auto dismiss, plain text rule, additive-only evolution. The server rejects unknown request fields (`422`); the payload omits `image_url` / `image_action` when unset; `style` and `dismiss_after_seconds` may be `null`; `action.type` is `url`, `deeplink` or `push_permission`, and `value` is absent for `push_permission` | Frozen by IARM, approved 2026-10-18; served since v0.23.0 [Certo] | y (Julio, 2026-10-18; OQ-6 closed 2026-10-24) |
| Contract defaults | `text_align` absent = `left`; `margin` absent = `true` (16 pt inset measured from the safe-area edge on `top`, `bottom`, `full`; `center` ignores it; refined by the margin row below); a button color token applies to every button; `style: null` = SDK defaults; unknown `format` = `center`; unknown fields ignored | Approved by the owner on 2026-10-18 | y (Julio, 2026-10-18) |
| What "session" means | The SDK's existing foreground session. The **first** session of the process opens when the core wins `NottiCore.SessionGate.tryOpen()` in `handleAppDidBecomeActive` (`NottiCore.swift:1020`) and reports it through a hook. **Later** sessions open on the main-thread `willEnterForeground` edge of the process observer in `NottiRuntime`, without waiting for the core's `workQueue` (AD-019 decision 3, RN `NottiInAppCoordinator.swift:227-241`, RN `5a3a1d3` design note). The core report is idempotent and, when it arrives while the app is in the background, is deferred to the next foreground (`sessionReportDeferred`). A repeat `didBecomeActive` and a core replacement that adopts the open session do not start one. The session ends at `didEnterBackground` from the process observer (`NottiRuntime.swift:74-83`), not from the core | The core's `tryOpen` and `close` run inside `workQueue.async` (`NottiCore.swift:1020`, `:1060`), which a retrying request can hold for about 105 s (5 attempts of 15 s plus 2/4/8/16 s); a session opened only from there would delay In-App on every return from background [Certo, code] | y (Julio, 2026-10-24, AD-019) |
| "Device registered" | The registration of **this process** succeeded (`registerDevice` `.success`, `NottiCore.swift:712-730`, `setLastToken` at `:722`), so the persisted `notti_device_id` and `notti_last_token` are the ones the server just accepted. Modeled as `registeredInProcess`: it survives session ends and is reset by a config change (whose new core registers again). `eligible` waits for it; the event flush does not (RN `NottiInAppSession.swift:102-105`, `14a4901`) | A device id persisted from an earlier launch with a rotated token would answer `403`. Registration runs on every launch [Certo, code] | y (AD-019, aligned with RN) |
| Where the engine lives | A process-level `NottiInAppEngine` owned by `NottiRuntime`, own serial queue `app.notti.sdk.inapp`, never `NottiCore.workQueue` and never the main thread for network or queue I/O | `NottiApiClient` blocks `workQueue` for minutes (retry + backoff, `NottiCore.swift:25-39`); an eligible fetch there would stall login and tags. Same ownership model as `sessionGate` and `eventBuffer` (`NottiRuntime.swift:29-31`) | y (design D1) |
| UI technology | UIKit (a dedicated `UIWindow` per display), not SwiftUI | Plain-text-by-construction (`UILabel.text`), no `openURL`/`Link` (the grep guard bans `openURL` text), hierarchy inspectable without third-party snapshot tools, pass-through hit testing for the bars, `accessibilityViewIsModal`, safe areas on iOS 15 | y (design D3, AD-013) |
| Link action delivery | `Notti.InAppMessages.addClickListener { NottiInAppClick }` (and the `@objc` mirror). The click carries `messageId`, `buttonId` and `action`: `{type, value}` with `type` `url` or `deeplink` and the untouched `value`, or nil. Swift: `action: NottiInAppAction?`; ObjC: the `action` key is a dictionary `{type, value}` or `NSNull`, never absent (RN `NottiInAppCoordinator.swift:19-32`) | The SDK never opens an author URL; a listener is the existing idiom (`NottiListenerHub`, main-thread delivery) | y (Julio, 2026-10-18, OQ-1; payload shape AD-019 decision 2) |
| `click` reporting when the host does not handle the link | The SDK **always** reports `click` for a tap, even with no listener registered or a listener that ignores it. The metric is "the user tapped", not "a link opened" | Matches the contract: a button tap sends `click`. Opening is the host's business | y (Julio, 2026-10-18, OQ-1) |
| Which taps close the message | Every button tap, image tap and body tap that has an action closes the display after the listener ran; the close reports only `click` (no `dismiss`) | Contract: "When a click closes the message, report the click". Closing first would cover the host's navigation | y (Julio, 2026-10-18, OQ-1) |
| `push_permission` button | Supported like RN (AD-019 decision 1). Buttons only (never `image_action`), no `value`. A tap reports one `click` with the button id, the listener receives `action: nil`, the message closes, then the platform action runs: not determined → `NottiCore.requestPermission` (keeps the subscribed PATCH and status refresh in the core); denied → open the iOS notification settings (`UIApplication.openNotificationSettingsURLString` on iOS 16+, else `UIApplication.openSettingsURLString`); authorized, provisional, ephemeral → nothing; unknown → one generic log line. No "no listener" warning for this action. If the platform port is not wired, the tap only reports and closes (RN `8640894`, `2b2a1c3`, `396d320`, `e9a5bb2`; `NottiInAppCoordinator.swift:274-288`; `NottiPushPermissionAction.swift`) | The only URL the SDK opens is that fixed system constant, from one file allowlisted in `scripts/check-no-url-open.sh`; author data is never opened | y (Julio, 2026-10-24, AD-019) |
| Backend gate for `push_permission` | The server serves a message with a `push_permission` button only when the device's `push_status != ok` and its `sdk_version >= MinSDKVersionPushPermission`, which is empty today, so no device receives such a message yet (`zeep-notti` `internal/inapp/sdkversion.go:11`, `eligibility.go:145-148`). A per-SDK minimum is needed before the dashboard enables it | Dependency only (AD-019 decision 4, a `zeep-notti` todo); the SDK side ships regardless [Certo, code] | y (Julio, 2026-10-24) |
| `trackEvent` placement and name | `Notti.trackEvent(_ name: String)` (top level, not under `InAppMessages`); ObjC `+[Notti trackEvent:]` | Contract wording; same name as RN | y (Julio, 2026-10-18) |
| `trackEvent` before the fetch has completed | Event names reported earlier **in the same session** are remembered in memory (distinct names; the **first 32** are kept and later new names are ignored, RN `NottiInAppSession.swift:236`) and matched once when the held messages arrive. No replay across sessions, none after a message is shown. An empty or whitespace-only name is a silent no-op (RN `NottiInAppSession.swift:233`, SDKIAM-59). The cold-start window is the row below | Without it, `trackEvent("home_viewed")` at launch races the network and the message is lost whenever the app is faster than the fetch | y (Julio, 2026-10-18, OQ-2; cap behavior AD-019) |
| Other `session_start` messages beyond the first | Not shown this session (neither queued nor re-fetched). They stay eligible for the next session | Contract: "Show the **first** session-start message the SDK can render" | y (Julio, 2026-10-18) |
| An event fires while a message is visible | The event is ignored (not queued, not replayed after the close) | Contract: show "only when no message is visible" | y (contract; RN `matchHeld`) |
| A message is visible when the session ends | The display survives the background (the auto-dismiss timer pauses, contract) and stays one visible message. The next session's fetch skips that message id; its `session_start` candidates are dropped for that session; `event` candidates are held normally | The contract pauses the timer in the background, so the display is expected to survive it | y (Julio, 2026-10-18) |
| Defaults for colors and typography | Semantic system colors (adapt to dark mode): background `secondarySystemBackground`, text `label`; first button filled (`systemBlue` / `white`), second button tinted (`tertiarySystemFill` / `label`); with any button token set, all buttons are filled with that token (the absent one keeps its default). Fonts: `headline` for the title, `subheadline` for the body, bold `subheadline` for the buttons (RN `NottiInAppStyle.swift:66-94`, `NottiInAppViews.swift:609-635`) | Same palette and fonts as RN 0.8.0 | y (Julio, 2026-10-18, OQ-5; fonts aligned AD-019) |
| Image wait | The message is presented after the image loads or after 3 s; on timeout it is shown without the image (and without `image_action`, which cannot be tapped), and a late image is dropped | Avoids layout jumps and an indefinitely delayed message | y (Julio, 2026-10-18: 3 s and 5 MiB) |
| In-App event queue | Separate from the CTR queue, with RN's key `notti_pending_inapp_events` in the `notti_prefs` suite and RN's Codable camelCase record `{id, eventId, appId, messageId, type, buttonId?, reason?, occurredAtMs}` stored as JSON `Data` (RN `NottiInAppEventStore.swift:15-31`, `:140-157`). Cap 100 (oldest dropped), drop of records older than 7 days (a record exactly 7 days old is kept), FIFO with stop-on-transient-failure | Pending events survive an RN-to-native engine swap (AD-019 decision 2). Impression must precede click, so skip-ahead is not allowed | y (Julio, 2026-10-24, AD-019) |
| Client retry constants | Eligible and events: 5 attempts, backoff 2/4/8/16 s, non-blocking. `408` is transient like `5xx` and transport errors. `429` on events: pause the flush for `Retry-After` (clamped to 1...300 s, 60 s when absent or invalid) as a stored deadline shared by every trigger, with no wait count and no give-up (RN SDKIAM-49, `NottiInAppCoordinator.swift:538-547`); `429` on `eligible` has its own cap (row below) | Constants kept in one place (RN `InAppTiming`) | y (Julio, 2026-10-18 and 2026-10-19; events wait count removed to match RN, AD-019) |
| `403` on either route | No retry. Eligible: stop for this session. Events: stop the flush and keep the queue. The SDK does not trigger a re-registration itself. One fixed `.warn` on `403` only, once per session per route, and a CHANGELOG note | The contract says "Re-register the device, do not retry as is"; this SDK deliberately diverges (same as RN) | y (Julio, 2026-10-18) |
| Margin standard (same on both platforms) | `margin: true` or absent = 16 pt inset measured **from the safe-area edge** (`top`: top and horizontal, `bottom`: bottom and horizontal, `full`: all sides). `margin: false` = the bar or card touches the safe-area edges on all sides and is never drawn under the notch or Dynamic Island, the status bar or the home indicator; in landscape it stays inside the left and right safe-area insets. `center` ignores `margin` | One rule for both SDKs (RN `computeFrame`, `NottiInAppStyle.swift:140-182`) | y (Julio, 2026-10-19) |
| `401` and `403` text | The "In-App is inactive on this device until the next registration" `.warn` is logged **only on `403`**. `401` (invalid client key) stops the fetch and the flush for the session (a `401` seen by the pre-`eligible` flush also skips `eligible`), keeps the queue, forces no re-registration, and logs only one generic fixed code | A `403` can be fixed by a re-registration; a `401` cannot | y (Julio, 2026-10-19) |
| Accessibility escape gesture | On a `center` or `full` message the VoiceOver escape gesture (`accessibilityPerformEscape`, two-finger Z) acts as the close control and the SDK reports `dismiss` with `close_button`. `top` and `bottom` do not handle it. iOS has no equivalent of the Android Back button (in RN on Android, Back is consumed as a no-op on `center` and `full` and not intercepted on `top` and `bottom`, RN A19, SDKIAM-22; recorded in the design parity checklist only) | Same as RN SDKIAM-63 | y (Julio, 2026-10-19) |
| `trackEvent` cold-start window | Names reported after `Notti.initialize` and before the **first** session of this process opens are remembered (memory only, same first-32 cap) and belong to that first session: they are replayed once, in call order, when the held messages arrive. Names reported before `Notti.initialize`, or while no session is open because the app went to the background after a session had already run, are ignored (no-op, never logged). Modeled as an engine flag (`awaitingFirstSession`, set at initialize when no session has opened yet, cleared when the first session opens). **[Provável]**: at `didFinishLaunching` `UIApplication.applicationState` is `.inactive`, so the first session opens at `didBecomeActive`, inside a `workQueue` block (`NottiCore.swift:1020`), after a `trackEvent` right after `initialize`; to be confirmed on a device (checklist line 19) | Without it a launch-time name is dropped | y (Julio, 2026-10-19) |
| `eligible` `429` cap and pause | Only for `eligible`: if the parsed `Retry-After` is greater than 60 s the SDK gives up on `eligible` for this session without waiting; otherwise it waits max(1, `Retry-After`) s (60 s when absent or invalid) and retries, at most 3 waits. The wait is a stored pause deadline that **outlives its session**: a new session that starts inside the pause schedules its fetch for the end of the pause; only a config change clears it (RN `NottiInAppCoordinator.swift:371-378`, `14a4901`, SDKIAM-05) | A long `Retry-After` on a screen-time fetch means the message would appear out of context; the rate limit does not reset with the session | y (Julio, 2026-10-19; cross-session pause AD-019) |
| Network regain | When the network returns, a fetch of the **current** session that gave up on a network, `5xx` or `408` failure is resumed, at most once per reconnect (not after `401`, `403`, `422`, a `Retry-After` over 60 s or exhausted `429` waits), and never makes a second successful fetch in one session (RN spec edge case ~line 314; `tryStartFetch` accepts `.gaveUp(transient: true)`, `NottiInAppSession.swift:190-198`) | Offline at session start would otherwise lose the whole session | y (AD-019, aligned with RN) |
| Re-initialize and the queue `app_id` | `Notti.initialize` again with a **different** app id, client key or base URL: the engine resets its session state (held messages, remembered names, the current fetch, `registeredInProcess`, the key-rejected flag, the `403` warning memory, and both `429` pause deadlines), invalidates any in-flight `eligible` response and tears down a visible display **without sending any event**. A same-config `initialize` preserves everything. Records carry the `appId` they were created for; the flush sends only records of the current app id, and a config change (and every flush pass) purges the records of other apps. The field is required (unreleased on native; RN records always carry it) | The server routes events by app id in the path; a record of another app can never succeed (RN `NottiInAppSession.swift:133-154`) | y (Julio, 2026-10-19; reset list AD-019) |
| Privacy manifest | `PrivacyInfo.xcprivacy` keys unchanged; only the comment mentioning Product Interaction is extended. No required-reason API is added: wall-clock `Date` for the timer (not `ProcessInfo.systemUptime`, `mach_absolute_time` or file timestamps), `UserDefaults` is already declared (CA92.1), the image cache is in memory. Reading the notification authorization status for `push_permission` is not a required-reason API and adds no collected data type (the permission status is already collected) | AD-005; PKG-13 | y (verify in T18) |

**Open questions:** none. OQ-1 to OQ-9 are closed (OQ-6 on 2026-10-24: the backend serves the payload since `zeep-notti` v0.23.0).

- **OQ-1 Link mechanism and click rule. CLOSED (Julio, 2026-10-18):** the integrator handles `url` and `deeplink`; the click listener of IAM-24, always-report-click, click closes the display without `dismiss`. With no listener registered: `click` is still reported, nothing opens, the display closes, one `.warn` (no values; not for `push_permission`). README must carry a prominent warning (IAM-47). RN has the same listener name and payload.
- **OQ-2 `trackEvent` before the fetch completes. CLOSED (Julio, 2026-10-18):** remember the session's distinct names (first 32 kept, aligned with RN) and re-evaluate on arrival.
- **OQ-3 Session granularity. CLOSED (Julio, 2026-10-18): keep.** Every foreground transition is a session and runs `eligible` (same as RN). A minimum-time-in-background threshold is a future evolution for both SDKs together.
- **OQ-4 Extra `session_start` messages. CLOSED (Julio, 2026-10-18):** only the first renderable one shows; the others generate no impression and stay eligible next session.
- **OQ-5 Default palette and fonts. CLOSED (Julio, 2026-10-18):** semantic system colors as in the table; fonts aligned with RN (AD-019).
- **OQ-6 Server release. CLOSED (2026-10-24, AD-017):** `zeep-notti` v0.23.0 (2026-10-22) first serves the IARM payload (`format` in four values, `style`, `trigger`); unchanged in v0.24.0, whose contract page is `docs/en/sdks/in-app-messages.md`. An older server returns `modal` / `banner`, rendered as `center` (unknown format rule).
- **OQ-7 `trackEvent` placement. CLOSED (Julio, 2026-10-18):** `Notti.trackEvent(name)` at the top level in both SDKs.
- **OQ-8 Image wait budget. CLOSED (Julio, 2026-10-18):** 3 s then show without image; 5 MiB cap.
- **OQ-9 Visible message across sessions. CLOSED (Julio, 2026-10-18):** the visible message survives the background across the session turn; the next fetch skips the same id and drops the pending `session_start` candidates.

---

## User Stories

### P1: Fetch once per session ⭐ MVP

**User Story**: As an integrator, I want the SDK to ask the server for eligible messages once per session, after the device is registered, so that messages appear without per-screen calls or rate-limit trouble.

**Why P1**: Nothing else works without it, and the route is rate limited per device.

**Acceptance Criteria**:

1. IAM-01: WHEN a foreground session is open (IAM-51) AND this process has registered the device (`registeredInProcess`), in either order, THEN the engine SHALL call `eligible` exactly once for that session. `registeredInProcess` SHALL survive session ends and SHALL be reset only by a config change (IAM-06). A repeat `didBecomeActive`, a token-refresh registration, a core replacement that adopts the open session, a late core session report for an already open session, and `trackEvent` SHALL NOT start another call. The event flush SHALL NOT require `registeredInProcess`.
2. IAM-02: WHEN `eligible` is called THEN the SDK SHALL send `POST {baseUrl}/v1/apps/{appId}/in-app-messages/eligible` with `Authorization: Bearer <client key>`, `Content-Type: application/json; charset=utf-8` and a body of exactly `device_id` and `token` (the persisted device id and last push token), SHALL percent-encode each path component on its own, and SHALL NOT send any other field (the server answers `422` to unknown fields).
3. IAM-03: WHEN the In-App event queue is not empty at that moment AND no events `429` pause is active THEN the engine SHALL try to flush it first, one attempt per event with no backoff, stopping at the first failure, and SHALL then call `eligible` regardless of the flush outcome, with one exception: a `401` (client key rejected) ends all In-App requests of the rest of the session (IAM-04, IAM-31), so `eligible` is not called after a flush that ended in `401`; a `403` in the flush logs the fixed inactive warning (IAM-31) and `eligible` is still called. WHILE an events `429` pause is active THEN the pre-fetch flush SHALL be skipped and `eligible` called directly. The pre-fetch pass MAY run while another flush pass owns the running flag; it SHALL NOT clear that flag (RN `NottiInAppCoordinator.swift:381-386`).
4. IAM-04: WHEN `eligible` answers `429` THEN, if the parsed `Retry-After` is greater than 60 s, the engine SHALL give up on `eligible` for this session without waiting (no second request, one fixed log code); otherwise it SHALL store a pause deadline of max(1, `Retry-After`) seconds (60 when absent or invalid) and retry after it, at most 3 waits; the deadline SHALL outlive the session: WHEN a new session starts before it elapses THEN the fetch SHALL be scheduled for the end of the pause (no request before it), and only a config change SHALL clear it. WHEN it answers `401` (invalid client key) THEN it SHALL NOT retry, SHALL stop the fetch and the flush for the session, SHALL keep the event queue, SHALL NOT force a re-registration and SHALL log only one generic fixed code (no registration text, no ids, no values); WHEN it answers `403` THEN it SHALL NOT retry, SHALL stop for the session and SHALL log once per session a fixed `.warn` stating that In-App is inactive on this device until the next registration (no ids, no values, no response body); WHEN it answers `422` or another `4xx` THEN it SHALL NOT retry and SHALL stop for the session; WHEN it answers `5xx` or `408`, the transport fails, or a `2xx` body cannot be parsed THEN it SHALL retry with backoff 2/4/8/16 s, 5 attempts in total, then give up for the session as transient (resumable by IAM-52). Every wait SHALL be non-blocking (no thread sleeps).
5. IAM-05: WHEN the response is parsed THEN unknown fields SHALL be ignored, a message that cannot be rendered SHALL be skipped without discarding the others, and an unknown `format` SHALL become `center` (see IAM-16 for what "renderable" means).
6. IAM-06: WHEN the session ends (`didEnterBackground`) before the response arrives THEN the late response SHALL be discarded (nothing held, nothing presented, a later `trackEvent` matches nothing; the same holds when a new session started in the meantime); WHEN it ends after THEN the held `event` messages SHALL be discarded. WHEN `Notti.initialize` is called again with a different app id, client key or base URL THEN the engine SHALL reset its session state (held messages, remembered names, the current fetch, `registeredInProcess`, the key-rejected flag, the `403` warning memory, the backoff and both `429` pause deadlines), SHALL discard an in-flight response and SHALL tear down a visible display WITHOUT sending any event; a same-config `initialize` SHALL preserve all of it. The engine SHALL NOT run on `NottiCore.workQueue` or on the main thread for network or queue I/O.

**Independent Test**: A fake session and registration signal plus a stubbed `URLProtocol` count calls: two signals in either order give one call; a second session gives a second call; no `eligible` before this process registered; each status code gives its policy (`429` with `Retry-After` 120 gives no second request, with 2 retries after 2 s; a new session inside a 30 s pause fetches at the pause end; `408` retries; `401` logs no registration text); a response that arrives after the session ended is dropped; a re-initialize with another config drops the in-flight response and the registered flag.

---

### P1: Choose what to show ⭐ MVP

**User Story**: As a product owner, I want the right message at the right moment, one at a time, so that the app is never covered by stacked cards.

**Why P1**: This is the selection contract; getting it wrong either spams users or loses impressions.

**Acceptance Criteria**:

1. IAM-07: WHEN the response arrives and no message is visible THEN the engine SHALL present the first renderable message with `trigger.type == "session_start"`, in server order, and SHALL NOT present any other `session_start` message in that session.
2. IAM-08: WHEN a message has `trigger.type == "event"` THEN the engine SHALL hold it in memory, and WHEN `Notti.trackEvent(name)` is called with a string equal to `trigger.name` (exact, case-sensitive, no trimming) and no message is visible THEN the engine SHALL present the oldest held message with that name (server order). The event name SHALL NOT be sent to the server, written to disk or logged.
3. IAM-09: WHEN a message is presented or visible THEN no other message SHALL be presented; each message id SHALL be presented at most once per session; and an event arriving while a message is visible SHALL be ignored.
4. IAM-10: WHEN the app restarts, or a new engine is built over the same `UserDefaults` suite, THEN no record of what was shown SHALL exist except the pending event queue, and a message the server returns SHALL be eligible to show again.
5. IAM-11: WHEN `trackEvent(name)` is called after the session started but before the held messages arrived (fetch not done), OR after `Notti.initialize` and before the first session of this process opens (`awaitingFirstSession`), THEN the engine SHALL remember the name (memory only, distinct names, the **first 32** kept and later new names ignored), and WHEN the messages arrive THEN it SHALL match the remembered names in call order, once, and present at most one message; names remembered before the first session belong to that first session. WHEN `trackEvent(name)` is called with an empty or whitespace-only name, before `Notti.initialize`, or while no session is open because the app went to the background after a session had already run, THEN it SHALL be a silent no-op (not remembered, never logged, no warning). Names SHALL NOT be remembered across sessions [Provável for the cold-start ordering, device checklist].
6. IAM-12: WHEN a message is visible at the moment a new session's response arrives THEN the engine SHALL skip a candidate with that id, SHALL drop the `session_start` candidates, and SHALL hold the `event` candidates as usual.

**Independent Test**: A pure selector test with fixed lists (two session-start, two event with the same name) asserts which message is picked, once-per-session, and the ignore-while-visible rule, with no UI. An engine test covers the cold-start window: `configure` then `trackEvent` before the session opens keeps the name for the first session; a name before `configure`, after a session ended, or blank is ignored; 33 distinct names keep the first 32.

---

### P1: Render the four layouts ⭐ MVP

**User Story**: As an end user, I want the message to look native and fit my screen, and I want to be able to close it, whatever the layout.

**Why P1**: The visible part of the feature.

**Acceptance Criteria**:

1. IAM-13: WHEN a message is presented THEN its layout SHALL follow the contract table and the RN 0.8.0 metrics (`NottiInAppStyle.swift:126-182`): `top` is a bar under the top safe area, its height at most min(40% of the container height, the safe-area height minus the two margins), no backdrop, closable by the close control or a swipe up; `bottom` the mirror above the bottom safe area, swipe down; `center` a card centered in the safe area, width min(90% of the container width, 560 pt, the safe-area width), height at most 90% of the container height minus the safe areas, over a 50% black backdrop, closable by the close control or a tap outside the card; `full` edge to edge inside the safe areas (minus the margin), buttons pinned to the bottom, closable by the close control only. A swipe is a pan in the dismiss direction whose translation reaches min(1/3 of the bar height, 44 pt) at release (RN `NottiInAppViews.swift:437-451`); a shorter pan snaps back; the pan begins only when the drag is mostly vertical, in the dismiss direction, and the text cannot scroll that way first.
2. IAM-14: WHEN any layout is shown THEN a close control SHALL be visible and operable at all times, including during an auto-dismiss countdown and with long content, with a hit area of 44 x 44 pt placed 8 pt from the card's top and trailing edges (top-leading in a right-to-left layout); WHEN it sits over an image (`center` and `full` with an image) THEN its glyph SHALL be white on a black 40% capsule chip, else tinted from the text color (RN `NottiInAppViews.swift:4-17, 186-189, 733-746`).
3. IAM-15: WHEN the message has an image THEN it SHALL be a 56 x 56 pt leading thumbnail in `top` and `bottom`; in `center` it SHALL fill the content width above the text, center-cropped (aspect fill), at most 180 pt tall; in `full` it SHALL be aspect-fit (never cropped) and take the height the text leaves free, at least its natural height capped at 180 pt (RN `NottiInAppViews.swift:209-232, 622-628`). WHEN it has two buttons THEN they SHALL sit side by side when each label fits half the width on one line, else one per row (narrow screen or large Dynamic Type); `full` SHALL pin the buttons to the bottom of the card while the text scrolls.
4. IAM-16: WHEN a message is parsed THEN it SHALL be renderable only if it has a non-empty string `id`, at least one `title` or `body` that is not blank (whitespace only counts as empty), and a `trigger` of a known type (`session_start`, or `event` with a non-empty `name`); a button SHALL be kept only with a non-empty `id` and `label` (at most the first two); an action SHALL be parsed only as `url` or `deeplink` with a non-empty string `value` (else the action is nil, the button stays) or as `push_permission` (no `value`) on a **button** only; an `image_action` SHALL be `url` or `deeplink` only (a `push_permission` image action is dropped); an `image_url` that is not an `https` URL SHALL be ignored (and an `image_action` without an image too); an unknown `format` SHALL render `center` (RN `NottiInAppModels.swift:119-219`, `34d4368`).
5. IAM-17: WHEN content is taller than its bound THEN the text region SHALL scroll and the close control and the buttons SHALL stay reachable; WHEN the buttons alone are taller than the card's room (a bar in landscape at an accessibility text size) THEN they SHALL move into the scroll view after the text, so every button can still be scrolled to and tapped (RN `NottiInAppViews.swift:155-205`, `1265833`); nothing SHALL be clipped without a way to reach it.
6. IAM-18: WHEN the device rotates, the size class changes or Dynamic Type changes THEN the layout SHALL re-flow within the same bounds and SHALL NOT report another impression or restart the countdown. The display window SHALL follow the host key window's supported orientations and status bar appearance, never forcing its own (RN `NottiInAppPresenter.swift:96-108`).
7. IAM-19: WHEN the message is on a `top` or `bottom` layout and the user taps the body (outside the close control, the buttons and a tappable image) AND the message has at least one button THEN the SDK SHALL run the action of the **first** button and report `click` with that button's id; WHEN it has no button THEN the body SHALL NOT be tappable.

**Independent Test**: A view built for a fixed size (for example 390 x 844 and 844 x 390, and a 1024 x 1366 iPad size for the 560 pt cap) is laid out offscreen; the test walks the hierarchy by accessibility identifier and asserts frames against the bounds (16 pt inset from the safe-area edge, `margin: false` touching the safe-area edges, landscape insets, the 8 pt close inset, the 56 pt thumbnail, the 180 pt image cap), the pan threshold, the buttons-into-scroll switch, and the close control's frame.

---

### P1: Style and plain text ⭐ MVP

**User Story**: As a marketer, I want my colors and alignment honored, and as a security reviewer I want the text never interpreted as markup.

**Why P1**: Style is the second visible gap IARM closed; plain text is a contract security rule.

**Acceptance Criteria**:

1. IAM-20: WHEN `style` carries `background_color`, `text_color`, `button_color` or `button_text_color` as `#RRGGBB` THEN the SDK SHALL apply it (card or bar background, title and body, button background, button label, and the close control tint from `text_color` when not over an image); WHEN a value cannot be parsed (wrong length, no `#`, non-hex, alpha form, non-string) THEN that token SHALL use its default and nothing SHALL fail or log the value.
2. IAM-21: WHEN `text_align` is `left`, `center` or `right` THEN title and body SHALL use it as an **absolute** side (`right` stays right and `left` stays left in a right-to-left layout, RN `NottiInAppViews.swift:698-705`); absent or unknown SHALL mean `left`. WHEN `margin` is `true` or absent THEN `top`, `bottom` and `full` SHALL be inset 16 pt measured from the safe-area edge (`top` and `bottom` at their edge and horizontally, `full` on all sides). WHEN `margin` is `false` THEN the bar or card SHALL touch the safe-area edges on all sides, horizontally too, and SHALL NOT be drawn under the notch or Dynamic Island, the status bar or the home indicator (in landscape it stays inside the left and right safe-area insets); `center` SHALL ignore `margin`.
3. IAM-22: WHEN `button_color` or `button_text_color` is set THEN every button SHALL be filled with it (the absent one keeps its default) and the secondary button SHALL NOT be drawn in a different style; WHEN `style` is `null` or absent THEN the defaults of the Assumptions table SHALL apply.
4. IAM-23: WHEN `title` or `body` contains HTML tags, Markdown (`**x**`, `[x](https://example.invalid)`, `# x`), entities or newlines THEN it SHALL be displayed character for character (newlines kept) with no styling, link detection or attributed parsing. The implementation SHALL use `UILabel.text` (never `attributedText` from markup, never `AttributedString(markdown:)`, never a web view). A blank title or body label SHALL be hidden. Text SHALL NOT be truncated at 100 / 500 characters (the server enforces it) and SHALL NOT be written to a log.

**Independent Test**: Parse and style tests with a table of valid and invalid colors; a hierarchy test sets title `**bold** <b>x</b> [l](https://example.invalid)` and asserts the label's `text` equals it and `attributedText` has no link or bold attribute; `text_align: right` stays `.right` with a forced right-to-left layout.

---

### P1: Link actions and clicks ⭐ MVP

**User Story**: As an integrator, I want to decide what a tapped link does inside my app, and as a marketer I want every tap counted once.

**Why P1**: Buttons without actions are decoration; and the SDK cannot open author URLs (DEL-18).

**Acceptance Criteria**:

1. IAM-24: WHEN the user taps a button, a tappable image or the body of a `top` / `bottom` message THEN the SDK SHALL deliver, on the main thread, a `NottiInAppClick` (`messageId`, `buttonId`, `action`) to every listener added through `Notti.InAppMessages.addClickListener`, where `action` is always present and nullable: `{type, value}` with `type` `url` or `deeplink` and the untouched `value`, or nil for a button without a valid action and for a `push_permission` button (RN `NottiInAppCoordinator.swift:19-32, 279-281`, `11541d1`). The ObjC dictionary SHALL carry the keys `messageId`, `buttonId` and `action`, the latter a dictionary `{type, value}` or `NSNull`, never absent. The SDK SHALL NOT call any URL-opening API for these actions, and SHALL NOT validate, rewrite or log the value. `scripts/check-no-url-open.sh` SHALL stay green. *(Amended 2026-10-25 by AD-020 / `in-app-open-url` IOU-01..05: after the listeners, the SDK opens an `http`/`https` `url` action in the external browser unless `Notti.Options.opensInAppURLs` is false; `deeplink` and other schemes are never opened; the no-listener warning applies only when the SDK did not open the link.)*
2. IAM-25: WHEN a tap happens THEN the SDK SHALL report exactly one `click` with `button_id` set to the button's id, to `image` for the image (only when the message has an `image_action` and the image loaded), or to the first button's id for a body tap; it SHALL do so even when no listener is registered, and SHALL then close the display without a `dismiss`. With no listener the SDK SHALL log one fixed `.warn` (no values), except for a `push_permission` tap.
3. IAM-26: WHEN a click closes the message THEN the order SHALL be: impression already reported, `click` queued, listeners called, display closed, then (for `push_permission` only) the platform action (IAM-49). WHEN two taps arrive in the same run loop turn THEN only the first SHALL count (the display is already closing).

**Independent Test**: A fake presenter drives `tap(button:)`; assertions on the queue (one `click`, correct `button_id`, no `dismiss`), on a recording listener (`action` nil for `push_permission` and for an unknown action), and a grep over the new sources for the banned open APIs.

---

### P1: Impressions, dismissals and the event queue ⭐ MVP

**User Story**: As a marketer, I want reliable counts, and as an integrator I want events to survive offline periods and retries without double counting.

**Why P1**: The server counts what the SDK sends; frequency (`once`, `n_times`, `interval`) depends on impressions.

**Acceptance Criteria**:

1. IAM-27: WHEN a message becomes visible THEN the engine SHALL record exactly one `impression` for that display, and re-layout, rotation, Dynamic Type change, scene re-attachment and a late image SHALL NOT record another. The `impression` SHALL be queued before any `click` or `dismiss` of the same display (the engine records it first if it is somehow missing).
2. IAM-28: WHEN the user closes the message without a click THEN the engine SHALL record `dismiss` with `reason` `close_button` (close control or VoiceOver escape), `swipe` (pan of `top` / `bottom`) or `outside_tap` (tap on the backdrop of `center`); WHEN the auto-dismiss timer closes it THEN `reason` SHALL be `auto`.
3. IAM-29: WHEN an event occurs THEN the SDK SHALL generate its `event_id` (UUID v4, lowercase string) at that moment, store it in the queue record, and reuse it for every retry and every app restart; the body SHALL carry `device_id`, `token`, `event_id`, `type`, `button_id` (click only), `reason` (dismiss only) and `occurred_at` (RFC 3339 UTC with milliseconds, the real time of the event) and nothing else.
4. IAM-30: WHEN an event is recorded THEN it SHALL be persisted before the first send attempt under the key `notti_pending_inapp_events` of the `notti_prefs` suite as a JSON array (`Data`) of RN's Codable camelCase records `{id, eventId, appId, messageId, type, buttonId?, reason?, occurredAtMs}` (`id` local to the queue, `eventId` sent to the server; no token, no device id), byte-compatible with RN 0.8.0 (`NottiInAppEventStore.swift:15-31`, `:140-157`) so pending events survive an RN-to-native swap; the queue SHALL be flushed oldest first, SHALL send only records whose `appId` equals the current app id, SHALL drop records older than 7 days (a record exactly 7 days old is kept) at enqueue and at flush time, and SHALL hold at most 100 records (oldest dropped); WHEN the engine is configured with another app id, and at the start of every flush pass, THEN the records of other apps SHALL be purged; a stored value that does not decode (including a record without `appId`) SHALL be removed so the queue self-heals to empty.
5. IAM-31: WHEN the server answers an event THEN any `2xx` (`201` new, `200` duplicate) SHALL remove it; `404`, `422` and any other `4xx` except `401`, `403`, `408` and `429` SHALL remove it and log one fixed code; `429` SHALL pause the flush for `Retry-After` (clamped to 1...300 s, 60 s when absent or invalid, kept as a stored deadline shared by every trigger, with no wait count; the `eligible` cap of IAM-04 does not apply to events) and keep the queue; `5xx`, `408` or a transport error SHALL retry the same event with backoff 2/4/8/16 s (5 attempts) and then stop the flush keeping the queue; `401` SHALL stop the flush and the fetch for the session, keep the queue, force no re-registration and log only one generic fixed code (no registration text); `403` SHALL stop the flush and keep the queue, and SHALL log the fixed `.warn` (at most once per session for the events route) saying In-App is inactive on this device until the next registration, with no ids or values.
6. IAM-32: WHEN the queue is flushed THEN the order SHALL be strict FIFO (a failed head blocks the rest, so impression always precedes click), and the flush SHALL run on the engine queue, independent of the CTR queue and of `NottiCore.workQueue` (a stuck In-App flush SHALL NOT delay login, tags or CTR events, and the reverse).
7. IAM-33: WHEN any of these happens THEN the engine SHALL start a flush: an event is recorded, registration succeeds, the app comes to the foreground, the network returns (`NottiRuntime.onNetworkAvailable`), an events `429` pause elapses, and just before `eligible` (IAM-03). At most one flush SHALL run at a time; a request arriving during a run SHALL be coalesced into one more pass; no flush SHALL start while an events `429` pause is active or after a `401` in the session.

**Independent Test**: A fake clock and scheduler plus a stubbed `URLProtocol`: queue three events, fail the first with 503, assert only one `event_id` was used across the retries and the order was never broken; reload the store from the same suite and assert the ids and `appId`s survive, that a record of another app is never sent, and that a JSON fixture written in RN 0.8.0's format decodes and is sent.

---

### P1: Auto dismiss ⭐ MVP

**User Story**: As a marketer, I want a tip to close by itself, and as a user I want to still close it earlier.

**Acceptance Criteria**:

1. IAM-34: WHEN `dismiss_after_seconds` is an integer from 1 to 300 THEN the countdown SHALL start when the message becomes visible and, at zero, the SDK SHALL close it and record `dismiss` with `reason: "auto"`; any other value (null, 0, 301, non-integer) SHALL mean no timer.
2. IAM-35: WHILE the app is in the background (`didEnterBackground` to `willEnterForeground`), or no foreground scene is available, the countdown SHALL be paused and SHALL resume with the remaining time; the close control SHALL remain available; a manual close during the countdown SHALL cancel the timer and report the gesture's own reason.

**Independent Test**: An injected clock and scheduler advance time: 8 s timer fires at 8 s; with a 3 s pause the fire moves by 3 s; a close at 2 s reports `close_button` and no `auto`.

---

### P1: Presentation, accessibility and safety ⭐ MVP

**User Story**: As an end user with assistive technology, and as an integrator who owns the app's windows, I want the message to be accessible and not interfere with the app.

**Acceptance Criteria**:

1. IAM-36: WHEN a message is presented THEN the SDK SHALL show it in a dedicated `UIWindow` on a foreground-active `UIWindowScene` (a legacy app without scenes: a window sized to the screen), above the host's windows, WITHOUT making it the key window and without resigning the host's first responder; WHEN the layout is `top` or `bottom` THEN touches outside the bar SHALL pass through to the host; WHEN it is `center` or `full` THEN the backdrop SHALL block them.
2. IAM-37: WHEN the scene backgrounds, disconnects or another scene becomes active THEN the window SHALL be torn down or moved to the active scene WITHOUT a new impression and WITHOUT a dismiss event; the display SHALL stay the same display (countdown paused while no scene is active).
3. IAM-38: WHEN VoiceOver is on THEN the title SHALL be its own element with the `.header` trait, followed by the body as its own element; buttons SHALL carry the `.button` trait and their label; the image SHALL be decorative unless it has a tappable `image_action`, and then it SHALL be a `[.button, .image]` element labeled with the message title (author text only, no SDK string; no label when the title is blank) (RN `NottiInAppViews.swift:563-580`); the close control SHALL have an accessibility label from an in-code table (`Close`, `Fechar` for any language whose primary subtag is `pt`, fallback English, no resource bundle); `center` and `full` SHALL set `accessibilityViewIsModal` and move focus to the title (`.screenChanged`, or the card when the title is hidden), and `top` / `bottom` SHALL announce title and body (`.announcement`) without trapping focus; WHEN the accessibility escape gesture (`accessibilityPerformEscape`, two-finger Z) is performed on a `center` or `full` message THEN it SHALL act as the close control and the SDK SHALL record `dismiss` with `reason` `close_button`, while `top` and `bottom` SHALL NOT handle it; WHEN Reduce Motion is on THEN the entrance, exit and swipe snap-back animations SHALL be a cross-fade or none.
4. IAM-39: WHEN the system appearance changes THEN default colors SHALL follow it; server-authored colors SHALL stay fixed. WHEN Dynamic Type is large THEN fonts SHALL scale (`adjustsFontForContentSizeCategory`) and layouts SHALL stay inside IAM-13 / IAM-17.

**Independent Test**: A presenter test builds a window in the test host (no real scene needed through an injected scene provider), asserts `isKeyWindow == false`, pass-through `hitTest` for a bar, `accessibilityViewIsModal` per layout, the header trait on the title, the image label equal to the title, `accessibilityPerformEscape` (closes `center` and `full` with `close_button`, not handled on bars) and the close label for `en`, `pt-BR`, `pt-PT` and an unknown language. VoiceOver ordering is checked on a device (checklist).

---

### P1: Images ⭐ MVP

**User Story**: As a marketer, I want the picture to show when it can, and never to block or leak anything when it cannot.

**Acceptance Criteria**:

1. IAM-40: WHEN the message has an `https` `image_url` THEN the SDK SHALL download it with a dedicated ephemeral `URLSession` (no `Authorization` header, no cookies, no URL cache, no credential storage), the whole call bounded to 10 s, at most 5 MiB (declared length or bytes received, cancelled early), and decode it always through `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` (so EXIF orientation is applied even to a small image) and a max pixel size of min(the image's longest side, the screen's longest side in physical pixels), never upscaling (RN `NottiInAppPresenter.swift:263`, `NottiInAppImageLoader.swift:120-147`, `60f2e3f`, `6660fb4`); decoded images SHALL be kept in an in-memory LRU cache of 5 entries, cleared on a memory warning.
2. IAM-41: WHEN the download fails, is too large, is not decodable, redirects to a non-`https` URL, answers a non-`2xx` status, or does not finish within the 3 s presentation budget THEN the message SHALL still be presented without the image and the `image_action` SHALL be dropped; a late image SHALL NOT change a visible message.
3. IAM-42: WHEN the image is requested THEN the Client key, the push token and the device id SHALL NOT be sent to the image host, and the image URL SHALL NOT be logged.

**Independent Test**: A stubbed `URLProtocol` serves a PNG, an EXIF-rotated small JPEG, an image larger than the screen, an 11 MiB declared length, a redirect to `http`, a never-finishing response; assertions on the request headers (no `Authorization`), on the decoded size (never above the screen's long side, never upscaled), on the orientation and on the presentation outcome.

---

### P1: Privacy, public surface and extension safety ⭐ MVP

**User Story**: As a compliance owner and as the maintainer, I want the feature to leak nothing, to be visible in the public surface, and to stay out of the extension.

**Acceptance Criteria**:

1. IAM-43: WHEN the engine, client, queue, presenter, image loader or push permission action logs THEN it SHALL use `NottiLogger` (category `inapp`), fixed codes and `"\(error.domain)#\(error.code)"`, and SHALL NOT include the token, device id, message id, title, body, button labels, URLs, event names or `localizedDescription`. A sentinel in each of those fields SHALL NOT appear in any captured line on any path. Fixtures use `example.invalid` and `fixture`.
2. IAM-44: WHEN the public surface changes THEN `.specs/codebase/PUBLIC_SURFACE.txt` SHALL list `Notti.trackEvent`, `Notti.InAppMessages` with `addClickListener`, the `NottiInAppClick` and `NottiInAppAction` types and their `@objc` mirrors (`NottiObjC.trackEvent:`, `NottiInAppMessages` with `addClickListener:`), all app-only types SHALL carry `@available(iOSApplicationExtension, unavailable)` (plain value types are added to the allowlist of `check-public-surface.sh`), and `scripts/check-public-surface.sh` SHALL pass.
3. IAM-45: WHEN the package is built THEN nothing under `Sources/NottiShared` or `Sources/NottiSDKExtension` SHALL reference the new code; `scripts/check-extension-safety.sh`, `check-package-graph.sh`, `check-no-url-open.sh` and `check-launch-hook-purity.sh` SHALL stay green; no new source text SHALL contain `openURL`, `UIApplication.shared.open` or `.open(_:options` (comments included) **except** the one file allowlisted in `check-no-url-open.sh` for the `push_permission` settings URL (IAM-50; AD-019 amends the "never opens a URL" rule of AD-013); both podspecs SHALL compile the new sources (no resource or packaging change is needed), and the strict device builds and `pod lib lint` SHALL pass. *(Amended 2026-10-25 by AD-020: a second allowlisted file, `NottiInAppURLOpener.swift`, opens validated `http`/`https` `url` actions.)*
4. IAM-46: WHEN the privacy manifest is reviewed THEN `PrivacyInfo.xcprivacy` SHALL keep its data types and reasons (no required-reason API added: no `systemUptime`, `mach_absolute_time`, file timestamp or disk-space call in the new code) and `PrivacyManifestTests` SHALL pass.

**Independent Test**: The sentinel sweep and the guard scripts (passing and failing fixture trees as in the existing scripts' proofs, plus a fixture that adds an open call to a non-allowlisted In-App file and fails).

---

### P1: Push permission button ⭐ MVP

**User Story**: As a marketer, I want a button that asks for push permission, and as a user I want it to do the right thing whatever I answered before.

**Why P1**: Owner decision (AD-019 decision 1), shipped by RN 0.8.0; an RN app swapped to this engine must not lose it.

**Acceptance Criteria**:

1. IAM-49: WHEN the user taps a button whose action is `push_permission` THEN the engine SHALL record one `click` with that button's id, SHALL deliver the click to the listeners with `action: nil`, SHALL NOT log the no-listener warning, SHALL close the display (no `dismiss`), and SHALL then run the platform action on the main thread; WHEN the platform action is not wired (no port set) THEN the tap SHALL only report and close. A body tap on a bar whose first button is `push_permission` SHALL behave the same (IAM-19). The port SHALL be set and read under the engine's confinement (RN `396d320`: set on the thread that reads it).
2. IAM-50: WHEN the platform action runs THEN it SHALL read the notification authorization status and: not determined → call `NottiCore.requestPermission` of the current core (`NottiCore.swift:365`; the subscribed PATCH and the status refresh stay in the core); denied → open `UIApplication.openNotificationSettingsURLString` on iOS 16+, else `UIApplication.openSettingsURLString`, on the main thread; authorized, provisional, ephemeral → nothing; unknown → one generic fixed log line. That settings URL SHALL be the only URL the SDK ever opens; it SHALL come only from the system constant (never from the payload) and the open call SHALL live in exactly one file, `Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift`, allowlisted by path in `scripts/check-no-url-open.sh`; the AGENTS.md rule "The SDK never opens a URL" SHALL state this exception.

**Independent Test**: The action with injected state reader, requester, settings opener and logger: one test per state row; a test that the allowlisted file opens only the two system constants (source grep: no other URL source, no payload type referenced); the guard script on a fixture tree with an open call in another In-App file fails.

---

### P1: Sessions and network regain ⭐ MVP

**User Story**: As an integrator, I want In-App to keep up with the app's foreground cycles even while the core is busy retrying, and to recover when the network comes back.

**Why P1**: Owner decision (AD-019 decision 3) and RN 0.8.0 behavior.

**Acceptance Criteria**:

1. IAM-51: WHEN the app returns to the foreground (`willEnterForeground`, main thread, process observer in `NottiRuntime`) AND a session has already opened in this process or a core session report was deferred, AND the engine is configured and no session is open, THEN the engine SHALL open the session itself, without waiting for `NottiCore.workQueue`; the first session of the process SHALL still come from the core hook (`tryOpen() == true`, `NottiCore.swift:1020`). WHEN the core reports a session that is already open THEN the report SHALL be ignored (idempotent); WHEN the core report arrives while the app is in the background THEN it SHALL be deferred and the next foreground SHALL open that session. The session SHALL end on `didEnterBackground` from the runtime's process observer (`NottiRuntime.swift:74-83`), even with no live core, which also pauses the display clock (RN `NottiImpl.swift:46-85`).
2. IAM-52: WHEN the network returns (`NottiRuntime.onNetworkAvailable`) AND the current session's fetch gave up on a transient failure (network, `5xx`, `408`, unparseable `2xx`) THEN the engine SHALL start the fetch again for the same session, at most once per reconnect; it SHALL NOT resume after `401`, `403`, `422`, a `Retry-After` over 60 s or exhausted `429` waits, and SHALL never produce a second successful fetch in one session.

**Independent Test**: A runtime with a fake core whose `workQueue` is blocked: background then `willEnterForeground` opens the session and calls `eligible` while the core is still blocked; the core's late report adds no call; a core report in background opens at the next foreground. An engine test: three transient failures exhaust the fetch, a network edge resumes it once, a second edge without a new failure does nothing, a `403` give-up is not resumed.

---

### P2: Documentation and example

**Acceptance Criteria**:

1. IAM-47: WHEN the feature ships THEN `README.md` SHALL document `trackEvent`, the click listener (payload with `action` nullable) and the `push_permission` button, with a prominent warning near the top of the In-App section that without a registered listener `click` is still reported but no link opens; `CHANGELOG.md` `[0.1.0]` SHALL describe the release as a native port of `react-native-notti` 0.8.0 with In-App Messages, list the feature, the new storage key `notti_pending_inapp_events` (RN's), the `push_permission` settings exception, and state that on `403` the SDK does not re-register as the server contract suggests; `example-and-release/release-pr.md` SHALL gain the In-App device checklist gate; `.specs/codebase/TESTING.md` SHALL list the new layers; `ROADMAP.md` SHALL show the feature's status; and `Example/` SHALL have a button that calls `trackEvent` and a listener that logs the action type only.
2. IAM-48: WHEN the manual device checklist (tasks.md, "Device validation checklist") runs THEN each line SHALL be marked pass, fail or not run in `validation.md`; the feature SHALL NOT be called verified before it does.

---

## Edge Cases

- WHEN `eligible` returns `{"messages": []}` or the App is disabled THEN nothing is shown, no event is created, and no retry runs.
- WHEN the response is `2xx` with a body that is not a JSON object, or `messages` is not an array THEN the engine SHALL treat it as a failed fetch (one fixed log code) and apply the transient retry policy (IAM-04).
- WHEN two `event` messages name the same event THEN the older shows on the first call and the second one waits for the next call of that event.
- WHEN `trackEvent("")` or `trackEvent("  ")` is called THEN the SDK SHALL ignore it silently (no log, no warning), like RN SDKIAM-59.
- WHEN `trackEvent` is called before `Notti.initialize` THEN the name SHALL be ignored (no-op, never logged). WHEN it is called after `Notti.initialize` and before the first session of this process opens THEN it SHALL be remembered per IAM-11 and belong to that first session. WHEN the app went to the background after a session had already run and `trackEvent` is called before the next session opens THEN it SHALL be ignored.
- WHEN the process was launched in the background (for example by a silent push) and `trackEvent` is called after `initialize` THEN the name is kept (first 32) until the first foreground session opens or the process ends [Provável, follows from IAM-11].
- WHEN `Notti.initialize` is called again with a different app id, client key or base URL THEN the engine SHALL reset its session state (IAM-06), invalidate any in-flight response, tear down a visible display without sending any event, and purge the queue records of other apps (IAM-30). WHEN the config is the same THEN everything SHALL be preserved (a re-initialize after the first session does not re-arm `awaitingFirstSession`).
- WHEN `eligible` answers `429` with `Retry-After: 120` THEN the engine SHALL give up for this session with no second request; with `Retry-After: 30` it SHALL retry after 30 s, and a session that starts 10 s into that pause SHALL fetch 20 s later, not at once (IAM-04).
- WHEN `eligible` or an event request answers `401` THEN no registration text SHALL be logged, only the generic fixed code (IAM-04, IAM-31).
- WHEN a message has `image_action` but its image failed to load THEN the click `image` SHALL be impossible (no tappable image). WHEN `image_action` is `push_permission` THEN it SHALL be dropped (buttons only).
- WHEN the host registers no click listener and the user taps a link button THEN `click` is reported, the display closes and the SDK logs one `.warn` (no values); for a `push_permission` button no warning is logged.
- WHEN a `push_permission` button is tapped and the permission is already granted THEN `click` is reported, the message closes and nothing else happens.
- WHEN the app is killed while a message is visible THEN the persisted `impression` stays queued, no `dismiss` is created, and the message may return next session according to the server.
- WHEN the device clock is wrong THEN `occurred_at` follows the device (the server ignores values outside 7 days past / 5 minutes future and stores its own time).
- WHEN the push token is nil or the device id is missing at send time THEN the flush and the fetch SHALL skip (nothing sent) and try again at the next trigger.
- WHEN the scene count is zero in a legacy (non-scene) app THEN the window SHALL fall back to a screen-sized window [Incerto, device checklist].
- WHEN iPad multitasking shows two scenes THEN the display attaches to one foreground-active scene only.
- WHEN the server's rate limit answers `429` on `events` THEN `eligible` is not blocked by it and vice versa (separate pauses); the pre-fetch flush is skipped while the events pause is active (IAM-03).
- WHEN the core's `workQueue` is held by a retrying request at a return from background THEN the session still opens at `willEnterForeground` (IAM-51).
- WHEN the device is offline at session start THEN `eligible` exhausts its backoff and gives up; the next network regain resumes it once (IAM-52).
- WHEN an RN 0.8.0 app with pending In-App events is updated to the native engine THEN those events are read from `notti_pending_inapp_events` and sent with their original `event_id` (IAM-30).

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| IAM-01 | P1: Fetch once per session (trigger, once, registered in this process) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-02 | P1: Fetch once per session (request shape) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-03 | P1: Fetch once per session (flush before fetch, events pause skip) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-04 | P1: Fetch once per session (error and retry policy, `eligible` 429 cap and cross-session pause, 408, 401 vs 403 text) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-05 | P1: Fetch once per session (lenient parsing) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-06 | P1: Fetch once per session (session end, late response, re-initialize reset, threading) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-07 | P1: Choose what to show (session start) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-08 | P1: Choose what to show (event trigger, local match) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-09 | P1: Choose what to show (one visible, once per session) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-10 | P1: Choose what to show (no persisted shown state) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-11 | P1: Choose what to show (early events, first 32, blank no-op, cold-start window) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-12 | P1: Choose what to show (visible across sessions, OQ-9) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-13 | P1: Render the four layouts (placement, RN metrics, pan swipe) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-14 | P1: Render the four layouts (close control, 8 pt inset, scrim chip) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-15 | P1: Render the four layouts (image sizing, buttons) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-16 | P1: Render the four layouts (renderable rules, action parsing, unknown format) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-17 | P1: Render the four layouts (overflow, buttons into the scroll view) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-18 | P1: Render the four layouts (rotation, host orientation, no duplicate impression) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-19 | P1: Render the four layouts (body tap on bars) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-20 | P1: Style and plain text (colors) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-21 | P1: Style and plain text (absolute alignment, margin from the safe-area edge) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-22 | P1: Style and plain text (button token, defaults) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-23 | P1: Style and plain text (plain text only) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-24 | P1: Link actions and clicks (listener, nullable `{type, value}`, no URL open) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-25 | P1: Link actions and clicks (click reporting) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-26 | P1: Link actions and clicks (ordering, double tap) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-27 | P1: Impressions, dismissals and the queue (impression once, first) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-28 | P1: Impressions, dismissals and the queue (dismiss reasons) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-29 | P1: Impressions, dismissals and the queue (event_id, body) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-30 | P1: Impressions, dismissals and the queue (RN key and schema, `appId` per record) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-31 | P1: Impressions, dismissals and the queue (server responses, 408, 401 vs 403 warning) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-32 | P1: Impressions, dismissals and the queue (FIFO, independence) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-33 | P1: Impressions, dismissals and the queue (flush triggers) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-34 | P1: Auto dismiss (timer, reason auto) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-35 | P1: Auto dismiss (pause, close available) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-36 | P1: Presentation (window, pass-through, key window) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-37 | P1: Presentation (scene lifecycle) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-38 | P1: Presentation (accessibility, header title, image label, escape gesture, close label table, reduce motion) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-39 | P1: Presentation (dark mode, Dynamic Type) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-40 | P1: Images (download and decode rules) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-41 | P1: Images (failure never blocks) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-42 | P1: Images (no credentials to the image host) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-43 | P1: Privacy and surface (logging, sentinels) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-44 | P1: Privacy and surface (PUBLIC_SURFACE, ObjC mirror) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-45 | P1: Privacy and surface (extension safety, scripts with the one allowlisted file, packaging) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-46 | P1: Privacy and surface (privacy manifest) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-47 | P2: Documentation and example | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-48 | P2: Documentation and example (device checklist) | Validate | Pending (T21 device checklist) |
| IAM-49 | P1: Push permission button (click, null action, close, then the platform action) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-50 | P1: Push permission button (state table, the only URL opened, allowlisted file) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-51 | P1: Sessions and network regain (foreground session open, idempotent core report, process-observer end) | Execute | Implemented, tested in the Simulator (`traceability.md`) |
| IAM-52 | P1: Sessions and network regain (resume a transient give-up once per reconnect) | Execute | Implemented, tested in the Simulator (`traceability.md`) |

**Coverage:** 52 total, mapped to stories; task mapping in `tasks.md`; tests per requirement in `traceability.md` (51 covered, IAM-48 pending T21).

---

## Success Criteria

- [ ] A stubbed server returns two `session_start` and two `event` messages: exactly one `eligible` call after this process registered, one message shown at launch, the right event message on `trackEvent`, none twice, and the queue holds `impression` before `click` or `dismiss` with stable `event_id`s.
- [ ] Every status code of the contract's error table (and `408`) produces the behavior of IAM-04 and IAM-31, proven with a fake clock (no real sleeps): `403` warns, `401` does not mention registration, `eligible` `429` over 60 s gives up, and a `429` pause carries into the next session.
- [ ] A `trackEvent` called right after `Notti.initialize` (same thread, app still inactive) matches its event message once the first session opens and the response arrives; a name called before `initialize`, after a session ended, or blank is never matched.
- [ ] With the core's `workQueue` blocked, a return from background opens the session and fetches (IAM-51).
- [ ] The four layouts stay inside their bounds at portrait, landscape and iPad sizes, with the largest Dynamic Type and a 500-character body, and the close control and every button are always reachable.
- [ ] A title with Markdown and HTML is displayed verbatim.
- [ ] The tap of a `deeplink` button reaches a test listener with the untouched value and the SDK calls no open API; a `push_permission` tap reaches the listener with `action: nil` and runs the state table; `check-no-url-open.sh` passes with exactly one allowlisted file.
- [ ] A queue written in RN 0.8.0's format is read and sent unchanged.
- [ ] The sentinel sweep finds no token, device id, title, body, URL or event name in any log line.
- [ ] `check-public-surface.sh`, `check-extension-safety.sh`, `check-package-graph.sh`, `check-no-url-open.sh`, SwiftLint `--strict`, strict device builds and `pod lib lint` (both pods) are green, and the test count is at or above the baseline.
- [ ] The device checklist (`tasks.md`) is run on a real iPhone and an iPad before the feature is called verified. Until then rendering on devices, VoiceOver, window level over the keyboard, legacy (non-scene) apps, the `push_permission` settings jump and the launch ordering of `initialize`, `trackEvent` and the first session (cold-start window) are listed as unproven.
