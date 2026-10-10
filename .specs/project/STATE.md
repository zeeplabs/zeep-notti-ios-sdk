# State

**Last Updated:** 2026-10-10
**Current Work:** `package-foundation` DONE 2026-10-10 (Verifier PASS round 6; lessons L-001..L-007). `core-port` Execute DONE 2026-10-10 on branch `feat/core-port` (not pushed): T1-T13, one commit each; full gate green after T13: 247 tests (Shared 13, SDK 233, Ext 1), SwiftLint 0, guard scripts, `pod lib lint` (all + Extension), strict device builds. Ported files follow AD-007; fixture values per AD-008. Verifier round 1 FAIL (R1, L4, G2 survived; `validation.md`). Round-1 gaps closed 2026-10-10: `NottiRuntime.defaultsSuiteName` + suite-name test (CORE-09), registration-failure sentinel tests at `.error` (CORE-12, also L6 at that site), initial effective log level test (CORE-13); R1, L4, L6, G2 verified killed; full gate green: 251 tests (Shared 14, SDK 236, Ext 1). Next: independent Verifier round 2, then PR.

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

## Active Blockers

_none_

---

## Lessons Learned

This repo's lessons live in `.specs/LESSONS.md` (managed by `lessons.py`; L-001..L-003 from the package-foundation Verifier, 2026-10-09). Candidate lessons inherited from the RN repo (`../zeep-notti-react-native/.specs/LESSONS.md`) apply as guidance only:

- RN L-001: test the layer that implements the acceptance criterion, not just the facade that calls it
- RN L-002: the Verifier re-derives proof of properties and does not trust task notes

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

## Preferences

**Model Guidance Shown:** never
