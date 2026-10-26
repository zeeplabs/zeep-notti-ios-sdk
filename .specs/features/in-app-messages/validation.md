# Validation: in-app-messages - PASS (owner report)

**Result**: PASS on the owner's device report, closed 2026-10-26 by owner decision (Julio); no independent Verifier. Evidence: item 9 recorded in `.specs/project/STATE.md:4` (Current Work); the T21 todo closed at `.specs/project/STATE.md:287`.

## Device checklist (`tasks.md`, "Device validation checklist", items 1-27)

| Item | Result | Evidence |
|------|--------|----------|
| 9 (url, deeplink and `tel:` actions) | Pass | Recorded 2026-10-25 by Julio on a device: an `https` button opened Safari; a `deeplink` button closed the message, reached the click listener and opened nothing; a `url` button with `tel:` opened nothing; the dashboard showed `click` with the right button and no `dismiss` for each. |
| 1-8, 10-27 | Pass (owner report) | Julio reported on 2026-10-26 that he ran every item internally. Device models, iOS versions and the server release were not recorded line by line, so this file does not list them. |

Items that needed extra infrastructure are part of the owner report above and were not observed separately: 14, 22 and 26 (proxy), 16 (legacy no-scene app and iPad), 18 (three CocoaPods consumers), 21 (`push_permission`: the backend has no `MinSDKVersionPushPermission`, see the STATE todo; 0.1.0 ships with that backend limitation) and 23 (RN to native queue carry-over).

## Verifier

Not run as an independent pass. Owner decision (Julio, 2026-10-26): close T21 on the internal test report; a beta tester will run the SDK in a real host app after 0.1.0. A failure found there is handled as a regular bug in a patch release.

## Still unproven on a device ([Provável] in the spec)

These were not observed separately and stay as they are in `spec.md` and `design.md` until the beta confirms them: window level `.alert` against the keyboard, Control Center and PiP; the legacy no-scene fallback window; the cold-start ordering of `initialize`, `trackEvent` and the first session; animation feel.
