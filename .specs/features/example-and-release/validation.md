# Validation: example-and-release - FAIL ❌ (round 5, Opus: 2 Majors, documented; no round 6)

**Status**: the feature is not marked done. Five independent review rounds ran on 2026-10-21 (four Verifier rounds and one Opus review). Round 5 found no Blocker and two Majors; both are documented as limitations plus a backend decision, and no round 6 ran. CI has never run for any of this work (GitHub Actions billing), and the device checklist has not been run, so no EXR is proven beyond "Local" (see `traceability.md`).

Method: each round ran in an isolated worktree, did not trust the author's notes, re-derived claims from `Sources/`, `Example/` and the scripts, and mutation-tested the guards.

## Round 1 (FAIL)

- **B1 Blocker.** Scheme `NottiExample-NoAdaptor` still compiled `USE_ADAPTOR` (target `$(inherited)` pulled it from base settings). Fixed in `56257df`: the flag is per configuration; CI asserts it.
- **M1** checklist steps unreachable (example never initializes at launch). **M2** D07 proves the 20 s deadline, not the OS expiry. **M3** EXR-18 overclaim. **M4** coverage guard blind spots. **M5** README and CHANGELOG network contract and retry rule. Fixed in `56257df` and `c50986b`.
- Minors: manifest purposes, secret-scan reach, `--built` path check, tag `v` prefix, CI timeout and bookkeeping fixed; the secret-scan reach, the date range check (`2026-13-45`), the XcodeGen brew pin and the `iPhone 17` grep stay open as minors.

## Round 2 (FAIL)

- **N1** D09 and D11 misdescribed the SwiftUI-without-adaptor path (the SDK returns early for SwiftUI's internal delegate). **N2** README and CHANGELOG lacked that limitation, which `delegate-integration/spec.md` requires. N3 to N5 minors. Fixed in `4a7146e`.

## Round 3 (conditional FAIL)

- N2, N3, N4 closed; N5 mostly closed; N1 partial.
- **M1** D09's pass criterion (the console warning) is unreachable: the warning is `.warn`, emitted once at launch, and the log level defaults to `error` and is only settable after launch. Fixed: the warning is no longer a criterion; a STATE todo records the missing launch-time log level.
- **M2** D11 exercised the early install path, not the late one in the STATE todo. Fixed: D11 is reworded, says a Pass does not tick that todo, and needs another host app.
- m1 (D11 prerequisite: neither fetch method), m2 (D12 and D13 no longer repeat D11), m3 (README and CHANGELOG say the warning is invisible at the default level; D01 names its scheme), m4 (release text: run `39647738829` only documents the billing block; D11 "Not run" is carried into the changelog step). Fixed.

## Round 4 (FAIL: 1 Major, no Blocker)

- **M1** D09 could not tell whether the SwiftUI class-name check works, yet closed the todo about it: over-install keeps the stored device id and the notification-center delegate delivers `received` and `clicked` either way. Fixed: D09 has a part B (fresh install, "Device id" must stay none, otherwise Fail).
- m1 D17 to D19 cited todos already ticked: wording now "append the result"; new STATE todo for the owner confirmations. m2 D03 has a "Not run" box and keeps the core-port T8 todo open. m3 README and checklist no longer say a SwiftUI app can forward by hand (the fix is the adaptor). m4 D15 needs both `notification_id` and `delivery_id`. m5 README and CHANGELOG state the legacy-only delegate limitation, the SDK-assigned notification-center delegate, and the NSE limits (https, 10 MiB, jpg/png/gif/mp4/mp3). m6 release step lists the stale "not proven" text. m7 key count 30. m8 stale S6 follow-up todo ticked. m10 D10 UI string, static libraries note.
- m9 guard hardening: `check-readme-snippets.sh` rejects malformed and repeated snippet ids; `check-example-config.sh` rejects a repeated sample key, scans `CHANGELOG.md`, matches `CK_`/`RK_` and `NOTTI_APP_ID:`; `check-version.sh` rejects an impossible date. Seven new mutations are killed.
- **Still open (low):** `check-example-coverage.sh` does not understand nested block comments, `"""` strings, `#if false` or an uncalled private function, and `IntegrationSnippets.swift` also satisfies several members, so the guard does not prove a screen reaches the SDK for those; the README snippet guard ignores markers inside `#if false`; `check-version.sh` does not check the README banner on a tag build; `grep -F "iPhone 17"` also matches "iPhone 17 Pro"; the XcodeGen pin follows Homebrew.

## Round 5 (Opus review: FAIL, 2 Majors, no Blocker)

- **M1** README said `logout` "clears the link", but `NottiCore.logout` clears only the local link and email and phone on the backend; the backend keeps `external_user_id` and tags (LGPD risk on shared devices). Fixed in the docs: README line, Known limitations and CHANGELOG.
- **M2** [Provável] every launch registration sends only token and platform, and the backend upsert (checked in `saas/zeep-notti`, main of 2026-10-21) resets `external_user_id` and tags; `react-native-notti` 0.6.0 behaves the same. Not fixable in M1 (port, AD-002): documented as a limitation, new checklist item D21, STATE todo for a backend decision.
- m1 CHANGELOG device-id continuity reasoning (the SDK adopts the backend's id, it does not send the stored one) and D20 rewritten. m2 Xcode minimum (`nonisolated(unsafe)` needs Swift 5.10). m3 NSE unknown media type falls back to `jpg`. m4 retry rule completed. m5 backup disclosure added. m6 backend minimum versions added. m9 traceability, ROADMAP and EXR-20 status corrected. m10 D09 part B has a control (Log shows `initialize: ok` and `permission: granted`).
- **m7 guards:** the coverage guard now requires the `requestPermission(completion:)` call and recognises any modifier before `func`; the snippet guard scans only `Example/App` and `Example/NotificationService`. Three new mutations are killed.
- **Follow-up 2026-10-21 (owner chose the backend fix):** `zeep-notti` AD-039 keeps `external_user_id` and tags on a re-registration that omits them and clears `external_user_id` on `PATCH null` (local commits, 1187 integration tests of the touched packages pass). SDK AD-015: `logout` sends `external_user_id: null`; mutation (empty fields) fails 2 tests. README, CHANGELOG and D21 updated. XcodeGen pinned by checksum; coverage guard handles nested comments, `"""` strings and `#if false`, no longer counts the snippet file, and a SIGPIPE race under `pipefail` was fixed; tag builds reject the release-candidate banner.
- **m8 code:** `ManualForwarding` now requires a real Boolean like the SDK (`<integer>1</integer>` no longer turns manual forwarding on while the SDK still swizzles); new test `test_onlyARealBooleanTrueTurnsManualForwardingOn`. Hosted tests: 35 on the SPM leg.

## Confirmed by the Verifiers (own runs)

- All `scripts/check-*.sh` pass locally and under ubuntu:24.04 with mawk for the text guards.
- Hosted tests: 34 per leg on SPM, pods static, libs and dynamic; the NoAdaptor scheme passes; strict device builds pass.
- Guard mutations are killed (snippets, version, config, coverage).
- README fields, endpoints, retry rule, manifest declarations and the 30 `notti_*` keys match the code.
- No PII, real ids or keys, and no AI co-author lines; every commit is authored by Julio Sousa.

## Not proven

- Everything in CI (the `example` job, the new guards, the NoAdaptor step): billing blocks Actions.
- Every `DEVICE_CHECKLIST.md` item, and the Objective-C README block.
- To finish: fix billing and read a green CI run, run the checklist, run a last Verifier on the final state, then mark the feature DONE.
