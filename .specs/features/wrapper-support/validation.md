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
