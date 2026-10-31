# Wrapper Support (0.2.0) Tasks

**Spec**: `.specs/features/wrapper-support/spec.md`
**Design**: `.specs/features/wrapper-support/design.md` (approved by Julio, 2026-10-31)
**Testing**: `.specs/codebase/TESTING.md`
**Status**: Draft

---

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill (pinned in `.claude/skills/`) and `AGENTS.md`. One commit per task, conventional style, no AI attribution. Work on a feature branch; push and PR only with Julio's OK. One `xcodebuild` at a time on this machine.

---

## Test Coverage Matrix

> Baseline (2026-10-31, `main` `3d1cad6`, six full runs): Shared 14, SDK 907, ObjC 8, Extension 110, ExtensionObjC 3. Counts below are minimum additions per task.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| --- | --- | --- | --- | --- |
| Core profile sync + store (`NottiCore`, `NottiDeviceStore`) | unit | `sdk_name` sent, echo-acked, unechoed re-sent, 422 isolated, empty omitted, ack cleared on new id, RN keys unchanged | `Tests/NottiSDKTests/NottiCoreTests.swift`, `NottiDeviceStoreKeysTests.swift` | quick, those classes |
| Facade + runtime (`NottiFacade`, `NottiRuntime`) | unit | Wrapper name/version sent, empty omitted, public path sends `ios` and the native version, restart on a different value | `Tests/NottiSDKTests/NottiFacadeInitializeTests.swift`, `NottiRuntimeTests.swift` | quick, those classes |
| SPI shell (`Notti+Wrapper.swift`) | unit | Routes to the facade with the wrapper version | `Tests/NottiSDKTests/NottiPublicApiTests.swift` | quick, `NottiPublicApiTests` |
| ObjC layer (`NottiObjC.swift`) | unit + ObjC compile check | Runtime name `NottiSDKFacade`; `NottiSDK` and RN class names not registered | `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m` | quick `-only-testing:NottiSDKTests/NottiObjCBridgeTests -only-testing:NottiSDKObjCTests` |
| Public-surface script | script mutation | Plain `public` fails, same-line `@_spi` goes to the SPI file, `@_spi` on its own line fails | `scripts/check-public-surface.sh`, `.specs/codebase/SPI_SURFACE.txt` | `scripts/check-public-surface.sh` on mutated trees |
| Docs, specs, versions | none / script | By review; `check-version.sh` | - | `scripts/check-version.sh` |

## Gate Check Commands

| Gate Level | When to Use | Command |
| --- | --- | --- |
| Quick | After each code task | `caffeinate -dimsu xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO -only-testing:<Target>/<Class>` |
| Full | T8 | the same without `-only-testing`, four times (WRAP-11 reaches ten with the six runs on `3d1cad6`), plus SwiftLint (`docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict`), the seven guard scripts of AGENTS.md, `scripts/check-hook-linked.sh spm` and `pod`, `pod lib lint` for both podspecs with and without `--use-libraries` |
| Build | Docs-only tasks | none (review) |

---

## Execution Plan

### Phase 1: Decisions

```
T1
```

### Phase 2: Identity, SPI and rename

```
T1 ──→ T2 ──→ T5
T1 ──→ T3 ──→ T4 ──→ T5
T1 ──→ T6
T1 ──→ T7
```

### Phase 3: Release

```
T5 ──→ T8
T6 ──→ T8
T7 ──→ T8
T8 ──→ T9
```

Sequential order for Execute: T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9.

---

## Task Breakdown

### T1: AD-023, AD-024, lesson and AGENTS rule

**What**: `STATE.md`: AD-023 (Obj-C facade renamed to `NottiSDKFacade`, amends AD-021, with the repro table from design section 4); AD-024 (wrapper `sdk_name` and `sdk_version` through `@_spi(Wrapper)`, part of `Config`, restart on change, SPI file; native `sdk_name: "ios"`, new key `notti_last_synced_sdk_name`, aligned with backend AD-044); lesson for the RN-only drain flake (design section 3, WRAP-10); Current Work. `AGENTS.md` Public API surface: keep `@_spi(...)` on the same line as `public`; SPI declarations listed in `SPI_SURFACE.txt`.
**Where**: `.specs/project/STATE.md`, `AGENTS.md`
**Depends on**: None
**Requirement**: WRAP-10, WRAP-14

**Done when**:

- [ ] `validate_state.py` and `validate_tasks.py` exit 0
- [ ] AD-023, AD-024 and the lesson in `STATE.md`; AGENTS rule added

**Tests**: none
**Gate**: build
**Commit**: `docs(specs): AD-023, AD-024 and the drain-flake lesson`

---

### T2: Public-surface script lists SPI separately

**What**: `scripts/check-public-surface.sh` excludes declarations whose same-line attributes include `@_spi(` from `PUBLIC_SURFACE.txt` and writes them to `.specs/codebase/SPI_SURFACE.txt` (drift-checked; `--update` rewrites both). Empty SPI file committed.
**Where**: `scripts/check-public-surface.sh`, `.specs/codebase/SPI_SURFACE.txt`
**Depends on**: T1
**Requirement**: WRAP-05

**Done when**:

- [ ] Unmodified tree passes; `PUBLIC_SURFACE.txt` unchanged
- [ ] Mutation proofs recorded in `validation.md`: added plain `public` fails; added same-line `@_spi(Wrapper) public` fails until `--update`, then only `SPI_SURFACE.txt` changes; `@_spi` on the line above `public` is read as plain public and fails
- [ ] Gate passes: script

**Tests**: script mutation
**Gate**: build
**Commit**: `ci(surface): list @_spi declarations in their own surface file`

---

### T3: Core sends `sdk_name` as a profile field

**What**: `NottiSDKVersion.name = "ios"`; `NottiCore.initialize` gains `sdkName: String = ""` (empty omitted) and syncs `sdk_name` after `sdk_version` with the existing echo ack; `profileFieldKeys` gains `sdk_name`; `NottiDeviceStore` gains `notti_last_synced_sdk_name` (get/set, snapshot, `clearProfileFieldAcks`, not the one-shot migration); keys test keeps the frozen RN list plus an SDK-only list; README storage-key list. Design section 1b.
**Where**: `Sources/NottiShared/NottiSDKVersion.swift`, `Sources/NottiSDK/Core/NottiCore.swift`, `Sources/NottiSDK/Network/NottiApiClient.swift`, `Sources/NottiSDK/Storage/NottiDeviceStore.swift`, `Tests/NottiSDKTests/NottiCoreTests.swift`, `Tests/NottiSDKTests/NottiDeviceStoreKeysTests.swift`, `README.md`
**Depends on**: T1
**Requirement**: WRAP-16, WRAP-17, WRAP-18, WRAP-19, WRAP-20

**Done when**:

- [ ] `sdk_name` passed to the core reaches its own PATCH and is acked on echo (test)
- [ ] Unechoed `sdk_name` stays unacked and is re-sent on the next registration (test)
- [ ] A 422 on `sdk_name` does not stop the other profile fields (test)
- [ ] Empty `sdkName` omits the field (test)
- [ ] `clearProfileFieldAcks` clears the new key (test)
- [ ] Every RN 0.8.0 key unchanged (keys test green with the SDK-only list)
- [ ] Test count: SDK +5
- [ ] Gate passes: quick (`NottiCoreTests`, `NottiDeviceStoreKeysTests`, `NottiDeviceStoreTests`)

**Tests**: unit
**Gate**: quick
**Commit**: `feat(core): send sdk_name as a profile field`

---

### T4: Thread wrapper `sdkName` and `sdkVersion` through facade and runtime

**What**: `NottiFacade.initialize` gains `sdkName: String? = nil, sdkVersion: String? = nil`; `Config` gains both; `NottiRuntime` gains `sdkName: String = NottiSDKVersion.name` and `start` gains both parameters, passing `x ?? self.x` to the core. Public behavior: same `sdk_version`, plus `sdk_name: "ios"`.
**Where**: `Sources/NottiSDK/Facade/NottiFacade.swift`, `Sources/NottiSDK/Runtime/NottiRuntime.swift`, `Tests/NottiSDKTests/NottiFacadeInitializeTests.swift`, `Tests/NottiSDKTests/NottiRuntimeTests.swift`
**Depends on**: T3
**Requirement**: WRAP-01, WRAP-02, WRAP-03, WRAP-06, WRAP-16, WRAP-17

**Done when**:

- [ ] Wrapper values reach the profile PATCHes as `sdk_version` and `sdk_name` (test)
- [ ] Public path sends `sdk_name: "ios"` (runtime test)
- [ ] Empty wrapper value omits `sdk_version` (test)
- [ ] No wrapper value sends `NottiSDKVersion.current` (test)
- [ ] Same config with a different wrapper `sdkVersion` or `sdkName` restarts the core; same values are a no-op (test)
- [ ] Test count: SDK +5
- [ ] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `feat(facade): accept a wrapper sdk name and version`

---

### T5: `@_spi(Wrapper)` initialize entry point

**What**: `Sources/NottiSDK/Public/Notti+Wrapper.swift` with `@_spi(Wrapper) public static func initialize(appId:clientKey:options:sdkName:sdkVersion:)` (doc comment: for wrapper SDKs, outside semver), `@available(iOSApplicationExtension, unavailable)` like the rest of `Notti`. `SPI_SURFACE.txt` updated with `--update`; `PUBLIC_SURFACE.txt` unchanged. WRAP-04 proved once with a scratch consumer (without `@_spi` the call does not compile), recorded in `validation.md`.
**Where**: `Sources/NottiSDK/Public/Notti+Wrapper.swift`, `Tests/NottiSDKTests/NottiPublicApiTests.swift`, `.specs/codebase/SPI_SURFACE.txt`
**Depends on**: T2, T4
**Requirement**: WRAP-01, WRAP-04, WRAP-05

**Done when**:

- [ ] Shell routes appId, clientKey, options, sdkName and sdkVersion to the facade (test through `setSharedForTesting`)
- [ ] `scripts/check-public-surface.sh` green; diff only in `SPI_SURFACE.txt`
- [ ] Scratch-consumer result for WRAP-04 in `validation.md`
- [ ] Test count: SDK +1
- [ ] Gate passes: quick

**Tests**: unit
**Gate**: quick
**Commit**: `feat(api): wrapper initialize behind @_spi(Wrapper)`

---

### T6: Rename the Obj-C facade class to `NottiSDKFacade`

**What**: `@objc(NottiSDKFacade)` on `NottiObjC`; ObjC tests, README Obj-C block and doc comments use it; the bridge test pins `NSClassFromString("NottiSDKFacade") === NottiObjC.self` and that `NottiSDK`, `Notti`, `NottiImpl`, `NottiBridge`, `NottiPushDelegate` are not registered by the SDK. CHANGELOG `[Unreleased]` upgrade note for Obj-C hosts.
**Where**: `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`, `Tests/NottiSDKObjCTests/NottiObjCTests.m`, `Tests/NottiSDKTests/NottiObjCBridgeTests.swift`, `README.md`, `CHANGELOG.md`, `.specs/codebase/PUBLIC_SURFACE.txt` (if the attribute line is listed)
**Depends on**: T1
**Requirement**: WRAP-14, WRAP-15

**Done when**:

- [ ] Runtime-name test updated and passing
- [ ] `NottiObjCTests.m` calls `[NottiSDKFacade ...]` and passes
- [ ] `grep -rn '\[NottiSDK ' README.md Tests Sources` empty
- [ ] Test count: unchanged or +1 (existing assertion edited)
- [ ] Gate passes: quick

**Tests**: unit + ObjC compile check
**Gate**: quick
**Commit**: `fix(objc)!: register the Objective-C facade as NottiSDKFacade`

---

### T7: Tell the RN repo the drain flake is RN-only

**What**: In `zeep-notti-react-native`, branch `spike/ios-native-sdk` (or its feature branch), add the finding to `.specs/STATE.md` Known limitations (RN `NottiCoreTests` drain flake, RN-only, ends with `ios-native-sdk` T6; evidence in this repo's design section 3), and mark EXT-1/EXT-3 progress in its `tasks.md`.
**Where**: `../zeep-notti-react-native/.specs/STATE.md`, `../zeep-notti-react-native/.specs/features/ios-native-sdk/tasks.md`
**Depends on**: T1
**Requirement**: WRAP-13

**Done when**:

- [ ] Note present in the RN repo (committed there with Julio's OK)

**Tests**: none
**Gate**: build
**Commit**: in the RN repo, `docs(specs): note the core test flake is RN-only`

---

### T8: Version 0.2.0 and the full gate

**What**: `NottiSDKVersion.current`, `NottiSDK.podspec`, `NottiSDKExtension.podspec` to `0.2.0`; CHANGELOG `[0.2.0] - TBD` (`sdk_name: "ios"` and its storage key, wrapper SPI for wrapper authors, Obj-C rename upgrade note, AD-023/AD-024); README install pin `~> 0.2`. Run the full gate.
**Where**: `Sources/NottiShared/NottiSDKVersion.swift`, both podspecs, `CHANGELOG.md`, `README.md`, `.specs/features/wrapper-support/validation.md`
**Depends on**: T5, T6, T7
**Requirement**: WRAP-07, WRAP-09, WRAP-11

**Done when**:

- [ ] `scripts/check-version.sh` green
- [ ] Four full-suite runs green, zero drain timeouts (ten total with the six on `3d1cad6`), counts recorded
- [ ] SwiftLint 0, seven guard scripts, `check-hook-linked.sh spm` and `pod`
- [ ] `pod lib lint` both podspecs, frameworks and `--use-libraries`
- [ ] Gate passes: full

**Tests**: all
**Gate**: full
**Commit**: `chore(release): prepare 0.2.0`

---

### T9: Release (Julio)

**What**: Push, PR, merge; tag `0.2.0`, GitHub Release, `pod trunk push` for `NottiSDK` then `NottiSDKExtension`, before the trunk turns read-only (AD-022). Check `pod trunk info` before retrying a failed push. Then the `zeep-notti` docs page `sdks/ios` (en + pt-BR) gets the Obj-C rename if it shows the snippet.
**Where**: GitHub, CocoaPods trunk
**Depends on**: T8
**Requirement**: WRAP-08

**Done when**:

- [ ] `pod trunk info NottiSDK` and `NottiSDKExtension` list `0.2.0`
- [ ] A clean `pod install` of the RN example resolves `~> 0.2.0` from the trunk

**Tests**: none
**Gate**: build
**Commit**: none (release)

---

## Validation (pre-approval checks)

### Check 1: Granularity

| Task | One deliverable? | Result |
| --- | --- | --- |
| T1 | Decision records | ✅ |
| T2 | One script + its output file | ✅ |
| T3 | One profile field through core, client and store + tests | ✅ |
| T4 | One behavior through two internal layers + tests | ✅ |
| T5 | One new file + surface update | ✅ |
| T6 | One rename + its references | ✅ |
| T7 | One cross-repo note | ✅ |
| T8 | Version bump + gate | ✅ |
| T9 | Release | ✅ |

### Check 2: Diagram vs `Depends on`

| Task | Depends on | Diagram | Match |
| --- | --- | --- | --- |
| T1 | None | start | ✅ |
| T2 | T1 | T1 → T2 | ✅ |
| T3 | T1 | T1 → T3 | ✅ |
| T4 | T3 | T3 → T4 | ✅ |
| T5 | T2, T4 | T2 → T5, T4 → T5 | ✅ |
| T6 | T1 | T1 → T6 | ✅ |
| T7 | T1 | T1 → T7 | ✅ |
| T8 | T5, T6, T7 | T5, T6, T7 → T8 | ✅ |
| T9 | T8 | T8 → T9 | ✅ |

### Check 3: Test co-location

| Task | Layer | Required (matrix) | In task | Result |
| --- | --- | --- | --- | --- |
| T1 | docs | none | none | ✅ |
| T2 | script | mutation | mutation proofs | ✅ |
| T3 | core + store | unit | `NottiCoreTests` +4, store/keys +1 | ✅ |
| T4 | facade + runtime | unit | facade/runtime +5 | ✅ |
| T5 | public shell | unit | `NottiPublicApiTests` +1, scratch consumer | ✅ |
| T6 | ObjC layer | unit + ObjC compile | bridge test + `.m` | ✅ |
| T7 | docs | none | none | ✅ |
| T8 | all | full | full gate | ✅ |
| T9 | release | none | trunk check | ✅ |

## Requirement coverage

| ID | Tasks |
| --- | --- |
| WRAP-01 | T4, T5 |
| WRAP-02 | T4 |
| WRAP-03 | T4 |
| WRAP-04 | T5 |
| WRAP-05 | T2, T5 |
| WRAP-06 | T4 |
| WRAP-07 | T8 |
| WRAP-08 | T9 |
| WRAP-09 | T8 |
| WRAP-10 | T1 |
| WRAP-11 | T8 |
| WRAP-12 | not applicable (spec P2) |
| WRAP-13 | T7 |
| WRAP-14 | T1, T6 |
| WRAP-15 | T6 |
| WRAP-16 | T3, T4 |
| WRAP-17 | T3, T4, T5 |
| WRAP-18 | T3 |
| WRAP-19 | T3 |
| WRAP-20 | T3 |

**Coverage:** 20 total, 19 mapped, 1 not applicable.
