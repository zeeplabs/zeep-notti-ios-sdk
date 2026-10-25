# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - TBD

First release. It is a native port of `react-native-notti` 0.8.0 for iOS, In-App Messages included, with the same backend contract and the same on-device storage. The date is set on release day, after the [device checklist](docs/DEVICE_CHECKLIST.md) and the In-App device checklist pass.

### Added

- Swift API `Notti` (`initialize`, `login`, `logout`, `deviceId`, `logLevel`, `setLocationSharingEnabled`), `Notti.User` (email, phone, tags, subscription) and `Notti.Notifications` (permission, received and clicked listeners, `takeInitialClick`, delegate forwarding). Objective-C names under `NottiSDK` (not `Notti`, which is the class name of `react-native-notti`'s module), `NottiUser` and `NottiNotifications`.
- Delivery events `received`, `opened` and `clicked`, queued on the device and retried with backoff.
- Push delegate integration by swizzling, installed by a launch hook; opt out with the Boolean `NottiDisableSwizzling` in `Info.plist` and forward five calls by hand.
- Rich media in a Notification Service Extension (`NottiSDKExtension`, class `NottiNotificationServiceExtension`) with a 20 second download deadline and an expiry fallback.
- Privacy manifests for both products. `NottiSDK` declares Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types (linked, no tracking); `NottiSDKExtension` declares no collected data and no required-reason API.
- Distribution through Swift Package Manager (products `NottiSDK`, `NottiSDKExtension`) and CocoaPods (two root pods, `NottiSDK` and `NottiSDKExtension`), with static libraries, static frameworks and dynamic frameworks.
- In-App Messages (needs `zeep-notti` v0.23.0 or later): one `eligible` fetch per foreground session after this process registered the device; `top`, `bottom`, `center` and `full` layouts in a dedicated non-key window at level `.alert`; plain text only, dashboard colors with safe fallbacks, Dynamic Type, VoiceOver (escape gesture closes `center` and `full`) and Reduce Motion; `https` images up to 5 MiB with a 3 second budget; auto dismiss; `impression`, `click` and `dismiss` events in a persistent ordered queue with client-generated `event_id`s. New API: `Notti.trackEvent(_:)` (matched on the device, never sent) and `Notti.InAppMessages.addClickListener(_:)` delivering `NottiInAppClick` (`messageId`, `buttonId`, `action: NottiInAppAction?`); Objective-C `[NottiSDK trackEvent:]` and `[NottiInAppMessages addClickListener:]` with an `NSDictionary` (`messageId`, `buttonId`, `action` as `{type, value}` or `NSNull`).
- `push_permission` In-App buttons: the SDK asks for push permission when it was never asked, and when permission is denied opens the system notification settings (`UIApplication.openNotificationSettingsURLString` on iOS 16+, `openSettingsURLString` on iOS 15). This settings URL is a fixed system constant, never author data.
- In-App `url` actions open in the external browser (AD-020): after the click listeners ran and the message closed, the SDK opens a `url` action whose value is an `http` or `https` URL with a host (`UIApplication.open`). Any other scheme is not opened, `deeplink` actions are never opened by the SDK, and the listener still receives every click with the value untouched. On by default; turn it off with `Notti.Options(baseUrl:opensInAppURLs:)` (`opensInAppURLs: false`) or Objective-C `[NottiSDK initializeWithAppId:clientKey:baseUrl:opensInAppURLs:]`. The link is never logged.
- Example app (`Example/`) that calls every public member, built through SPM and CocoaPods, and an integrator README whose snippets are checked against the example sources.

### Known limitations

- Several behaviors are not proven on a physical device. See [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md).
- The Notification Service Extension is not exercised in the Simulator by this repo.
- A SwiftUI app without `@UIApplicationDelegateAdaptor`: the SDK does not swizzle SwiftUI's internal app delegate, logs one warning (level `warn`, invisible at the default `error` level) and does not receive the APNs token. Use the adaptor or the manual forwarding API.
- `logout` and re-registration need `zeep-notti` v0.24.0 or later. On an older backend, the `logout` unlink answers 2xx but the device stays linked to the previous user until the next launch, the SDK does not retry it, and every launch registration resets `external_user_id` and tags (call `login` and `addTags` at each launch). Tags always survive `logout`.
- `logout` sends `external_user_id: null` to unlink the device on the backend, like `react-native-notti` 0.8.0. The unlink is durable: a `logout` made offline, before `initialize`, or whose request failed is sent again at the next registration, and a later `login` made after `initialize` replaces it. `login`, tag and `setSubscription` calls made before `initialize` are dropped, each with one warning (level `warn`); `logout` is the only identity call kept from before `initialize`. After `initialize` and before the first registration, only the latest `login` or `logout` call is sent.
- The `notti_prefs` suite is included in iOS device backups and can carry the device identity to another device when restored.
- A host app delegate that implements only the legacy `application(_:didReceiveRemoteNotification:)` gets no silent-push `received` event.
- If your own delegate overrides a push callback and calls `super`, the SDK can observe the same callback twice.
- A visible push without `notification_id` (for example from another SDK) is not reported as `received`.
- There is no consent API: gate `Notti.initialize` and `Notti.login` yourself, and call `login` after `initialize` (before it, `login` is dropped).
- Email, phone, external user id and tags are stored unencrypted in `UserDefaults` (suite `notti_prefs`).
- A request is tried up to 5 times with 2, 4, 8 and 16 second waits; only network errors, 5xx, 408 and 429 are retried, and `Retry-After` is ignored.
- Location sharing needs your app to hold location permission; the SDK never requests it.
- In-App Messages are tested in the Simulator only: rendering, VoiceOver, the window level against the keyboard, Control Center and Picture in Picture, legacy apps without scenes, iPad multitasking, the `push_permission` settings jump and the launch ordering of `initialize`, `trackEvent` and the first session wait for the In-App device checklist.
- Without an In-App click listener, a tap on a `deeplink` button, or on a `url` button the SDK does not open (another scheme, or `opensInAppURLs: false`), reports `click` and closes the message but opens nothing. A listener that also opens an `http`/`https` `url` while `opensInAppURLs` is true opens it twice.
- On `403` from the In-App routes the SDK does **not** re-register as the server contract suggests: it logs one warning, stops In-App on the device until the next registration and keeps the queued events (same as `react-native-notti` 0.8.0).
- `push_permission` messages reach no device until `zeep-notti` adds a per-SDK minimum version for them.

### Migration notes from `react-native-notti` (0.6.0 to 0.8.0)

- **Storage.** The SDK keeps the same `UserDefaults` suite, `notti_prefs`, and the same key names as the iOS part of `react-native-notti` 0.8.0 (for example `notti_device_id`, `notti_last_token`, `notti_external_user_id`, `notti_tags`, `notti_pending_events`, `notti_pending_external_user_id_clear`, `notti_pending_inapp_events`). No key was renamed. `notti_pending_external_user_id_clear` is a flag (no personal data) for a `logout` unlink not yet acknowledged by the backend. `notti_pending_inapp_events` is the In-App event queue in RN's format, so In-App events queued by the React Native module are sent with their original `event_id` after the swap (not yet verified on a device).
- **Device id continuity.** An app that replaces the React Native module with this SDK keeps its install container and its `notti_prefs` suite. The SDK does not send the stored `notti_device_id`: at registration it sends the push token and platform, and adopts the device id the backend returns for that token. So continuity depends on the APNs token not changing and on the backend upserting by token, and is **not yet verified on a device** (checklist item D20). Until it is, do not tell customers that device history is preserved.
- **Behavior differences.**
  - A visible push without `notification_id` is no longer emitted as `received`.
  - In-App `http`/`https` `url` actions are opened by the SDK after the click listener (React Native 0.8.0 never opens a link). Pass `opensInAppURLs: false` to keep the 0.8.0 behavior.
  - In the Notification Service Extension, `didReceive(_:withContentHandler:)` and `serviceExtensionTimeWillExpire(for:contentHandler:)` take no `session:` or `logger:` argument.
  - The media download has a 20 second deadline for the whole transfer (React Native used an inactivity timeout).
  - Swizzling is on by default and can be turned off with `NottiDisableSwizzling`. When the host leaves the notification-center delegate nil, the SDK assigns its own at the end of launch.
