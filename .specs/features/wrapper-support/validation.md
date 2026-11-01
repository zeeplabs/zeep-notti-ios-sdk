# Wrapper Support (0.2.0) Validation

Evidence recorded during Execute. The Verifier writes its verdict at the end; this file is not a PASS.

## T2: Public-surface script lists `@_spi` separately (WRAP-05)

Run 2026-10-31 on `feat/wrapper-support`, mutations in a scratch copy of `Sources/`, `scripts/` and
`.specs/codebase/` (script called with the copy as repo root), one mutant file
`Sources/NottiSDK/Public/Mut.swift` at a time:

| Tree | Result |
| --- | --- |
| Unmodified repo | `public surface ok (87 declarations, 0 @_spi)`, exit 0; `--update` leaves `PUBLIC_SURFACE.txt` byte-identical and writes an empty `SPI_SURFACE.txt` |
| Added `public static func mutantPlain()` | exit 1, public surface drift |
| Added `@_spi(Wrapper) public static func mutantSpi()` | exit 1, `@_spi surface differs`; after `--update`: `PUBLIC_SURFACE.txt` byte-identical, `SPI_SURFACE.txt` lists the line, check exit 0 |
| `@_spi(Wrapper)` on its own line above `public static func mutantAbove()` | exit 1, read as plain public (public surface drift) |

## T5: `@_spi(Wrapper)` entry point invisible without the attribute (WRAP-04)

Run 2026-10-31, scratch SPM library (`.package(path:)` to this checkout at T5), `xcodebuild build`
for `generic/platform=iOS Simulator`, Xcode 27.2. Consumer line:
`Notti.initialize(appId: "a", clientKey: "k", sdkName: "react-native", sdkVersion: "0.9.0")`.

| Import | Result |
| --- | --- |
| `import NottiSDK` | does not compile: `error: extra arguments at positions #3, #4 in call` (only the public overload is visible) |
| `@_spi(Wrapper) import NottiSDK` | compiles (exit 0) |

`scripts/check-public-surface.sh --update` after adding the file: `PUBLIC_SURFACE.txt` unchanged (87
declarations), `SPI_SURFACE.txt` lists the one wrapper `initialize`.

## T8: Full gate on the 0.2.0 commit (WRAP-07, WRAP-09, WRAP-11)

Run 2026-10-31, branch `feat/wrapper-support`, iPhone 17 simulator (iOS 27.0), Xcode 27.2, CocoaPods 1.17.0.

| Check | Result |
| --- | --- |
| `scripts/check-version.sh` | `Version ok: 0.2.0` |
| Full suite `NottiSDK-Package`, 4 consecutive runs | 4/4 green: Shared 14, SDK 919, ObjC 8, Extension 110, ExtensionObjC 3; 0 failures, 0 `did not drain` |
| WRAP-11 total | 10 consecutive green full runs (6 on `3d1cad6`, 4 here), zero drain timeouts |
| SwiftLint 0.65.1 `--strict` | first run: 1 violation (`NottiCore.swift` 1504 lines, `file_length` 1500) after T3; fixed by compacting the T3 lines (comment and one call), then 0 violations; `NottiCoreTests` re-run green (134) |
| Seven guard scripts (AGENTS.md) | green |
| `scripts/check-hook-linked.sh spm` / `pod` | green / green |
| `pod lib lint` `NottiSDK`, `NottiSDKExtension`, `--platforms=ios`, frameworks and `--use-libraries` | 4/4 green |

Test count vs baseline (SDK 907): T3 +5 (core 4, store 1), T4 +6 (facade 4, runtime 2), T5 +1 = 919.
Note: `NottiCore.swift` is now at the 1500-line `file_length` limit; the next addition there needs a split.

## Pre-release review fixes (2026-11-01, branch `fix/pre-release-0.2.0`)

An Opus review of `0.1.0..main` found no blocker and six items; all fixed here.

| Finding | Fix | Proof |
| --- | --- | --- |
| `@_spi(Wrapper) import NottiSDK` proven only through SPM (T5) | none needed | RN example (`react-native-notti` `origin/main` 354d5c1) with `core.dependency "NottiSDK", "0.2.0"`, `pod 'NottiSDK', :path =>` this repo at 4134587 and a Swift file in the `Notti` pod calling `NottiSDK.Notti.initialize(appId:clientKey:options:sdkName:sdkVersion:)`: `xcodebuild build` green with static libraries, `use_frameworks!` static and dynamic. Negative control (plain `import NottiSDK`, dynamic): `error: extra arguments at positions #4, #5 in call`, BUILD FAILED |
| T9 did not date the CHANGELOG (`TBD` fails a tag build) | T9 step and Done-when item | `tasks.md` T9 |
| `spi_pattern` missed `@available(iOS 15, *) @_spi(Wrapper) public ...` | attributes with parenthesized, spaced arguments accepted | mutant M1: old script `--update` writes it to `PUBLIC_SURFACE.txt`; new: check exit 1 (`@_spi surface differs`), `--update` keeps `PUBLIC_SURFACE.txt` byte-identical and adds the line to `SPI_SURFACE.txt` |
| `@_spi` on its own line or on an `extension` was filed as plain public | new guard: every non-comment `@_spi(` must share the line with a `public` / `open` declaration; fails check and `--update` | M2 (own line) and M3 (`@_spi(Wrapper) extension`): exit 1, `--update` exit 1, files untouched; M4 (`// @_spi` comment): exit 0; unmodified repo: `public surface ok (87 declarations, 1 @_spi)` |
| A replaced core could PATCH its stale `sdk_name` after the new core's ack | `NottiCore.invalidate()` sets a flag; profile-field PATCHes check it before sending and before acking | `test_anInvalidatedCoreSendsNoProfileField`; mutant (send guard removed): fails, `("10") is not equal to ("0")`. Residual: a PATCH already on the wire at `invalidate()` can still land last (no ack is written for it) |
| No CI compile of `NottiSDK.Notti` in a CocoaPods consumer | `Example/App/LiveSDKClient.swift` calls `NottiSDK.Notti.initialize`; the Example CI legs `pods-static`, `pods-libs`, `pods-dynamic` build it | local `pods-libs` and `pods-dynamic` device builds green (gate below) |
| No core test that a new device id re-sends `sdk_name`; README said "sent once"; README pins allowed 0.3.x | `test_aNewDeviceIdResendsTheAckedSdkName`; README text, `~> 0.2.0` / `.upToNextMinor(from: "0.2.0")`, backend note (`sdk_name` needs a `zeep-notti` release after v0.26.0) | test green |

Gate (Xcode 27.2, iPhone 17 simulator, CocoaPods 1.17.0): full `NottiSDK-Package` green, Shared 14, SDK 921 (+2), ObjC 8, Extension 110, ExtensionObjC 3, 0 `did not drain`; strict device build green; SwiftLint 0.65.1 `--strict` 0 violations (`NottiCore.swift` 1499 lines); ten guard scripts green; `scripts/check-hook-linked.sh spm` / `pod` green; `pod lib lint` `NottiSDK` and `NottiSDKExtension`, frameworks and `--use-libraries`, 4/4 passed; Example `pods-libs` and `pods-dynamic` device builds (warnings as errors) green with `NottiSDK.Notti.initialize`.
