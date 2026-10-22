# Release PR text for 0.1.0 (EXR-22)

Paste this as the description of the release PR. The PR itself only sets the CHANGELOG date and flips the README banner; the tag, the GitHub Release and `pod trunk push` stay with Julio.

---

## 0.1.0: pre-tag gates

Do not tag until every box is ticked.

**Proof**
- [ ] CI is green on this PR and on `main` (GitHub Actions billing fixed; push the PR branch and read the new run. Run `39647738829` belongs to the merged PR #11 and only documents the billing block). The `example` job, `check-example-coverage.sh`, `check-example-config.sh`, `check-readme-snippets.sh` and the CHANGELOG check in `check-version.sh` have never run in CI before this PR.
- [ ] `docs/DEVICE_CHECKLIST.md` D01..D21 run on a physical device; each Fail is fixed or carried into the CHANGELOG as a known limitation. D03 (location sharing) and D11 (fetch callback added to a delegate that lacks it) run in a separate host app; the example cannot do either. If they are not run, carry them into the CHANGELOG as unproven.
- [ ] STATE todos cited by the checklist ticked after it passes (EXR-16).
- [ ] `pod lib lint NottiSDK.podspec --platforms=ios` and `pod lib lint NottiSDKExtension.podspec --platforms=ios` pass (also `--use-libraries`).

**Owner decisions**
- [ ] `zeep-notti` with AD-039 (branch `fix/device-upsert-keeps-identity`) is merged and released, and the README names that version as the minimum for `logout` and re-registration (D21 run against it).
- [ ] Device ID privacy-manifest declaration: decided 2026-10-21 (declare). Confirm it stands.
- [ ] Legal or privacy confirms the wording of User ID, Other Diagnostic Data and Other Data Types (D18).
- [ ] AD-014 D4 confirmed one by one: key name `NottiDisableSwizzling`; a visible push without `notification_id` is no longer emitted as `received`; warnings as errors on library builds only.
- [ ] Backend confirms `https://app.zeepnotti.app` as the production default host (confirmed 2026-10-11 per the spec; the STATE todo is still unticked).
- [ ] App Store Connect validation accepts both manifests (no C617.1 in the extension) and the dynamic-framework layout (D17, D19).

**Release steps (Julio)**
1. Flip the README banner from "release candidate" to the released wording, remove the "Not yet proven on a device" bullet (or update it with what the checklist left unproven), update the CHANGELOG wording that says the date is set after the checklist and that device id continuity is not yet verified (D20), and set the CHANGELOG date: replace `[0.1.0] - TBD` with `[0.1.0] - YYYY-MM-DD`. `scripts/check-version.sh` rejects `TBD` on a tag build.
2. Merge this PR.
3. Tag `0.1.0` (no `v` prefix: `check-version.sh` compares the tag with `NottiSDKVersion.current`).
4. Create the GitHub Release from the CHANGELOG section.
5. `pod trunk push NottiSDK.podspec`, then `pod trunk push NottiSDKExtension.podspec`.
