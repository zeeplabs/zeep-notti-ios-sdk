# NottiSDK (zeep-notti-ios-sdk): agent and contributor rules

Native iOS SDK for Zeep Notti push notifications. Swift 5.9 tools, **Swift 5 language mode**, iOS 15+. Distributed through SPM (products `NottiSDK`, `NottiSDKExtension`) and CocoaPods (pod `NottiSDK`, subspecs `Shared`, `Core` (default), `Extension`).

These rules apply to every contributor and every coding agent (Claude Code, Codex, Cursor, Copilot, etc.) working in this repo. This file is the single source of truth; agent-specific files such as `CLAUDE.md` only point here.

## Source of truth

- Plans and decisions live in `.specs/` (`tlc-spec-driven` workflow): `project/PROJECT.md`, `project/ROADMAP.md`, `project/STATE.md` (decisions AD-xxx, lessons, todos), `features/<feature>/{spec,design,tasks}.md`, `codebase/TESTING.md`.
- Read `STATE.md` and the current feature's `tasks.md` before starting work. Any behavior change needs a spec in this repo first (AD-001).
- Record new architecture decisions as AD entries in `STATE.md`.

## Layout

```
Sources/NottiShared/       internal, extension-safe, `package` access (AD-006)
Sources/NottiSDK/          app-only
Sources/NottiSDKExtension/ Notification Service Extension, extension-safe, never depends on NottiSDK
Tests/<Target>Tests/       XCTest, run through the SPM scheme NottiSDK-Package (`NottiSDKObjCTests` is Objective-C)
scripts/                   check-version.sh, check-extension-safety.sh, check-package-graph.sh, check-public-surface.sh,
                           check-no-url-open.sh, check-launch-hook-purity.sh, check-hook-linked.sh (+ hook-consumer/, the scratch app it builds)
```

## Commands

Set `NOTTI_SIM` to an installed simulator (CI uses `iPhone 17`; check with `xcrun simctl list devices available`).

```sh
# all tests
xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO
# one class
xcodebuild test -scheme NottiSDK-Package -destination "platform=iOS Simulator,name=$NOTTI_SIM" CODE_SIGNING_ALLOWED=NO -only-testing:NottiSDKTests/<Class>
# lint (SwiftLint is pinned; not installed locally)
docker run --rm -v "$PWD:/w" -w /w ghcr.io/realm/swiftlint:0.65.1 lint --strict
# guards and packaging
scripts/check-version.sh && scripts/check-extension-safety.sh && scripts/check-package-graph.sh && scripts/check-public-surface.sh && scripts/check-no-url-open.sh && scripts/check-launch-hook-purity.sh
# launch hook proofs (need Xcode; NOTTI_SIM picks the simulator, default "iPhone 17")
scripts/check-hook-linked.sh spm   # Release build of scripts/hook-consumer, run in the simulator, loadCount == installCount == 1
scripts/check-hook-linked.sh pod   # pod lib lint --no-clean, then nm for NottiBootstrap (about 2 min)
pod lib lint NottiSDK.podspec --platforms=ios
```

`swift test` on macOS does not work (UIKit / UserNotifications). Do not run two `xcodebuild` processes on the same checkout at once; use a separate git worktree.

## Rules

### M1 is a port, not a rewrite (AD-002)

Until M1 (v0.1.0) ships, code ported from `react-native-notti` 0.6.0 (`../zeep-notti-react-native/ios` at `52e4b55`) stays behavior-identical:

- Copy the RN file, then change only what the task lists. Keep the serial `workQueue`, the semaphore-based HTTP client, retry/backoff and every UserDefaults key (`notti_prefs` suite) exactly as in RN.
- Port RN tests 1:1 with XCTest. Do not migrate them to Swift Testing in M1.
- No Swift 6 / strict-concurrency changes, no actor or `async` rewrites of ported code. Those belong to a post-M1 spec.

### Project skills

Installed in `.claude/skills/` for Claude Code (pinned in `skills-lock.json`; other agents can read the same `SKILL.md` files directly; restore or update with `npx skills experimental_install` / `npx skills update -p`):

- `tlc-spec-driven` (tech-leads-club/agent-skills, CC-BY-4.0): the planning and execution workflow for every feature (Specify → Design → Tasks → Execute, plus quick mode). Its validators run locally with no dependencies, e.g. `python3 .claude/skills/tlc-spec-driven/scripts/validate_tasks.py .specs/features/<feature>/tasks.md`.
- `write-swift` (emilkowalski/skills): Swift style, API design, value types, performance.
- `swift-concurrency` (AvdLee): concurrency review and Swift 6 migration.

`write-swift` and `swift-concurrency` assume Swift 6.2+. In M1, use them for **new** code (e.g. `NottiRuntime`, `public-api`) and for review findings. Never apply their advice to ported code in M1; if they flag a real issue there, record it as a todo in `STATE.md` instead.

Do not add `dpearson2699/swift-ios-skills` (PolyForm Perimeter license) to this repo without legal review.

### Privacy and logging (LGPD)

- Log only through `NottiLogger`. Never interpolate email, phone, push token, external user id, country or tag values into a log message.
- Log errors as `"\(error.domain)#\(error.code)"`, not `localizedDescription` (URLs carry appId/deviceId).
- Default log level is `.error`.
- A feature that adds a required-reason API or a new collected data type updates the matching `PrivacyInfo.xcprivacy` in the same change (PKG-13).
- Test fixtures use synthetic values only (`example.invalid`, `fixture`).

### Extension safety

`NottiShared` and `NottiSDKExtension` must not use `UIApplication`, `import UIKit`, `beginBackgroundTask`, `registerForRemoteNotifications` or `CLLocationManager`. App-only API in `NottiSDK` is marked `@available(iOSApplicationExtension, unavailable)`. `scripts/check-extension-safety.sh` enforces this in CI, the extension device build uses `APPLICATION_EXTENSION_API_ONLY=YES`, and `scripts/check-package-graph.sh` fails if `NottiSDKExtension` (SPM) or the `Extension` subspec (CocoaPods) ever depends on app code.

### Code conventions

- 4-space indentation; SwiftLint config in `.swiftlint.yml` must stay at zero violations (`--strict`).
- Access: `internal` in `NottiSDK` until `public-api`; `package` in `NottiShared`. Guard shared imports with `#if canImport(NottiShared)`.
- Resources: access through `NottiSDKResources.bundle` / `NottiSDKExtensionResources.bundle`, never `Bundle.module` directly (CocoaPods has no `Bundle.module`).
- Every code change ships with its tests in the same commit (see the coverage matrix in `.specs/codebase/TESTING.md`). Test counts must not drop.

### Public API surface

Every `public` / `open` declaration in `Sources/NottiSDK` and `Sources/NottiSDKExtension` is listed in `.specs/codebase/PUBLIC_SURFACE.txt`, and `Sources/NottiShared` must have none (it stays `package`). A new, changed or removed public symbol updates that file in the same commit: run `scripts/check-public-surface.sh --update`, review the diff, commit it. `scripts/check-public-surface.sh` fails CI on drift. It also fails when a top-level public type in `Sources/NottiSDK` lacks `@available(iOSApplicationExtension, unavailable)` (extension-safe types are allowlisted in the script). Keep `public` on the declaration line, and put no `package` type in a public signature.

### Delegate integration and the launch hook

- `Sources/NottiSDKBootstrap` (ObjC) is app-only and a dependency of `NottiSDK` only. Its `+load` does a class lookup and one message send to `NottiDelegateInstaller`: no UIKit, no I/O, no `NottiRuntime` access, and on the enabled, valid path nothing logged above debug (opt-out `.info`, install failure `.error` and non-Boolean `.warn` are the only lines). `scripts/check-launch-hook-purity.sh` bans `NSLog|os_log|NSUserDefaults|NSFileManager|NSURLSession|dataWithContentsOfFile|NottiRuntime` in `NottiBootstrap.m` and `UserDefaults|FileManager|URLSession|NottiRuntime` in `NottiDelegateInstaller.swift` (comments ignored). `scripts/check-package-graph.sh` fails if `NottiShared`, `NottiSDKExtension` or the `Extension` subspec reach it; `scripts/check-hook-linked.sh` proves it runs (SPM) and is in the pod product.
- The SDK never opens a URL: a tapped push's `data` reaches the host untouched. `scripts/check-no-url-open.sh` bans `UIApplication.shared.open`, `.open(_:options` and `openURL` under `Sources/NottiSDK` and `Sources/NottiSDKBootstrap`.
- Swizzling tests build their own fake classes (`objc_allocateClassPair`, unique names) and their own `NottiMethodSwizzler`. No unit test swizzles `UIApplication` or `UNUserNotificationCenter`; `UNUserNotificationCenter` instances come from `class_createInstance` because `current()` can raise without an app bundle.

### Version

`NottiSDKVersion.current` is the only place the version is defined. Bump it together with `s.version` in `NottiSDK.podspec`; `scripts/check-version.sh` fails CI on drift.

### Git and CI

- Conventional commits (`feat(scope):`, `fix:`, `test:`, `docs(specs):`, `ci:`, `chore:`), one task per commit.
- Do not add AI co-authorship or attribution lines to commits or PRs.
- CI (`.github/workflows/ci.yml`) runs on pull requests and on pushes to `main`: SwiftLint, version + extension-safety scripts, tests on `macos-26` (Xcode 26.6, iPhone 17), device builds, `pod lib lint`. A branch push without a PR does not run CI.
