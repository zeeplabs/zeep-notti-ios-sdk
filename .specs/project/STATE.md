# State

**Last Updated:** 2026-10-11
**Current Work:** `package-foundation` DONE 2026-10-10 (Verifier PASS round 6; lessons L-001..L-007). `core-port` Execute DONE 2026-10-10 on branch `feat/core-port` (draft PR #3): T1-T13, one commit each; full gate green after T13: 247 tests (Shared 13, SDK 233, Ext 1), SwiftLint 0, guard scripts, `pod lib lint` (all + Extension), strict device builds. Ported files follow AD-007; fixture values per AD-008. Verifier round 1 FAIL (R1, L4, G2 survived; `validation.md`). Round-1 gaps closed 2026-10-10: `NottiRuntime.defaultsSuiteName` + suite-name test (CORE-09), registration-failure sentinel tests at `.error` (CORE-12, also L6 at that site), initial effective log level test (CORE-13); R1, L4, L6, G2 verified killed; full gate green: 251 tests (Shared 14, SDK 236, Ext 1). Verifier round 2 PASS (draft PR #3, CI green). Round-2 note F2 closed: empty `delivery_id` test (SDKCTR-04, mutant H8 killed), 252 tests (Shared 14, SDK 237, Ext 1). Verifier round 3 PASS (`validate_state.py` exit 0); core-port DONE, merged via PR #3. `public-api` Specify written 2026-10-10 (`spec.md`, API-01..15, decisions in AD-009; `validate_spec.py` exit 0, 1 warning for the open `n` rows). Design and Tasks (T1-T14) approved 2026-10-11. `public-api` Execute DONE 2026-10-11 on branch `feat/public-api`: T1-T14, one commit each; full gate green: 351 tests (Shared 14, SDK 332, ObjC 4, Ext 1), SwiftLint 0, four guard scripts, `pod lib lint` (all + Extension), strict device builds; 58 declarations in `.specs/codebase/PUBLIC_SURFACE.txt`. `traceability.md` written; recorded deviations (T3 recipient capture, T4 key constants, T5 http build rule, T6 runtime fix, T9/T12 ObjC types, T13 surface format) are applied to `spec.md`/`design.md`. Verifier round 1 FAIL (G1, G2, G3), fixes committed, round 2 PASS (public-api DONE, 356 tests). `delegate-integration` Specify, Design and Tasks (T1-T14) approved 2026-10-11 (AD-010). `delegate-integration` Execute done 2026-10-11 on branch `feat/delegate-integration`: T1-T14, one commit each plus two small test commits; full gate green: 465 tests (Shared 14, SDK 444, ObjC 6, Ext 1), SwiftLint 0, five guard scripts, `pod lib lint` (all + Extension), strict device builds of the SDK and the NSE, `scripts/check-hook-linked.sh` spm and pod (local only; CI has not run yet); 68 declarations in `.specs/codebase/PUBLIC_SURFACE.txt`. `traceability.md` written. Verifier pending (no `validation.md` yet); the feature is not done until it passes.

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

**Decision:** The `NottiSDK` privacy manifest declares Coarse Location (opt-in country) and Product Interaction (session telemetry), in addition to RN's Email, Phone and UserDefaults `CA92.1`.
**Reason:** These are data the SDK actually collects and links to the device record. Under-declaring them is an App Store review and LGPD transparency risk.
**Trade-off:** Integrators' App Store privacy labels gain two entries compared to RN 0.6.0. The RN manifest should be aligned in M2.
**Impact:** package-foundation PKG-11; README data-collection section in `example-and-release`.

### AD-006: Cross-target sharing uses `package` access + `-package-name NottiSDK` in the podspec (2026-10-09)

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

---

## Active Blockers

_none_

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

- [ ] (Verifier r1 note, non-blocking) Add a test that exercises the CocoaPods branch of `NottiSDKResources` / `NottiSDKExtensionResources` (today only compiled by `pod lib lint`). Natural home: `example-and-release` (CocoaPods example app).
- [ ] (Verifier r1 note, non-blocking) Assert privacy manifest `NSPrivacyCollectedDataTypePurposes` per type in `PrivacyManifestTests` (AD-005 purposes are only checked by review today).
- [ ] (Verifier r1 note, non-blocking) Run the spec's PKG-06 independent test (throwaway Podfile with app + NSE targets, `pod install` + build) in `example-and-release`.

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
- [ ] (core-port Verifier r1 N7, LGPD — validate internally/legal) Assess declaring `NSPrivacyCollectedDataTypeUserID` (core sends `external_user_id`) and possibly Device ID in `PrivacyInfo.xcprivacy` (AD-005 scope).
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
- [ ] (delegate-integration, backend) `NottiEventStore.enqueue` does not de-duplicate: two silent pushes with the same `delivery_id` queue the `received` report twice (the same as the current `willPresent` path). Verify with the backend whether the events endpoint is idempotent.
- [ ] (delegate-integration, behavior change from D2) A visible push from another SDK without `notification_id` is no longer emitted as `received` to the listener (before, any push with `aps` was). Confirm it is acceptable.
- [ ] (delegate-integration, device) The SwiftUI-internal app delegate check (`NottiAppDelegateSwizzler.isSwiftUIInternal`) is a class-name check, [Incerto]. Validate on a device in `example-and-release` with a SwiftUI app with and without `@UIApplicationDelegateAdaptor`, together with the launch hook in a CocoaPods app (static and dynamic).
- [ ] (delegate-integration, behavior) With swizzling active, `Notti.Notifications.willPresent(_:)` logs one warning and returns the D2 options (not `[]`), so a host that uses the value as its completion still shows a Notti push.
- [ ] (delegate-integration, CI) Draft PR CI has not run for `delegate-integration`: the two `check-hook-linked.sh` steps, `check-no-url-open.sh` and the extended `check-package-graph.sh` are proved locally only. `check-hook-linked.sh pod` checks the Core subspec; a static-library pod (`--use-libraries`) is not covered.
- [ ] (delegate-integration, tests) Test files added in earlier delegate-integration tasks (`NottiMethodSwizzlerTests` and others) emit "inferred to have type AnyClass" compiler warnings in the test build; the device builds (strict) are unaffected. Annotate `: AnyClass` when next touched.
- [ ] (delegate-integration Verifier r1 M5, tooling) `check-no-url-open.sh` bans `UIApplication.shared.open`, `.open(_:options` and `openURL`; its second pattern is selector text real code never contains, so an alias, a multi-line call or `app.open(url, ...)` passes. `grep -rnE "\.open\(|openURL|canOpenURL" Sources` is empty today (DEL-18 holds). A plain `\.open\(` ban would close it; check for legitimate uses first.
- [ ] (delegate-integration Verifier r1 M2, tests) The production binding `installDelegates: { NottiDelegateInstaller.ensureInstalled() }` (`Notti.swift`) is untested; it is the safety net if `+load` does not run. Needs a seam that proves it calls `ensureInstalled` without installing real swizzles in the test process.
- [ ] (delegate-integration Verifier r1 N5/N7/N9, notes) `NottiDeepLinkTests.test_noCallbackOfEitherSwizzlerOpensAURL` is tautological (the script is the real guard); `NottiBootstrap.h` is public in the pod but not in `PUBLIC_SURFACE.txt` (confirm acceptable); late-install path where UIKit may read the app delegate's capabilities before the SDK adds a missing callback is [Incerto] and device-only.

## Preferences

**Model Guidance Shown:** never
