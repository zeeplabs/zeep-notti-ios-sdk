# NSE Rich Media Specification

## Problem Statement

`NottiSDKExtension` is a placeholder (`NottiSDKExtensionModule.version`). The backend already sends `aps.mutable-content: 1` plus a top-level `notti_image_url` (`zeep-notti` `internal/providers/apns/apns.go:133,173`), but nothing on the iOS side downloads the media, so a push with an image shows as plain text. `react-native-notti` 0.6.0 has the helper (`ios/NotificationServiceExtension/NottiNotificationServiceExtension.swift`, 9 tests). This feature ports it into the extension-safe product, with the privacy and timing fixes the SDK rules require.

## Goals

- [ ] A Notification Service Extension that forwards two calls to `NottiNotificationServiceExtension` shows the push with the image, video or audio attached, with no download code in the host.
- [ ] Every failure (bad URL, network, size, type, timeout, expiry) ends in exactly one `contentHandler` call with the original, attachment-less content. The extension never crashes, hangs or calls the handler twice.
- [ ] Only `https` media is fetched, on the first URL and after redirects, capped at 10 MiB.
- [ ] No PII, URL, host or query string reaches a log line (AGENTS.md privacy rules).
- [ ] The extension product stays extension-safe and never depends on `NottiSDK`.

## Out of Scope

| Feature | Reason |
| --- | --- |
| Reporting `received` from the NSE, badge increment, App Group | M3 `nse-shared-state` (Deferred Ideas in `STATE.md`; needs a backend contract review) |
| Action buttons / categories | M3 `notification-action-buttons` |
| More than one attachment, attachment options (thumbnail time, hidden thumbnail), sniffing the type from the bytes | RN 0.6.0 attaches one file and derives the type from the MIME or URL (AD-002, no new behavior) |
| Authenticated downloads, custom headers, signed-URL refresh | The backend contract is one public `https` URL |
| Creating the Xcode target, Podfile/SPM wiring, `@objc(NotificationService)` setup docs, README | `example-and-release`. This feature keeps the wiring snippet in the class doc comment |
| Running the extension in the iOS Simulator | The OS does not run an NSE in the Simulator since Xcode 11.4. Unit tests call the helper directly. End to end needs a device (`example-and-release` checklist) |
| Expo managed workflow | Needs a native target (same limit as RN) |
| Consent gating | `privacy-consent` (post-M1) |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Payload contract | `notti_image_url` (string, https URL), sibling of `aps`, with `aps.mutable-content: 1`. Read through `NottiPayloadKeys.imageUrl` | Backend emits it today [Certo, `apns.go:133,173`]. Frozen key, already in `NottiShared` | y |
| Public API shape | Keep the RN names and labels: `NottiNotificationServiceExtension.didReceive(_:withContentHandler:)` and `serviceExtensionTimeWillExpire(for:contentHandler:)`, both `public static` | Same one-line forwarding as RN, so M2 and integrators migrate without edits | y (Julio, 2026-10-11, Q1) |
| The RN `session:` and `logger:` parameters | Removed from the public signature (source-compatible for callers that omit them). Tests reach an internal overload | RN's default `NSLog` sink logs `error.localizedDescription` (URLs carry ids). A public `logger:` closure is a new public contract nobody asked for | y (Julio, 2026-10-11, Q2) |
| Logging | Through `NottiLogger` only (category `nse`), failures at `.error`, reason as a fixed code or `domain#code`. Never the URL, host, query, title, body or `localizedDescription` | AGENTS.md rule. The NSE has no app state, so the level stays `.error`; `.warn` would never be seen in production. Differs from RN (NSE-13) | y (Julio, 2026-10-11, Q2) |
| Time budget | One deadline for the whole download, 20 s, under the OS budget (~30 s). RN's `URLRequest.timeoutInterval` is an idle timeout between packets, not a total cap, so a slow trickle can run past 30 s [Provável, to prove with a test] | The goal "deliver the handler before the OS kills the process" needs a real total cap | y (proposal, same 20 s value as RN) |
| Expiry | `serviceExtensionTimeWillExpire` cancels the in-flight download, calls the handler once with the best-attempt content, and a late completion never calls the handler again. RN has no cancel, so a late completion could call the handler a second time | Roadmap line: "deliver best attempt on expiry". Needs correlation between the expiry call and its download (Design) | y (behavior), Design spike (how) |
| Size cap | 10 MiB. RN checks the size after the file is on disk, so bytes transferred are bounded only by the time cap | A stricter early abort is P2 (NSE-17). The after-download check stays as the floor | y (Julio, 2026-10-11, Q3: early abort enters M1) |
| MIME handling | Case-insensitive match on `response.mimeType`. Allowed: `image/jpeg`, `image/png`, `image/gif`, `video/mp4`, `audio/mpeg`. Fallback to the URL extension only if in `jpg, png, gif, mp4, mp3`; else `jpg` (iOS may reject it, then the original shows) | RN behavior, except case-insensitive (small, safe deviation) | y |
| Objective-C hosts | `@objc` mirror of the two methods on the class (P2, NSE-16) | NSE templates exist in Objective-C; the app SDK already ships an `@objc` surface (API-12/13). Interop only, no new behavior | y (Julio, 2026-10-11, Q4: enters M1) |
| Privacy manifest | `NottiSDKExtension` keeps `NSPrivacyAccessedAPICategoryFileTimestamp` `C617.1` while the code calls `FileManager.attributesOfItem`. Updated in the same change if that call goes away (PKG-13) | Already declared. Reason code unchanged | y |

Open questions: none. Q1 to Q4 were confirmed by Julio on 2026-10-11 with the recommended answers. NSE-16 and NSE-17 stay P2 in priority but are in M1 scope. The only Design spike is how the expiry call is correlated with its download (Q1); if it cannot be proven safe, the instance-based API comes back to Julio.

---

## User Stories

### P1: Attach the media ⭐ MVP

**User Story**: As an iOS developer, I want one forwarding call in my Notification Service Extension so that a Notti push with `notti_image_url` shows its image, video or audio.

**Why P1**: This is the whole feature. Without it `mutable-content` pushes are plain.

**Acceptance Criteria**:

1. NSE-01: WHEN `userInfo["notti_image_url"]` is a valid `https` URL and the download returns 2xx with an allowed type within budget THEN `didReceive` SHALL call `contentHandler` once with content that has exactly one attachment and every other field (title, subtitle, body, sound, badge, category, thread id, `userInfo`) equal to the original.
2. NSE-02: WHEN the key is missing or not a `String` THEN `didReceive` SHALL call `contentHandler` once with the original content, start no request and write no log line.
3. NSE-03: WHEN the value is not a valid URL or its scheme is not `https` (any other scheme, any case of `HTTPS` is accepted) THEN `didReceive` SHALL start no request, log one `.error` line without the value, and call `contentHandler` once with the original content.
4. NSE-04: WHEN the response final URL (after redirects) is not `https` THEN the helper SHALL discard the downloaded file, attach nothing and call `contentHandler` once with the original content.
5. NSE-05: WHEN the transfer fails, there is no local file, or the status is not 2xx THEN the helper SHALL attach nothing, delete any temp file and call `contentHandler` once with the original content.
6. NSE-06: WHEN the downloaded file is larger than 10 MiB THEN the helper SHALL delete it, attach nothing and call `contentHandler` once with the original content.
7. NSE-07: WHEN the file type is derived THEN it SHALL come from the MIME type (allowlist above, case-insensitive), then from the URL extension if allowlisted, else `jpg`.
8. NSE-08: WHEN `UNNotificationAttachment` rejects the file THEN the helper SHALL delete the moved file, attach nothing and call `contentHandler` once with the original content.
9. NSE-09: WHEN any path ends, successful or not THEN no downloaded file SHALL remain in the temp directory except the one owned by a returned attachment.

**Independent Test**: A test calls `didReceive` with a stub session returning a small PNG and asserts the attachment and the unchanged fields. Each failure above is a separate stub.

---

### P1: Time budget and expiry ⭐ MVP

**User Story**: As an integrator, I want a slow or stalled download to still end with a delivered notification so that a bad CDN never swallows the push.

**Why P1**: The OS kills the extension at ~30 s. A push that never reaches the handler is shown plain by the OS at best, and the SDK cannot clean up.

**Acceptance Criteria**:

1. NSE-10: WHEN the download is still running at 20 s THEN the helper SHALL cancel it and call `contentHandler` once with the original content. A response that keeps sending bytes SHALL NOT extend the deadline.
2. NSE-11: WHEN `serviceExtensionTimeWillExpire(for:contentHandler:)` is called with content while a download is in flight THEN the helper SHALL cancel that download, call the handler once with that content, and SHALL NOT call any handler when the cancelled download completes later.
3. NSE-12: WHEN `serviceExtensionTimeWillExpire` is called with `nil` content THEN it SHALL NOT call the handler (RN parity, Apple template contract).

**Independent Test**: A stub that never finishes plus a short injected deadline proves NSE-10. A stub that never finishes plus a direct expiry call proves NSE-11, counting handler calls after the stub is released.

---

### P1: Privacy, logging and extension safety ⭐ MVP

**User Story**: As a compliance owner, I want the extension to leak nothing and stay inside extension-safe APIs so that it passes App Store review and LGPD review.

**Why P1**: Media URLs can carry tokens and ids. The extension runs without the app, so a mistake is invisible until review.

**Acceptance Criteria**:

1. NSE-13: WHEN the helper logs THEN it SHALL use `NottiLogger` with category `nse`, SHALL NOT include the URL, host, query, payload text or `localizedDescription`, and SHALL write errors as `"\(error.domain)#\(error.code)"`. A sentinel in the URL (path, query, host) and in the title and body SHALL NOT appear in any captured line on any failure path.
2. NSE-14: WHEN the extension product is built THEN it SHALL use no `UIApplication`, no `import UIKit` and no dependency on `NottiSDK`, and `scripts/check-extension-safety.sh`, `scripts/check-package-graph.sh` and the strict device build with `APPLICATION_EXTENSION_API_ONLY=YES` SHALL stay green.
3. NSE-15: WHEN the public surface is listed THEN `NottiNotificationServiceExtension` and its two methods SHALL appear in `.specs/codebase/PUBLIC_SURFACE.txt`, and `scripts/check-public-surface.sh` SHALL pass.

**Independent Test**: The sentinel test runs every failure path and scans the sink. The scripts run in CI.

---

### P2: Hardening and interop

**User Story**: As an integrator with an Objective-C extension, and as an operator who cares about battery and data, I want the cap enforced while downloading and an `@objc` entry point.

**Why P2**: Both are improvements over RN 0.6.0, not parity. Julio confirmed both for M1 (Q3, Q4, 2026-10-11).

**Acceptance Criteria**:

1. NSE-16: WHEN an Objective-C host calls `+[NottiNotificationServiceExtension didReceive:withContentHandler:]` and `+[NottiNotificationServiceExtension serviceExtensionTimeWillExpireFor:contentHandler:]` THEN they SHALL behave as the Swift methods, proven by a test in `NottiSDKObjCTests` or an extension-side Objective-C test target.
2. NSE-17: WHEN the response is larger than 10 MiB (declared length or bytes received) THEN the helper SHALL cancel the transfer as soon as that is known, instead of after the file is complete.
3. NSE-18: WHEN the contract values are tested THEN the key literal `notti_image_url`, the 10 MiB cap, the 20 s deadline and the five allowed types SHALL each be asserted as literals, not through the constants the code reads (lesson from `delegate-integration` G1).

**Independent Test**: NSE-17: a stub declaring 11 MiB is cancelled before any body is read.

---

## Edge Cases

- WHEN `request.content` cannot be copied to a mutable copy THEN `didReceive` SHALL call `contentHandler(request.content)` once (RN behavior).
- WHEN the URL has an uppercase scheme (`HTTPS://`) THEN it SHALL be accepted.
- WHEN the URL has no extension and the response has no MIME type THEN the file SHALL be saved as `jpg`.
- WHEN a redirect chain ends on `https` THEN the media SHALL be attached.
- WHEN `notti_image_url` is an empty string THEN it SHALL count as invalid (NSE-03).
- WHEN the same notification is delivered to two extension instances in one process THEN one instance's expiry SHALL NOT cancel the other's download (Design must show how the expiry call is correlated, see Q1).
- WHEN the `userInfo` carries `notti_image_url` but the push has no `mutable-content` THEN the OS never calls the extension, and nothing in this feature changes that.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| NSE-01 | P1: Attach the media | Specify | Implemented, Verifier pending |
| NSE-02 | P1: Attach the media | Specify | Implemented, Verifier pending |
| NSE-03 | P1: Attach the media (scheme allowlist) | Specify | Implemented, Verifier pending |
| NSE-04 | P1: Attach the media (redirect to non-https) | Specify | Implemented, Verifier pending |
| NSE-05 | P1: Attach the media (transfer and status failures) | Specify | Implemented, Verifier pending |
| NSE-06 | P1: Attach the media (size cap, after download) | Specify | Implemented, Verifier pending |
| NSE-07 | P1: Attach the media (file type) | Specify | Implemented, Verifier pending |
| NSE-08 | P1: Attach the media (attachment init failure) | Specify | Implemented, Verifier pending |
| NSE-09 | P1: Attach the media (no leaked temp files) | Specify | Implemented, Verifier pending |
| NSE-10 | P1: Time budget (total deadline) | Specify | Implemented, Verifier pending |
| NSE-11 | P1: Time budget (expiry, single handler call) | Specify | Implemented, Verifier pending |
| NSE-12 | P1: Time budget (expiry with nil content) | Specify | Implemented, Verifier pending |
| NSE-13 | P1: Privacy, logging and extension safety (no PII in logs) | Specify | Implemented, Verifier pending |
| NSE-14 | P1: Privacy, logging and extension safety (extension-safe) | Specify | Implemented, Verifier pending |
| NSE-15 | P1: Privacy, logging and extension safety (public surface) | Specify | Implemented, Verifier pending |
| NSE-16 | P2: Hardening and interop (`@objc` mirror) | Specify | Implemented, Verifier pending |
| NSE-17 | P2: Hardening and interop (early size abort) | Specify | Implemented, Verifier pending |
| NSE-18 | P2: Hardening and interop (contract literals) | Specify | Implemented, Verifier pending |

Inherited behavior: `react-native-notti` 0.6.0 NSE helper and its 9 tests (`52e4b55`), carried over except where a row above says otherwise. RN has no test for redirect, size cap, transfer error, deadline or expiry races, so NSE-04, 05, 06, 10, 11 are new tests.

**Coverage:** 18 total, 18 mapped to a story, 18 mapped to tasks and to named tests (`traceability.md`).

---

## Success Criteria

- [ ] A stub download of a PNG, JPG, GIF, MP4 and MP3 each ends in one attachment with the original fields intact and one handler call.
- [ ] Every failure path in NSE-02 to NSE-12 ends in exactly one handler call (or none, for NSE-12), proven by counting calls after the stub is released.
- [ ] A sentinel in the URL and in the payload text appears in no log line on any path.
- [ ] No file stays in the temp directory after any path.
- [ ] Extension-safety, package-graph and public-surface scripts stay green, the strict extension device build passes, `pod lib lint` (all and Extension only) stays green, SwiftLint `--strict` stays at 0, and the test count stays at or above 474.
- [ ] End to end on a real device with a real push is listed as unproven until the `example-and-release` checklist runs.
