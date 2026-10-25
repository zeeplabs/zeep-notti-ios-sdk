# In-App Open URL Specification

## Problem Statement

Today an In-App `url` action leaves the SDK only as data: the click listener receives it and the host must open it (AD-013 D7, IAM-24). An app that forgets the listener, or registers one that only logs, shows a button that does nothing, and the SDK logs a warning nobody sees at the default `error` level. OneSignal and Braze open web links themselves. The SDK is not published yet and will become the native base of `react-native-notti` (AD-001, M2), so the owner aligned it with that behavior now (Julio, 2026-10-25, AD-020): the SDK opens `http`/`https` `url` actions in the external browser after the listener ran, on by default, with an option to turn it off. `deeplink` actions stay with the host.

## Goals

- [ ] A tap on an In-App `url` action whose value is an `http` or `https` URL with a host opens it in the external browser, after the click listeners were called.
- [ ] Nothing else is ever opened from author data: other schemes and `deeplink` actions reach the listener only.
- [ ] One option turns it off (`Notti.Options.opensInAppURLs`, ObjC mirror), so the RN bridge can keep RN 0.8.0 behavior.
- [ ] No URL, or any part of one, in a log line. The URL guard allowlists exactly two files.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Opening `deeplink` actions | The host owns its routes; a custom scheme can trigger anything in another app |
| An in-app browser (`SFSafariViewController`) | External browser only, like the owner decision; a presented controller needs a view-controller host the In-App window does not provide |
| Universal links opened in the app itself | `UIApplication.open` on an `https` URL already hands a universal link to its app; no SDK option for it |
| Opening a push's `data` link | DEL-18 unchanged: a push link reaches the host untouched |
| RN bridge changes | `react-native-notti` passes `false` or adopts the behavior when it moves onto this SDK (STATE todo) |
| A toggle in the Example app | The Example passes the default explicitly; no setting UI for options exists |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Which actions open | `url` from a button, the tappable image or a bar body acting as its first button; never `deeplink` | Owner decision 2026-10-25 | y (Julio, AD-020) |
| Scheme allowlist | `http` and `https`, case-insensitive, with a non-empty host; a value with whitespace or control characters is refused before parsing | A `url` action is author data from the dashboard: `tel:`, `sms:`, custom schemes or `javascript:` would let a message call, text or drive another app without the host's consent. Refusing whitespace keeps the result the same on iOS 15/16 and iOS 17+ (Foundation percent-encodes invalid characters only from iOS 17) | y (Julio, AD-020) |
| Order | Listener delivery, then the close, then the open; all on the main thread (the open is queued after the listener's main-thread block) | Owner decision ("first delivers the click to the listeners"); the message is gone before Safari comes forward | y (Julio, AD-020) |
| Default | On (`opensInAppURLs: true`) | Owner decision | y (Julio, AD-020) |
| `initialize` with only the option changed | Applies the option without restarting the core or re-registering; the same appId, clientKey and baseUrl stay a no-op for the core | The option is local In-App behavior; a restart would re-register the device for a UI choice | n (proposed, D1) |
| Option on an invalid `initialize` | Ignored with the rest of the call | "Invalid values are logged and ignored" (API-01) | n (proposed) |
| Refusal log | One fixed `.debug` line, no value, when a `url` action is not opened because of its value; nothing when the option is off | Diagnosable at `debug`, invisible at the default level, no data | y (owner brief allows warn or debug) |
| Open failure | No retry; one fixed `.warn` line, no URL | Owner decision | y (Julio, AD-020) |
| No-listener warning | Logged only when the SDK did not handle the tap itself: no listener and (a `deeplink`, a `url` not opened, or no action); never for `push_permission` | Owner decision; a tap the SDK opened is handled | y (Julio, AD-020) |

**Open questions:** none blocking. D1 (option-only re-initialize) is a proposal recorded here and in AD-020.

---

## User Stories

### P1: The SDK opens web links of In-App messages ⭐ MVP

**User Story:** As an integrator, I want a `url` button of an In-App message to open in Safari without code, so a message works even before I write a click listener.

**Acceptance Criteria:**

1. IOU-01: WHEN the user taps an In-App button, a tappable image or a bar body whose action is `url`, AND `opensInAppURLs` is true, AND the value is an `http` or `https` URL (scheme case-insensitive) with a non-empty host THEN the SDK SHALL first hand the click to the click listeners exactly as before (same `NottiInAppClick`, `action.value` untouched), then close the display, then call `UIApplication.shared.open` with that URL once, on the main thread.
2. IOU-02: WHEN a `url` action's value has any other scheme (`tel`, `sms`, `mailto`, custom, `javascript`, ...), no scheme, no host, is empty, or contains whitespace or control characters THEN the SDK SHALL NOT open it, SHALL still deliver it to the listener untouched, and SHALL log at most one fixed `.debug` line with no part of the value.
3. IOU-03: WHEN the action is `deeplink` THEN the SDK SHALL NOT open it under any option (listener only, unchanged).
4. IOU-04: WHEN the host calls `Notti.initialize(appId:clientKey:options:)` THEN `Notti.Options.opensInAppURLs` SHALL default to true, `Notti.Options(baseUrl:)` SHALL keep compiling, and `opensInAppURLs: false` SHALL stop every SDK open (IOU-01) with no refusal log. Objective-C SHALL offer `+[Notti initializeWithAppId:clientKey:baseUrl:opensInAppURLs:]`; the existing `initializeWithAppId:clientKey:baseUrl:` SHALL keep the default (true). A valid `initialize` that changes only the option SHALL apply it without restarting the core.

**Independent Test:** engine tests with a recording open port and a fake main dispatcher; facade tests over an isolated runtime.

---

### P1: Unchanged parts and logging ⭐ MVP

**User Story:** As the Notti team, I want the click metric, `push_permission` and the privacy rules unchanged, so the new behavior adds one effect and nothing else.

**Acceptance Criteria:**

1. IOU-05: WHEN no click listener is registered THEN the SDK SHALL log the existing fixed no-listener `.warn` only if it did not open the URL itself (a `deeplink`, a `url` not opened for the option or the value, or a button with no action), and never for `push_permission`. The text SHALL stay free of any URL or value.
2. IOU-06: WHEN `UIApplication.open` reports failure THEN the SDK SHALL NOT retry and SHALL log at most one fixed `.warn` line without the URL.
3. IOU-07: WHEN any tap happens THEN `click` and `dismiss` reporting, the display close, the `push_permission` platform action and the listener payload SHALL behave exactly as before this feature.
4. IOU-08: WHEN the package is checked THEN `scripts/check-no-url-open.sh` SHALL allow `UIApplication.shared.open(` lines in exactly two files (`NottiPushPermissionAction.swift`, AD-019; `NottiInAppURLOpener.swift`, AD-020) and fail on the same call anywhere else; a unit test SHALL pin the opener file to one open call that takes the validated URL; the In-App privacy sentinel tests SHALL cover the open, refusal and failure paths with no sentinel (URL included) in any log line.
5. IOU-09: WHEN the feature ships THEN `AGENTS.md`, `README.md` (In-App section, snippet, Objective-C block), `CHANGELOG.md` `[0.1.0]`, `.specs/codebase/PUBLIC_SURFACE.txt`, the in-app T21 checklist item 9 and `docs/DEVICE_CHECKLIST.md` SHALL state the new behavior; `PrivacyInfo.xcprivacy` SHALL need no change (no required-reason API, no new data type).

**Independent Test:** `scripts/check-no-url-open.sh` with a temporary mutant, `NottiInAppPrivacyTests`, `NottiInAppURLOpenerTests`.

---

## Design (medium scope, inline)

- **D1 Option flow.** `Notti.Options.opensInAppURLs` → `NottiFacade.initialize(..., opensInAppURLs:)` → `NottiRuntime.setOpensInAppURLs(_:)` → `NottiInAppEngine.setOpensURLs(_:)` (engine queue). It is applied on every valid `initialize`, before the idempotency check, so it is not part of `NottiFacade.Config` and never restarts the core. The engine default is true.
- **D2 Opener.** `Sources/NottiSDK/InApp/Platform/NottiInAppURLOpener.swift`, modelled on `NottiPushPermissionAction`: a pure `static func openableURL(from:) -> URL?`, an injected `Platform.open(URL, completion)` (production `system`: hops to main and calls `UIApplication.shared.open(url, options: [:], completionHandler:)`), and the failure log. `NottiRuntime` builds it from an optional platform (`shared` passes `.system`, tests nil) and hands the engine a port `(URL) -> Void` through `setURLOpenPort`, like the `push_permission` port.
- **D3 Engine.** `handleTap` (engine queue) decides: a `url` link with the option on, a port set and a value `openableURL` accepts is opened; with the option on and a port set but a refused value, one fixed `.debug` line. Order of effects: `emitClick` (the hub queues the listener block on main), the no-listener warning when applicable, `mainDispatcher { close }`, `mainDispatcher { port(url) }`. In production every block is `DispatchQueue.main.async`, so the listener runs before the open.
- **D4 Guard.** `check-no-url-open.sh` and `NottiInAppSourceGuard` take a list of two allowlisted paths.

## Tasks (inline)

| Task | What | Done when | Commit |
| --- | --- | --- | --- |
| T1 | This spec and AD-020 in `STATE.md` (with the RN alignment todo) | Files written | `docs(specs): in-app-open-url spec and AD-020` |
| T2 | Opener, engine, runtime, facade, `Notti.Options`, ObjC mirror, guard script, surface file, Example client and coverage script; tests: validator table, opener platform, engine order/gating/warning, facade option flow, ObjC option, privacy sentinels, guard pin | Full `NottiSDK-Package` test run green, SwiftLint 0, guard scripts green, test counts not lower | `feat(in-app): open http(s) url actions in the browser by default` |
| T3 | README, AGENTS.md, CHANGELOG, in-app spec notes and T21 item 9, DEVICE_CHECKLIST, README snippet with `IntegrationSnippets.swift` | `check-readme-snippets.sh` green | `docs: in-app url actions open in the browser` |

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| IOU-01 | P1: SDK opens web links | Execute | Implementing |
| IOU-02 | P1: SDK opens web links | Execute | Implementing |
| IOU-03 | P1: SDK opens web links | Execute | Implementing |
| IOU-04 | P1: SDK opens web links | Execute | Implementing |
| IOU-05 | P1: Unchanged parts and logging | Execute | Implementing |
| IOU-06 | P1: Unchanged parts and logging | Execute | Implementing |
| IOU-07 | P1: Unchanged parts and logging | Execute | Implementing |
| IOU-08 | P1: Unchanged parts and logging | Execute | Implementing |
| IOU-09 | P1: Unchanged parts and logging | Execute | Implementing |

## Success Criteria

- [ ] On a device, a `url` button with an `https` value opens Safari after the Example listener logged the click; a `deeplink` button opens nothing (in-app T21 item 9).
- [ ] The local `ci.yml` equivalent is green.
