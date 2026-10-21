# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - TBD

First release. It is a native port of `react-native-notti` 0.6.0 for iOS, with the same backend contract and the same on-device storage. The date is set on release day, after the [device checklist](docs/DEVICE_CHECKLIST.md) passes.

### Added

- Swift API `Notti` (`initialize`, `login`, `logout`, `deviceId`, `logLevel`, `setLocationSharingEnabled`), `Notti.User` (email, phone, tags, subscription) and `Notti.Notifications` (permission, received and clicked listeners, `takeInitialClick`, delegate forwarding). Objective-C names under `Notti`, `NottiUser` and `NottiNotifications`.
- Delivery events `received`, `opened` and `clicked`, queued on the device and retried with backoff.
- Push delegate integration by swizzling, installed by a launch hook; opt out with the Boolean `NottiDisableSwizzling` in `Info.plist` and forward five calls by hand.
- Rich media in a Notification Service Extension (`NottiSDKExtension`, class `NottiNotificationServiceExtension`) with a 20 second download deadline and an expiry fallback.
- Privacy manifests for both products. `NottiSDK` declares Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types (linked, no tracking); `NottiSDKExtension` declares no collected data and no required-reason API.
- Distribution through Swift Package Manager (products `NottiSDK`, `NottiSDKExtension`) and CocoaPods (two root pods, `NottiSDK` and `NottiSDKExtension`), with static libraries, static frameworks and dynamic frameworks.
- Example app (`Example/`) that calls every public member, built through SPM and CocoaPods, and an integrator README whose snippets are checked against the example sources.

### Known limitations

- Several behaviors are not proven on a physical device. See [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md).
- The Notification Service Extension is not exercised in the Simulator by this repo.
- If your own delegate overrides a push callback and calls `super`, the SDK can observe the same callback twice.
- A visible push without `notification_id` (for example from another SDK) is not reported as `received`.
- There is no consent API: gate `Notti.initialize` and `Notti.login` yourself.
- Email, phone, external user id and tags are stored unencrypted in `UserDefaults` (suite `notti_prefs`).
- A request is tried up to 5 times with 2, 4, 8 and 16 second waits; only network errors, 5xx, 408 and 429 are retried, and `Retry-After` is ignored.
- Location sharing needs your app to hold location permission; the SDK never requests it.

### Migration notes from `react-native-notti` 0.6.0

- **Storage.** The SDK keeps the same `UserDefaults` suite, `notti_prefs`, and the same key names as the iOS part of `react-native-notti` 0.6.0 (for example `notti_device_id`, `notti_last_token`, `notti_external_user_id`, `notti_tags`, `notti_pending_events`). No key was renamed or added for 0.1.0.
- **Device id continuity.** An app that replaces the React Native module with this SDK keeps its install container, so it should keep its `notti_device_id` and not register a new device. This follows from the shared suite and keys and is **not yet verified on a device** (checklist item D20). Until it is, do not tell customers that device history is preserved.
- **Behavior differences.**
  - A visible push without `notification_id` is no longer emitted as `received`.
  - In the Notification Service Extension, `didReceive(_:withContentHandler:)` and `serviceExtensionTimeWillExpire(for:contentHandler:)` take no `session:` or `logger:` argument.
  - The media download has a 20 second deadline for the whole transfer (React Native used an inactivity timeout).
  - Swizzling is on by default and can be turned off with `NottiDisableSwizzling`.
