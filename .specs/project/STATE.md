# State

**Last Updated:** 2026-10-21
**Current Work:** `example-and-release` Execute done 2026-10-21 (T1-T12; PR #12 T3-T7, PR #13 T8-T12); five review rounds (`validation.md`; the last, by Opus, found the logout and launch-registration limits), findings fixed or recorded as todos, no PASS yet; CI blocked by billing (see Active Blockers). `package-foundation` DONE 2026-10-10 (Verifier PASS round 6; lessons L-001..L-007). `core-port` Execute DONE 2026-10-10 on branch `feat/core-port` (draft PR #3): T1-T13, one commit each; full gate green after T13: 247 tests (Shared 13, SDK 233, Ext 1), SwiftLint 0, guard scripts, `pod lib lint` (all + Extension), strict device builds. Ported files follow AD-007; fixture values per AD-008. Verifier round 1 FAIL (R1, L4, G2 survived; `validation.md`). Round-1 gaps closed 2026-10-10: `NottiRuntime.defaultsSuiteName` + suite-name test (CORE-09), registration-failure sentinel tests at `.error` (CORE-12, also L6 at that site), initial effective log level test (CORE-13); R1, L4, L6, G2 verified killed; full gate green: 251 tests (Shared 14, SDK 236, Ext 1). Verifier round 2 PASS (draft PR #3, CI green). Round-2 note F2 closed: empty `delivery_id` test (SDKCTR-04, mutant H8 killed), 252 tests (Shared 14, SDK 237, Ext 1). Verifier round 3 PASS (`validate_state.py` exit 0); core-port DONE, merged via PR #3. `public-api` Specify written 2026-10-10 (`spec.md`, API-01..15, decisions in AD-009; `validate_spec.py` exit 0, 1 warning for the open `n` rows). Design and Tasks (T1-T14) approved 2026-10-11. `public-api` Execute DONE 2026-10-11 on branch `feat/public-api`: T1-T14, one commit each; full gate green: 351 tests (Shared 14, SDK 332, ObjC 4, Ext 1), SwiftLint 0, four guard scripts, `pod lib lint` (all + Extension), strict device builds; 58 declarations in `.specs/codebase/PUBLIC_SURFACE.txt`. `traceability.md` written; recorded deviations (T3 recipient capture, T4 key constants, T5 http build rule, T6 runtime fix, T9/T12 ObjC types, T13 surface format) are applied to `spec.md`/`design.md`. Verifier round 1 FAIL (G1, G2, G3), fixes committed, round 2 PASS (public-api DONE, 356 tests). `delegate-integration` Specify, Design and Tasks (T1-T14) approved 2026-10-11 (AD-010). `delegate-integration` Execute done 2026-10-11 on branch `feat/delegate-integration`: T1-T14, one commit each plus two small test commits; full gate green: 465 tests (Shared 14, SDK 444, ObjC 6, Ext 1), SwiftLint 0, five guard scripts, `pod lib lint` (all + Extension), strict device builds of the SDK and the NSE, `scripts/check-hook-linked.sh` spm and pod (local only; CI has not run yet); 68 declarations in `.specs/codebase/PUBLIC_SURFACE.txt`. `traceability.md` written. Verifier pending (no `validation.md` yet); the feature is not done until it passes. `nse-rich-media` Specify, Design and Tasks (T1-T16) approved 2026-10-11 (AD-011). `nse-rich-media` Execute done 2026-10-11 on branch `feat/nse-rich-media`: T1-T16, one commit each plus one fix commit; full gate green: 584 tests (Shared 14, SDK 453, ObjC 6, Ext 108, Ext ObjC 3), SwiftLint 0, six guard scripts plus `check-nse-logging.sh`, `pod lib lint` (all + Extension), strict device builds; 71 declarations in `.specs/codebase/PUBLIC_SURFACE.txt`. `traceability.md` written. Verifier round 1 FAIL (B1 deadline trickle with large chunks, B2 no http request after redirect, B3 race cleanup; tests only, production untouched), fixed in `f9acfd9` (586 tests, Ext 110); round 2 PASS (`validation.md`); nse-rich-media verified. Push, PR and merge pending Julio's approval.

---

## Recent Decisions (Last 60 days)

### AD-001: This SDK is the single source of truth for Notti iOS logic (2026-10-09)

**Decision:** The Swift core currently in `zeep-notti-react-native/ios` is extracted into this repo. In M2, the RN SDK depends on this pod and deletes its own Swift core.
**Reason:** Removes a second Swift implementation (RN's AD-001 already forces Swift + Kotlin duplication). Mirrors OneSignal, where `react-native-onesignal` wraps `OneSignal-iOS-SDK`.
**Trade-off:** RN iOS releases now depend on this SDK's releases. The public API must stay `@objc`-bridgeable for the Turbo Module. Until M2 ships, both copies exist and fixes must be applied twice.
**Impact:** The core port preserves behavior, backend contract and UserDefaults keys exactly. Any behavior change goes through a spec in this repo first.

### AD-002: v1 scope = behavior parity with react-native-notti 0.6.0 (2026-10-09)

**Decision:** M1 ships every iOS behavior RN 0.6.0 has (registration, identity, tags, email/phone, permission, profile fields, session telemetry, received/opened/clicked events, NSE rich media). No new behavior.
**Reason:** Keeps the port verifiable against the existing XCTest suite and spec IDs. New features go in M3.
**Trade-off:** Known RN gaps (no consent API, PII in UserDefaults, no Retry-After) ship in v0.1.0 too.
**Impact:** Feature specs in M1 reference the RN requirement IDs instead of redefining behavior.

### AD-003: Distribution via SPM (source) + CocoaPods (2026-10-09)

**Decision:** Source-based `Package.swift` with two products (app SDK and NSE SDK) plus a podspec.
**Reason:** SPM is the native default; the podspec is required for RN (CocoaPods) consumption in M2. OneSignal's binary-only SPM adds release tooling we don't need yet.
**Trade-off:** Two manifests to keep in sync; CI must build both.
**Impact:** The NSE product must not depend on the app module. Shared code goes in an internal target.

### AD-004: APNs/delegate capture via swizzling with opt-out (2026-10-09)

**Decision:** Swizzling is on by default (OneSignal model). An Info.plist key disables it; a manual forwarding API is always available.
**Reason:** One-line integration for native apps. The RN SDK today requires manual AppDelegate forwarding and taking over `UNUserNotificationCenter.delegate`, which conflicts with other push SDKs.
**Trade-off:** Swizzling is ObjC-runtime work in Swift, fragile across iOS versions and hard to unit test. It must forward to host originals and guard against double-swizzle (OneSignal `SwizzlingForwarder` pattern).
**Impact:** Its own feature (`delegate-integration`) with a dedicated test strategy. Manual calls made while swizzling is active must be ignored with a warning, to avoid double-processing.

### AD-005: Privacy manifest declares more than RN 0.6.0 (2026-10-09)

**Decision:** The `NottiSDK` privacy manifest declares Coarse Location (opt-in country) and Product Interaction (session telemetry), in addition to RN's Email, Phone and UserDefaults `CA92.1`. User ID (the host's `external_user_id`, purpose App Functionality only, linked, no tracking) was added on 2026-10-12 after Julio confirmed the purpose.
**Reason:** These are data the SDK actually collects and links to the device record. Under-declaring them is an App Store review and LGPD transparency risk.
**Trade-off:** Integrators' App Store privacy labels gain two entries compared to RN 0.6.0. The RN manifest should be aligned in M2.
**Impact:** package-foundation PKG-11; README data-collection section in `example-and-release`.

### AD-006: Cross-target sharing uses `package` access + `-package-name NottiSDK` in the podspec (2026-10-09)

> Amended by AD-012 (2026-10-12): the pod is now two root pods; the single-module remark and the subspec lint list below are historical.

**Decision:** Keep the design's primary option. `NottiShared` declarations use `package` access. The podspec sets `pod_target_xcconfig OTHER_SWIFT_FLAGS = '$(inherited) -package-name NottiSDK'`. The `@_spi(NottiInternal)` fallback is not needed.
**Reason:** Spike (package-foundation T1, throwaway in the scratchpad, Xcode 27.0, CocoaPods 1.17.0) with subspecs Shared/Core/Extension and a `package` symbol used from Core and Extension:
- SPM `xcodebuild build -scheme Spike-Package`: BUILD SUCCEEDED.
- `pod lib lint --platforms=ios` (frameworks): passed, 0 warnings.
- `pod lib lint --platforms=ios --use-libraries` (static libraries, the RN default): passed.
- `pod lib lint --platforms=ios --subspec=Extension`: passed.
- Negative control without the flag: fails with `error: the package access level used on 'SharedVersion' requires a package name; set it with the compiler flag -package-name`. So the flag is what makes it work, not a coincidence.
**Trade-off:** Relies on an undocumented-for-CocoaPods compiler flag passed through `OTHER_SWIFT_FLAGS`. The CI `pod-lint` job is the regression guard. Not verified on Xcode 26.x locally; CI (`macos-26`) covers it in T12.
**Impact:** package-foundation T3 onward uses `package`; design.md "Cross-target visibility" stands as written.

### AD-007: Ported files are re-indented to 4 spaces and keep RN's lint exceptions in file-scoped disables (2026-10-10)

**Decision:** Every file ported from `react-native-notti` (`52e4b55`, 2-space indent) is re-indented mechanically to 4 spaces (leading spaces doubled; the RN files have no tabs and no multi-line string literals) and gets a final newline. Verbatim parity is checked with a whitespace-insensitive diff (`diff -w <rn-file> <ported-file>`). SwiftLint rules the RN code itself breaks (e.g. `trailing_comma`, `force_try`, `force_cast`, `identifier_name` for `ms`, `closure_parameter_position`) are disabled for that file only, with a `// swiftlint:disable <rules>` header and a matching `// swiftlint:enable` footer (the footer satisfies `blanket_disable_command`). Only rules that actually fire are listed. The code tokens stay identical to RN.
**Reason:** AGENTS.md requires 4-space indentation and zero SwiftLint violations, and AD-002 requires a token-level verbatim port. Fixing the lint findings in code would add diff lines that are not in the task's allowed change list; relaxing `.swiftlint.yml` would also relax new code (`NottiRuntime`, `public-api`).
**Trade-off:** `git diff`/plain `diff` against RN shows every line as changed; reviewers must use `diff -w`. The disabled rules are real style debt, revisited after M1 together with the `NottiCore` split.
**Impact:** core-port T1–T7 (and later ports). Each ported file starts with a provenance comment naming its RN source.

### AD-008: Ported RN tests keep their fixture values in M1 (2026-10-10)

**Decision:** Tests ported from `react-native-notti` keep their fixture values verbatim (`user@example.com`, `a@example.com`, `a@b.com`, `+5511999999999`, `+10000000000`). Tests written in this repo use `example.invalid` / `fixture` values.
**Reason:** Porting rule 1 (1:1 port) and the values never leave the test process: all requests go to `StubURLProtocol` and no log line carries a value (CORE-12).
**Trade-off:** `a@b.com` (registered domain) and `+5511999999999` (valid São Paulo mobile format) are not reserved test values. AGENTS.md's synthetic-values rule is met by new tests only until the rename.
**Impact:** core-port `traceability.md` section 5. Rename post-M1 (todo), listing each rename in `traceability.md`.

---

### AD-009: public-api facade decisions (2026-10-10)

**Decision:** (1) Listeners are multi-listener with a removable `NottiSubscription`, multiplexed over the core's single handler per type. (2) Every host-facing callback runs on the main thread. (3) `initialize` with the same normalized `appId`/`clientKey`/`baseUrl` is a no-op, and different values rebuild the core. (4) `baseUrl` defaults to the RN default host when omitted, and `requestPermission` is `async` plus a completion-handler variant.
**Reason:** RN parity (`EventSubscription`, `Promise<boolean>`), safety with several host modules, predictable UI threading, and no re-registration on duplicate init (closes N1).
**Trade-off:** New facade code (multiplexer, main-thread hop, config comparison) that M1's "port, not rewrite" rule does not cover, so each piece needs its own tests. The default host is fixed in the binary.
**Impact:** `.specs/features/public-api/spec.md` (API-01..15). The default host must be confirmed with the backend team before v0.1.0.

---

### AD-010: delegate-integration decisions (2026-10-11)

**Decision:** (D1) The fallback `UNUserNotificationCenter` delegate is assigned at the end of launch (`UIApplication.didFinishLaunchingNotification`), not at `+load`, and only when the host left `delegate` nil; an install after launch evaluates it immediately. (D2) With a host delegate that has no `willPresent`, the SDK completes with `[.banner, .list, .sound, .badge]` only for a Notti push (remote push with a non-empty `notification_id`) and with `[]` for anything else (confirmed by Julio, 2026-10-11). The same options are what `Notti.Notifications.willPresent(_:)` returns. (D3) The silent-push `fetchCompletionHandler` variant is not added over a host that has only the legacy method. (D4) A tapped push's `data` (including a link) is passed through untouched and the SDK never opens a URL; `scripts/check-no-url-open.sh` enforces it. Opt-out key: `NottiDisableSwizzling` (Boolean `true` turns swizzling off); the name is a proposal to confirm with Julio because it is public contract.
**Reason:** At `+load` every host's delegate is nil, so assuming it then would override a host that sets it a few milliseconds later. Adding `willPresent` literally would show every foreground notification of the host (local, other SDKs) where iOS showed none. Adding the fetch variant would make UIKit stop calling the legacy method.
**Trade-off:** A legacy-only host gets no silent-push events until it adds the modern method or uses the manual API. A visible push from another SDK without `notification_id` is no longer emitted as `received` (before, any push with `aps` was).
**Impact:** `.specs/features/delegate-integration/spec.md` (DEL-01..18), `design.md`, `traceability.md`. The launch hook is the ObjC target `NottiSDKBootstrap`; the Swift installer is reached by name so there is no dependency cycle.

### AD-011: nse-rich-media decisions (2026-10-11)

**Decision:** (D1) The public `didReceive(_:withContentHandler:)` and `serviceExtensionTimeWillExpire(for:contentHandler:)` lose RN's `session:` and `logger:` parameters; tests use `internal` overloads that take an environment. (D2) A timer enforces 20 s for the whole download (RN's `timeoutInterval` is an inactivity timeout). (D3) Expiry cancels the job and a once-only gate guarantees one handler call. (D4) The download is a delegate-based `URLSessionDownloadTask`, so a non-https redirect and an oversize body are refused early; the post-download checks stay as the second barrier. (D5) The MIME match is case-insensitive. (D6) The facade is an `@objc(NottiNotificationServiceExtension)` `NSObject` subclass with a private `init`, so Objective-C hosts can call it. (D7) Logging only through `NottiLogger` category `nse` at `.error`, with fixed codes and `domain#code`; `scripts/check-nse-logging.sh` bans `NSLog`, `print(`, `debugPrint`, `dump(`, `os_log` and `localizedDescription` in the extension. (D8) `.ephemeral` session, no cache. (D9) File size through `fileSizeKey`; `PrivacyInfo.xcprivacy` unchanged (C617.1 kept). (D10) The expiry call is matched to its job by `userInfo` equality, or by a shared non-empty `delivery_id` when a host changed another key of its best-attempt copy.
**Reason:** An NSE is killed at about 30 s, receives only the host's own content at expiry, and runs without app state; URLSession errors and logs would otherwise carry the media URL (ids, tokens).
**Trade-off:** Two identical pushes (same `userInfo`, no `delivery_id`) in one process are expired together. The registry keeps 16 jobs. The log category is checked on the source text because the logger sink does not carry it.
**Impact:** `.specs/features/nse-rich-media/` (spec NSE-01..18, design, tasks, traceability), new script `scripts/check-nse-logging.sh` in the CI `checks` job, new SPM test target `NottiSDKExtensionObjCTests`, 3 new declarations in `PUBLIC_SURFACE.txt`.

### AD-012: Two root pods instead of subspecs (2026-10-12)

**Decision:** CocoaPods ships two root pods with no subspecs: `NottiSDK` (Shared + SDK + ObjC launch hook, module `NottiSDK`) and `NottiSDKExtension` (Shared + Extension, module `NottiSDKExtension`). Both pass `-package-name NottiSDK` and compile the `NottiShared` sources into their own module. The old `NottiSDK/Core`, `/Extension` and `/Shared` subspecs are gone (nothing was published).
**Reason:** With `use_frameworks!` (dynamic), an app on `NottiSDK` and an NSE on `NottiSDK/Extension` made CocoaPods build two pod targets that both produced `NottiSDK.framework` with module `NottiSDK`, and the app resolved `import NottiSDK` to the extension framework (`cannot find 'Notti' in scope`). Found by the example-and-release spike S6; `pod lib lint` does not catch it. Proved with a scratch app + NSE under dynamic frameworks, static frameworks and static libraries with the real podspecs (hosted tests: hook counts 1, both privacy bundles in the product).
**Trade-off:** Two pods to publish and keep on one version (`check-version.sh` checks both). `NottiShared` is duplicated across the pods; there are no ObjC types in it, Swift symbols are module-qualified, and a process links only one of the two pods per binary. Amends AD-006 (the single-module remark).
**Impact:** `.specs/features/pod-split/`, `NottiSDKExtension.podspec`, `scripts/check-package-graph.sh`, `scripts/check-version.sh`, `scripts/check-hook-linked.sh`, CI `pod-lint`, README, AGENTS.md. The permanent app+NSE consumer is `example-and-release` T7.

### AD-013: in-app-messages decisions (2026-10-18; D7, OQ-2, OQ-5 and the image limits accepted by Julio; the rest proposed; amended 2026-10-19 by Julio)

**Decision:** (D1) The feature is post-M1, listed in M3; it amends `PROJECT.md` (In-App moves from "out of scope" to scope) when it ships. (D2) One `NottiInAppEngine` per process, owned by `NottiRuntime`, on its own serial queue; never on `NottiCore.workQueue`. (D3) UIKit and one dedicated `UIWindow` per display, not SwiftUI. (D4) Three optional hooks in `NottiCore` (session started on the `tryOpen()` branch, session ended, device registered) reuse the SDK's existing session. (D5) A separate non-blocking `NottiInAppApiClient` with `Retry-After`; `NottiApiClient` stays as ported except one `private` to `internal`. (D6) A separate In-App event queue, key `notti_inapp_pending_events`, strict FIFO (impression before click), cap 100, 7 day drop; the CTR queue and its key are untouched. (D7) Link actions leave the SDK through `Notti.InAppMessages.addClickListener`; the SDK never opens a URL and always reports `click` (accepted by Julio, 2026-10-18: the integrator handles `url` and `deeplink`; with no listener the click is reported and nothing opens, README warns; RN adopts the same listener). Also accepted 2026-10-18: `trackEvent` before the fetch remembers distinct names of the session (limit 32) and re-evaluates on arrival; default palette = semantic system colors; image 3 s and 5 MiB. Accepted 2026-10-18 too: single-attempt flush before `eligible` and `eligible` is called even if it fails; events `429` `Retry-After` clamp 1..300 s, 60 s default, up to 3 waits (constants tunable; `eligible` `429` and `408` as amended on 2026-10-19 below); `403` forces no re-registration and keeps the queue. Closed 2026-10-18: OQ-3 (every foreground is a session, existing definition, same as RN; a background-time threshold is future work for both SDKs together), OQ-4 (only the first renderable `session_start` shows, no impression for the others), OQ-7 (`Notti.trackEvent` at the top level in both SDKs), OQ-9 (the visible message survives the background, next fetch skips its id and drops pending `session_start`). No open question remains. Approved 2026-10-18 for RN parity: (a) on `403` (eligible and events) the SDK logs one fixed `.warn`, no ids or values, saying In-App is inactive on this device until the next registration, and the CHANGELOG `[Unreleased]` records the divergence from the contract's "re-register"; (b) the close-control label is an in-code table (`en`, `pt-BR`, fallback English), with no `resource_bundles`, `Localizable.strings` or `defaultLocalization`, so packaging does not change and the CocoaPods lproj risk is gone. OQ-6 (server release) stays recorded as a dependency. Amended 2026-10-19 (Julio, review decisions applied to both SDKs): (1) `margin: true` or absent is a 16 pt inset measured from the safe-area edge, `margin: false` touches the safe-area edges on all sides and never goes under the notch, status bar or home indicator, `center` ignores it. (2) The "inactive until the next registration" `.warn` is logged only on `403` (eligible and events); `401` stops fetch and flush for the session, keeps the queue, forces no re-registration and logs only a generic fixed code. (3) The VoiceOver escape gesture closes `center` and `full` messages as `close_button`; iOS has no Android Back equivalent (design parity note). (4) `trackEvent` cold-start window: names after `initialize` and before the first session of the process are remembered (32 cap) for that session through the engine flag `awaitingFirstSession` (D12); names before `initialize` or in the background after a session ran are ignored; [Provável] ordering to confirm on a device. (5) `eligible` `429`: `Retry-After` over 60 s gives up for the session, otherwise wait max(1, value) s (60 s when absent or invalid), at most 3 waits; events keep the 1..300 s clamp. (6) A late `eligible` response after the session ended is discarded. (7) A re-initialize with a different app id, client key or base URL resets the engine, invalidates in-flight responses and tears a visible display down with no event; queue records carry a required `app_id`, the flush sends only the current app's and a config change purges the others (D13). (8) `408` is transient (same policy as 5xx) on both routes. (9) IAM-16 renderability stays as the reference for RN. Open questions OQ-1..OQ-9 and the parity list with the RN spec are in the feature's `spec.md` and `design.md`.
**Reason:** The contract (`zeep-notti` `in-app-messages.mdx`) is server-driven, forbids a local "already shown" state and requires reliable impressions in order; `NottiApiClient` blocks the core queue for minutes and ignores `Retry-After`; `check-no-url-open.sh` bans opening URLs; the CTR queue key is an RN continuity contract.
**Trade-off:** A second queue and a second client to maintain; head-of-line blocking by a failing queue head is accepted for ordering (bounded by the 7 day drop and the cap); an app with no click listener never opens a link (documented); three call lines added to a ported file.
**Impact:** `.specs/features/in-app-messages/{spec,design,tasks}.md`, new public surface (`Notti.trackEvent`, `Notti.InAppMessages`, `NottiInAppClick`, `NottiInAppAction`, ObjC mirrors), `scripts/check-public-surface.sh` allowlist, `PrivacyInfo.xcprivacy` comment only. RN and iOS specs must agree on the parity list before either ships.

---

### AD-015: logout unlinks the device on the backend (2026-10-21)

**Decision:** `Notti.logout()` also sends `PATCH {external_user_id: null}` through the same path as `login` (queued until registration, not retried, dropped before `initialize`), before the email and phone clears. The backend side is `zeep-notti` AD-039 (branch `fix/device-upsert-keeps-identity`, not merged at the time of writing), which also makes a registration that omits `external_user_id` and `tags` keep them. Owner choice 2026-10-21: fix in the backend, not by re-sending the stored link from the SDK.
**Reason:** The round 5 review found that `logout` left the device linked to the previous user on the backend (pushes for that user kept arriving on a shared device; LGPD) and that every launch registration reset the link and tags.
**Trade-off:** SPEC_DEVIATION from `react-native-notti` 0.6.0 (AD-002 port rule): the iOS SDK now sends one more PATCH on logout. A backend without AD-039 answers 200 and keeps the value, so the call is safe but cannot tell the two apart. RN should adopt the same call. Tags still survive logout.
**Impact:** `NottiCore.logout`, `NottiCoreTests` and `NottiFacadeProfileTests` (assertions on the null), README and CHANGELOG limitations, `DEVICE_CHECKLIST` D21.

### AD-014: Pre-0.1.0 owner calls on privacy and public contract (2026-10-21)

**Decision:** (D1) The `NottiSDK` manifest also declares Device ID (push token and backend device id), Other Diagnostic Data (app/sdk version, OS, model, timezone, language, push-permission status) and Other Data Types (host tags), all linked, no tracking, App Functionality. Declaring Device ID confirmed by Julio. (D2) `NottiSDKExtension` drops `NSPrivacyAccessedAPICategoryFileTimestamp` C617.1: the code uses `fileSizeKey` only and no timestamp API remains (grep of `Sources`). (D3) `NottiBootstrap.h` stays public (the module map needs it), outside semver; `check-public-surface.sh` fails if another public ObjC header or any other `@interface`/`@protocol` appears there. (D4) Proposed, awaiting Julio: keep the Info.plist key `NottiDisableSwizzling`; accept that a visible push without `notification_id` is no longer emitted as `received`; warnings-as-errors on library builds (device and simulator) in the `example` CI job, not yet on test targets.
**Reason:** Under-declared data is an App Store review and LGPD transparency risk; an unused required-reason declaration is inaccurate; the surface script scans Swift only, so the ObjC header was unguarded.
**Trade-off:** The two "Other" categories are a best fit for fields Apple's list does not name [Incerto]; privacy/legal should confirm. Dropping C617.1 relies on App Store validation of a real build (to check in `example-and-release`).
**Impact:** both `PrivacyInfo.xcprivacy` and their tests, `scripts/check-public-surface.sh`, CHANGELOG notes for D4.

## Active Blockers

- **GitHub Actions does not start any job (found 2026-10-21).** Every job of PR #11 failed in 3 to 7 s with no steps: "The job was not started because recent account payments have failed or your spending limit needs to be increased" (run `39647738829`). Not a code failure. PR #11 was merged with `--admin` knowing CI had not run. Nothing from `example-and-release` has run in CI: the `example` job, `check-example-coverage.sh`, `check-example-config.sh`, `check-readme-snippets.sh` and the CHANGELOG check in `check-version.sh`. Julio fixes billing (Settings > Billing and plans); then `gh run rerun 39647738829`, and run CI on PR #12 and on `main`. Whether it is a refused payment or a spending limit, and whether other repos are affected, is [Incerto].

---

## Lessons Learned

This repo's lessons live in `.specs/LESSONS.md` (managed by `lessons.py`; L-001..L-003 from the package-foundation Verifier, 2026-10-09). Candidate lessons inherited from the RN repo (`../zeep-notti-react-native/.specs/LESSONS.md`) apply as guidance only:

- RN L-001: test the layer that implements the acceptance criterion, not just the facade that calls it
- RN L-002: the Verifier re-derives proof of properties and does not trust task notes

delegate-integration Verifier round 1 (candidate lessons, not yet in `.specs/LESSONS.md`):

- A constant that tests read does not prove the constant's value: a public contract string (an Info.plist key) is asserted as a literal, and one test builds the input with the literal.
- A dependency injected in tests needs one test of the production binding (`NottiFacade.shared` with `NottiSwizzlingState.shared`), or a wrong wiring passes every test.
- An acceptance criterion verified "by review" needs a grep check or a test (DEL-14: `scripts/check-launch-hook-purity.sh`).

---

## Quick Tasks Completed

| #   | Description | Date | Commit | Status |
| --- | ----------- | ---- | ------ | ------ |

---

## Deferred Ideas

- [ ] NSE reports `received` in the background through an App Group (needs a backend/contract review). Captured during: project init
- [ ] Badge increment in the NSE. Captured during: project init
- [ ] Privacy consent gating API (`setConsentRequired` / `setConsentGiven`) and a local data wipe. Captured during: project init
- [ ] Keychain storage for email/phone (LGPD). Captured during: project init
- [ ] Binary xcframework distribution. Captured during: project init

---

## Todos

- [x] Pod/package name: `NottiSDK` (Julio, 2026-10-09). NSE product `NottiSDKExtension` confirmed (2026-10-09). License MIT.
- [x] `git init` (branch `main`, 2026-10-09).
- [x] GitHub remote `origin` = `git@github.com:zeeplabs/zeep-notti-ios-sdk.git` (2026-10-09).
- [x] Swift 5 language mode for M1; Swift 6 strict concurrency deferred (2026-10-09).
- [x] RN `sdk-core-v1` "Needs Fix" item (native prerequisite path, SDK-04) carried into core-port: CORE-08, task T9.

---

- [x] Privacy manifest scope: see AD-005.
- [x] Spike result: CocoaPods honors `-package-name` via `OTHER_SWIFT_FLAGS`. See AD-006.

- [x] Independent Verifier for package-foundation: PASS in round 6 (2026-10-10), `validation.md` committed; `validate_state.py` exit 0.
- [ ] Note: core-port task ids were renamed `C1..C13` → `T1..T13` (2026-10-09) to match the template; older notes and commits may still say `C<n>`.

- [ ] (Verifier r1 note, non-blocking; narrowed 2026-10-21, example-and-release T7) Narrowed: `ProductIntegrationTests` proves the built pod products ship `NottiSDK_Privacy.bundle` and `NottiSDKExtension_Privacy.bundle` (static frameworks, static libraries, dynamic frameworks) with the manifests. Still open: nothing runs the CocoaPods branch of `NottiSDKResources` / `NottiSDKExtensionResources` itself (internal); it would need a podspec `test_spec`, out of scope for `0.1.0` (Julio, 2026-10-12).
- [ ] (Verifier r1 note, non-blocking) Assert privacy manifest `NSPrivacyCollectedDataTypePurposes` per type in `PrivacyManifestTests` (AD-005 purposes are only checked by review today).
- [x] (Verifier r1 note; closed 2026-10-21, example-and-release T7) PKG-06 independent test: the example app on `pod 'NottiSDK'` plus the NSE on `pod 'NottiSDKExtension'` passes `pod install`, the hosted tests and a strict generic device build under `use_frameworks! :linkage => :static`, `use_modular_headers!` and `use_frameworks!`.

- [ ] (Verifier r5/r6 note, non-blocking) PKG-04: the simulator compile inside `xcodebuild test` does not treat warnings as errors (only device builds and `pod lib lint` do). Decide whether to add the flags to the test step.
- [x] (Verifier r5/r6 note, core-port; done in T11: `NottiLoggerTests.test_messageAtLevelNoneIsNeverEmittedEvenAtVerbose`) `NottiLogger.log` drops `.none` messages via a guard that no test covers; add the test with CORE-12/13 (core-port T11).
- [x] (core-port T7; partly done in T11: one `.error`, `.warn` and `.debug` site asserted in `NottiLoggingPrivacyTests`; the other 21 levels stay review-only) The 24 `NottiCore` log levels are not asserted by any test (the ported RN tests check message text only). Cover at least one `.error`, `.warn` and `.debug` site in T11, or record why not.
- [ ] (core-port T5) The semaphore-backstop `NottiApiClientTimeoutError` is a private Swift struct, so its `domain#code` failure text is the bridged Swift type name instead of RN's "Notti API request timed out". No PII; revisit wording post-M1 if it hurts diagnostics.
- [x] (core-port T2-T7; decided in T13 as AD-008) Ported RN tests keep their fixture values verbatim (`user@example.com`, `+5511999999999`, `+10000000000` in `NottiCoreTests`). They are reserved/synthetic, but not the `example.invalid` / `fixture` style AGENTS.md asks for in new tests. Decide in T13 whether to rename them (each rename listed in `traceability.md`).
- [ ] (AD-007, post-M1) Remove the file-scoped SwiftLint disables in ported files (`trailing_comma`, `force_try`, `force_cast`, `identifier_name`, `large_tuple`, `closure_parameter_position`, `line_length`, `cyclomatic_complexity`, `function_parameter_count`, `unneeded_synthesized_initializer`, `static_over_final_class`, `file_length`, `type_body_length`) together with the `NottiCore` split.

- [ ] (AD-008, post-M1) Rename the RN fixture values in ported tests (`a@b.com`, `+5511999999999` first) to `example.invalid` / `fixture` values; list each rename in core-port `traceability.md`.
- [ ] (core-port T8) `NottiPlatformProviders.live()` closures (APNs registration, permission prompt, `CLGeocoder`, `UIDevice`) are build-verified only; exercise them on a device in `example-and-release`.

- [x] (core-port Verifier r2 F1, closed in public-api T10) `PublicApi.test_productionFacadeReadsTheDeviceIdFromTheNottiPrefsSuite` reads the real `notti_prefs` suite through `Notti.deviceId`; the mutant that renames the suite in `NottiRuntime.shared` fails it.
- [x] (core-port Verifier r1 N1, closed in public-api T5, AD-009) `NottiFacade.initialize` compares the normalized config and skips `runtime.start` on an identical one (`NottiFacadeInitializeTests`). `NottiRuntime.start` still always rebuilds, by design.
- [x] (core-port Verifier r1 N7, LGPD) `NSPrivacyCollectedDataTypeUserID` declared 2026-10-12 (App Functionality, confirmed by Julio). Still open, not a blocker: whether Device ID (device id / push token) must be declared [Incerto]; internal/legal confirmation of the declaration text before `0.1.0` is advisable.
- [ ] (public-api T6, note for the Verifier) `NottiRuntime.invalidateCurrentCore` now keeps a replaced core alive until its queue drains (bounded 60 s wait on a utility thread): work queued on the ensured core (a pre-initialize `setEmail`) was lost when `start` replaced it, because queued core blocks capture `self` weakly. Test: `NottiRuntimeTests.test_aMutationQueuedOnTheEnsuredCoreSurvivesStartReplacingIt`, `NottiFacadeProfileTests.test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration`. No ported core file changed.
- [ ] (public-api T3, note) `NottiListenerHub` snapshots the recipients when the event is received, not when the main block runs, so the replay inside `attach` reaches only the first listener. A listener removed before its turn is still skipped.
- [ ] (public-api T12, note) `NottiSubscription` inherits `NSObject` for ObjC; ObjC payloads are `NSDictionary`; the ObjC classes (`NottiObjC`, `NottiUserObjC`, `NottiNotificationsObjC`) are visible to Swift too. Revisit whether to hide them from Swift (post-M1).
- [ ] (public-api, before v0.1.0) Backend team confirms `https://app.zeepnotti.app` is still the production default host (AD-009).
- [x] (core-port Verifier r3 F7, closed in delegate-integration T4) `NottiPushAdapterTests.test_didReceiveWithAnEmptyDeliveryIdQueuesNoReport` covers the empty `delivery_id` on the `didReceive` path.
- [ ] (public-api Verifier r2 N8/N2, tests) Assert the call count of the ObjC `deviceIdChanged` listener (`NottiObjCBridgeTests.swift:157-173` reads `.first`, never `count`; mutant B33 survives) and give the ObjC `logout`, `setPhone`, `clearEmail`, `clearPhone`, `removeTag` entry points a test that fails when they become no-ops (B12, B20-B23).
- [ ] (public-api Verifier r2 N15, tests) The pre-initialize test for login/logout/tags/subscription only asserts that the core exists; assert the effect (nothing sent, nothing persisted that should not be).
- [ ] (public-api Verifier r1 N1/r2, tests) The race tests for `initialize` and `ensureCore` are probabilistic; lock-removal mutants F07 and R09 survive. Decide whether a deterministic seam is worth it.
- [ ] (public-api T6, post-M1) `NottiRuntime.invalidateCurrentCore` keeps a replaced core alive up to 60 s on one utility thread each. Replace the blocking wait by queueing a no-op on the old core's `workQueue`; also decide whether the old core may still fire `onDeviceIdChanged` for new listeners.
- [ ] (public-api Verifier r1/r2 N3, N9-N13, tooling) `check-public-surface.sh` blind spots: lone `public` on its own line, `public indirect enum`, attribute inside a trailing comment, top-level `public func`/`let` (not a type), `@available(..., unavailable, message:)` false fail, silent allowlist edits. None affects a type that exists today.
- [ ] (public-api Verifier r1 N4, tests) The ObjC test target and the F1 test write to the simulator's real `notti_prefs` suite and undo it afterwards; consider an injectable suite for the ObjC target.
- [ ] (public-api, post-M1) Decide whether `NottiObjC`, `NottiUserObjC` and `NottiNotificationsObjC` should be hidden from Swift (they are visible today).
- [x] (public-api) Default host `https://app.zeepnotti.app` confirmed as the production host by Julio (2026-10-11); the facade default comes from the RN TS constant.
- [ ] (delegate-integration, confirm with Julio) The Info.plist key `NottiDisableSwizzling` is a public contract. It is a proposal; confirm the name before v0.1.0.
- [ ] (delegate-integration, known limit) An app delegate or UN delegate that overrides a callback and calls `super`, or forwards to another swizzled delegate, makes the SDK observe the callback twice (both implementing classes are swizzled). Only subclasses that do not override are proven (`AD.test_aSubclassOfASwizzledDelegateClassIsObservedOncePerCallback`, `CS.test_aSubclassOfASwizzledDelegateClassIsObservedOnce`). Not fixed here.
- [x] (delegate-integration, backend; checked 2026-10-12 in `saas/zeep-notti`, branch `feat/dashboard-i18n`, code only) `NottiEventStore.enqueue` does not de-duplicate, and neither does the backend: `RecordEvent` (`internal/notifications/events.go`) inserts into `notification_events` with no `ON CONFLICT` and the index on `(delivery_id, type)` is not unique, so a repeated `received` adds a row and returns success. Metrics are unaffected: `AggregateMetrics` and `overview/analytics.go` use `EXISTS` / `COUNT(DISTINCT device_id)`. Not a `0.1.0` blocker; optional backend cleanup (partial unique index plus `ON CONFLICT DO NOTHING`).
- [x] (nse-rich-media design risk, backend; checked 2026-10-12) The worker always sets `data["delivery_id"]` (`internal/notifications/worker.go`, after `stringifyData`; integrator-supplied `delivery_id` is stripped by `reservedDataKeys`), silent pushes included, and APNs flattens `data` to top-level keys. The double-handler risk after expiry with a host-mutated `userInfo` does not apply to worker-sent pushes. Pushes sent outside the worker (manual APNs tests) may lack it [Provável]. Also confirmed: `aps.mutable-content: 1` only with an image; `notti_image_url` set after `payload.Data`, so it is never shadowed.
- [ ] (delegate-integration, behavior change from D2) A visible push from another SDK without `notification_id` is no longer emitted as `received` to the listener (before, any push with `aps` was). Confirm it is acceptable.
- [ ] (delegate-integration, device) The SwiftUI-internal app delegate check (`NottiAppDelegateSwizzler.isSwiftUIInternal`) is a class-name check, [Incerto]. Validate on a device in `example-and-release` with a SwiftUI app with and without `@UIApplicationDelegateAdaptor`, together with the launch hook in a CocoaPods app (static and dynamic).
- [ ] (delegate-integration, behavior) With swizzling active, `Notti.Notifications.willPresent(_:)` logs one warning and returns the D2 options (not `[]`), so a host that uses the value as its completion still shows a Notti push.
- [ ] (delegate-integration, CI) Draft PR CI has not run for `delegate-integration`: the two `check-hook-linked.sh` steps, `check-no-url-open.sh` and the extended `check-package-graph.sh` are proved locally only. `check-hook-linked.sh pod` checks the Core subspec; a static-library pod (`--use-libraries`) is not covered.
- [ ] (delegate-integration, tests) Test files added in earlier delegate-integration tasks (`NottiMethodSwizzlerTests` and others) emit "inferred to have type AnyClass" compiler warnings in the test build; the device builds (strict) are unaffected. Annotate `: AnyClass` when next touched.
- [ ] (delegate-integration Verifier r1 M5, tooling) `check-no-url-open.sh` bans `UIApplication.shared.open`, `.open(_:options` and `openURL`; its second pattern is selector text real code never contains, so an alias, a multi-line call or `app.open(url, ...)` passes. `grep -rnE "\.open\(|openURL|canOpenURL" Sources` is empty today (DEL-18 holds). A plain `\.open\(` ban would close it; check for legitimate uses first.
- [ ] (delegate-integration Verifier r1 M2, tests) The production binding `installDelegates: { NottiDelegateInstaller.ensureInstalled() }` (`Notti.swift`) is untested; it is the safety net if `+load` does not run. Needs a seam that proves it calls `ensureInstalled` without installing real swizzles in the test process.
- [ ] (delegate-integration Verifier r1 N5/N7/N9, notes) `NottiDeepLinkTests.test_noCallbackOfEitherSwizzlerOpensAURL` is tautological (the script is the real guard); `NottiBootstrap.h` is public in the pod but not in `PUBLIC_SURFACE.txt` (confirm acceptable); late-install path where UIKit may read the app delegate's capabilities before the SDK adds a missing callback is [Incerto] and device-only.
- [ ] (nse-rich-media, device) End to end on a real device with a real push: `notti_image_url`, the `@objc(NotificationService)` wiring and the two forwarding calls. An NSE does not run in the Simulator; add to the `example-and-release` checklist.
- [ ] (nse-rich-media, known limit) A process killed mid-download leaves an orphan file in `temporaryDirectory/notti-media`. The OS purges the temp area; no cleanup sweep exists (it would need file dates).
- [x] (nse-rich-media, D9; resolved 2026-10-21, AD-014 D2: declaration dropped; App Store validation of a real build still to confirm) `PrivacyInfo.xcprivacy` over-declaration: `NSPrivacyAccessedAPICategoryFileTimestamp` C617.1 stays declared although the code now uses `fileSizeKey`. Confirm in App Store validation of a real build (`example-and-release`) that it is accepted, or drop the declaration if no file-timestamp API remains.
- [ ] (nse-rich-media, CI) The new `checks` step `check-nse-logging.sh` and the new `NottiSDKExtensionObjCTests` target have not run in CI yet; `check-hook-linked.sh spm|pod` results are in the T16 commit.
- [ ] (core, found 2026-10-12 via CI flake) `NottiRuntime.start` replacing the ensured core: if the old core's queue runs after the new core's registration resync, the held-email PATCH is skipped (email is persisted, but the PATCH goes out only on the next registration or `setEmail`, so DPF-19 convergence is late, not lost). Very unlikely in production (registration needs a network round trip). Reproduced only with an instant stub under CPU load. M1 is a port (AD-002): decide in a post-M1 spec. Other tests using `drain(runtime.core)` after a core replacement may have the same race (not audited).
- [ ] (tests, lesson candidate) The first `UNNotificationAttachment` in a process on a clean simulator takes about 20 s; `JobTestCase` now warms it up once. Tests that wait on a first-use system service need a warm-up outside the timed wait.
- [ ] (nse-rich-media, Verifier r2 N6) Mutant w3 (one-shot deadline extension by time to first byte) survives; tighter bound would be flaky. Non-blocking.
- [ ] (nse-rich-media, Verifier r2 N7) No test redirects https to https to http; guard is stateless per hop. Add a two-hop test.
- [ ] (nse-rich-media, Verifier r1 N1/N2/N3) l4 job-level URL-extension fallback wiring and t8 live URLSession config untested; `check-nse-logging.sh` false negatives (`//` in string, `let f = print`, `fputs`, `os.Logger`) and no committed test. Doc snippet says `import NottiSDKExtension` (SPM name; CocoaPods module is `NottiSDK`).

- [ ] (example-and-release T10, CI) The `example` job and the three new guards have never run in CI (Active Blockers). Until they do, `tasks.md` T10 stays open, and no todo is closed on CI evidence. The SPM leg's shell logic was run locally.
- [ ] (example-and-release T9, example gap) The example has no `NSLocationWhenInUseUsageDescription` and never requests location permission, so `DEVICE_CHECKLIST` D03 (geocoder and location sharing) cannot run in it. Add a usage string and a request button to the example (host-side code; the SDK never asks), or run D03 in another host app, or carry it as an unproven limitation.
- [ ] (example-and-release T9, example gap) `Example/project.yml` and `project-pods.yml` hard-code `invalid.example.notti.app` bundle ids and an empty team, and target settings override an xcconfig, so a device run needs a local Xcode edit that regenerating resets. Consider reading both from `Example.local.xcconfig`.
- [ ] (example-and-release T10, tooling) XcodeGen is pinned by `brew install xcodegen` plus a version assertion (`XCODEGEN_VERSION` in `ci.yml`), so the job fails when Homebrew serves a newer one. Switch to a pinned release asset with a checksum if that gets noisy.
- [ ] (example-and-release T8, docs) The Objective-C block in `README.md` is not compiled by CI (the example has no ObjC target); the names come from `@objc(...)` in `NottiObjC.swift`. Add an ObjC target or a compile check if the block drifts.
- [ ] (example-and-release T11, release) `CHANGELOG.md` `[0.1.0]` has the date `TBD`; `check-version.sh` rejects `TBD` on a tag build. Set the date on release day. The release PR text with the pre-tag gates is in `.specs/features/example-and-release/release-pr.md`.

- [ ] (example-and-release T9, SDK gap) The SwiftUI-without-adaptor warning is emitted once at launch at level `warn`, and the log level defaults to `error` and is only settable after launch, so an integrator never sees it. A launch-time log level (Info.plist key or launch argument) needs a spec first (AD-001); until then the README states the limitation.
- [ ] (example-and-release, owner confirmations after the device checklist) Append results to the already-ticked todos: App Store validation of both manifests and of the C617.1 removal (D17), legal wording of the User ID, Other Diagnostic Data and Other Data Types labels (D18), and App Store acceptance of the dynamic-framework layout (D19). Open until Julio runs them.
- [x] (example-and-release, backend decision, found by the round 5 review 2026-10-21; decided and implemented 2026-10-21, AD-015 and zeep-notti AD-039) `logout` now sends `external_user_id: null`; the backend keeps the link and tags on a re-registration that omits them. Still open: release the backend change (branch `fix/device-upsert-keeps-identity` in `saas/zeep-notti`, local commits only, full `make test-integration` before push) and port the logout call to `react-native-notti`.
- [ ] (example-and-release, docs) README states Xcode 15.3 or later because `NottiRichMediaJob.swift` uses `nonisolated(unsafe)` (Swift 5.10); `Package.swift` still says tools 5.9. Only Xcode 26.6 and 27.1 are tested. Decide the supported minimum and add a CI leg or lower the requirement.
- [ ] (example-and-release, docs) The README does not document the NSE's fallback of an unknown media type to `jpg` beyond one sentence, nor `Notti.Options(baseUrl:)` validation (http vs https). Add if integrators ask.
## Preferences

**Model Guidance Shown:** never
- [x] (example-and-release T1 spike S6, found 2026-10-12; closed 2026-10-21, T7) CocoaPods dynamic frameworks failed with the subspec layout. Fixed by the two-pod split (AD-012, PR #8); T7 proves it: static frameworks, static libraries and dynamic frameworks all pass the hosted tests (hook counts 1, both privacy bundles in the product) and a strict device build. Layout fact for dynamic frameworks: CocoaPods embeds `NottiSDK.framework` and `NottiSDKExtension.framework` both in the app's `Frameworks/`, and the extension reaches its own through `@executable_path/../../Frameworks` (asserted by `test_extensionCanReachASharedFrameworkInTheApp`). Whether the App Store accepts an extension that loads a framework from the host app is [Incerto]; confirm on a real archive (`DEVICE_CHECKLIST`).
- [x] (S6 follow-up, 2026-10-12; closed 2026-10-21: shipped as AD-012, PR #8) Option B was prototyped in a scratch dir and passes under dynamic frameworks (design S6b): two root pods `NottiSDK` and `NottiSDKExtension`. Needs its own spec (packaging change, AD-001): drop the `Extension` subspec, add `NottiSDKExtension.podspec`, update `check-version.sh` (two podspecs), `check-package-graph.sh`, CI `pod lib lint` x2, README and `pod trunk push` x2. Awaiting Julio's go-ahead.
