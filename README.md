# NottiSDK for iOS

Native iOS SDK for [Zeep Notti](https://github.com/zeeplabs) push notifications: device registration, user identity, tags, engagement events (`received` / `opened` / `clicked`) and rich media in a Notification Service Extension.

> **Status: `0.1.0` release candidate.** The code is complete and tested in the Simulator, but the release is not tagged or published until the [device checklist](docs/DEVICE_CHECKLIST.md) passes. It ports `react-native-notti` 0.6.0 to iOS. Do not depend on it in production yet. See [Known limitations](#known-limitations) and the [CHANGELOG](CHANGELOG.md).

## Requirements

- iOS 15.0+
- Xcode 15.3 or later. The extension target uses `nonisolated(unsafe)`, which needs Swift 5.10. Only Xcode 26.6 and 27.1 are tested.
- A Notti backend (`zeep-notti`) that accepts what the SDK sends: v0.10.0 or later for the device-profile fields and v0.11.0 or later for the `opened` event (the same as `react-native-notti` 0.6.0). An older backend rejects those fields or events and the SDK drops them.
- An Apple Developer account with push notifications and an APNs key configured in your Notti app

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/zeeplabs/zeep-notti-ios-sdk.git
```

- Add the **`NottiSDK`** product to your app target.
- Add the **`NottiSDKExtension`** product to your Notification Service Extension target (optional, for rich media).

### CocoaPods

```ruby
target 'YourApp' do
  pod 'NottiSDK'
end

target 'YourNotificationServiceExtension' do
  pod 'NottiSDKExtension'
end
```

Linking `NottiSDKExtension` into the app target builds, but exposes no app API. Use `NottiSDK` there. In the extension, `import NottiSDKExtension`, the same line as with SPM. Both pods work with dynamic frameworks, static frameworks and static libraries.

## Capabilities

In the app target, under **Signing & Capabilities**:

- **Push Notifications**
- **Background Modes → Remote notifications** (needed for silent pushes)

The Notification Service Extension needs no capability of its own.

## Quick start

Call `Notti.initialize` once at launch with your app id and client key, then ask for permission when it makes sense for your user. `requestPermission` returns whether the user granted it.

<!-- snippet:init -->
```swift
Notti.initialize(appId: "YOUR_APP_ID", clientKey: "YOUR_CLIENT_KEY")

Task {
    let granted = await Notti.Notifications.requestPermission()
    print("push permission granted: \(granted)")
}
```

Without options the SDK talks to the production host `https://app.zeepnotti.app`. To target another host, pass `Notti.Options(baseUrl:)`. The SDK never requests location permission.

## Identity and tags

`login` links the device to your own user id. Email, phone and tags are optional and are sent only when you set them. `logout` clears the link on the device, sends `external_user_id: null` to unlink it on the backend, and clears email and phone; tags stay. Unlinking on the backend needs a `zeep-notti` release that includes its AD-039: see [Known limitations](#known-limitations).

<!-- snippet:identity -->
```swift
Notti.login("user-123")
Notti.User.setEmail("person@example.invalid")
Notti.User.addTags(["plan": "premium", "locale": "pt-BR"])
Notti.User.removeTag("locale")

Notti.logout()
```

Other calls: `Notti.User.setPhone`, `clearEmail`, `clearPhone`, `addTag`, `removeTags`, `Notti.User.setSubscription(_:)` and `Notti.setLocationSharingEnabled(_:)` (off by default, see [Data the SDK handles](#data-the-sdk-handles)).

## Listeners

Listeners receive the payload of a push that arrived while the app runs (`received`) and of a tap (`clicked`). The SDK never opens a URL: the push `data` reaches your code untouched and you decide what a link means.

<!-- snippet:listeners -->
```swift
let received = Notti.Notifications.addReceivedListener { payload in
    print("received with \(payload.data.count) data keys")
}
let clicked = Notti.Notifications.addClickedListener { payload in
    // `payload.data` is the push data, untouched. Decide what a link means here.
    print("clicked with \(payload.data.count) data keys")
}

// A tap that launched the app is kept until you take it.
if let initial = Notti.Notifications.takeInitialClick() {
    print("launched from a push: \(initial.data.count) data keys")
}

received.remove()
clicked.remove()
```

Remove a listener with `remove()` on the returned subscription. `Notti.addDeviceIdChangedListener` calls your handler on the main thread each time the device id changes, and is removed the same way.

## Rich media (Notification Service Extension)

Add a Notification Service Extension target, link `NottiSDKExtension`, and forward both callbacks. The extension downloads the media URL carried by the push (key `notti_image_url`, never part of `payload.data`) and attaches it. The URL must be `https`, the file at most 10 MiB, and the type one of jpg, png, gif, mp4 or mp3 by its MIME type or URL extension. A file with an unknown type is still tried as `jpg`, so it may or may not render. If the time budget runs out it delivers the content it already has.

<!-- snippet:nse -->
```swift
import NottiSDKExtension
import UserNotifications

@objc(NotificationService)
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content
        NottiNotificationServiceExtension.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler else { return }
        NottiNotificationServiceExtension.serviceExtensionTimeWillExpire(
            for: bestAttemptContent, contentHandler: contentHandler
        )
    }
}
```

## Delegate integration and the swizzling opt-out

By default the SDK installs itself at launch and observes the push callbacks on your app delegate and on `UNUserNotificationCenter`'s delegate, so no forwarding code is needed. It works with a UIKit delegate and with SwiftUI `@UIApplicationDelegateAdaptor`. A SwiftUI app **without** the adaptor is not supported by swizzling: see [Known limitations](#known-limitations). When the host leaves `UNUserNotificationCenter`'s delegate nil, the SDK assigns its own at the end of launch; a delegate you set later is observed, not replaced.

To turn that off, add this key to your app's `Info.plist`. Only a Boolean `true` counts; a string or a number is ignored and the SDK logs one warning.

```xml
<key>NottiDisableSwizzling</key>
<true/>
```

With the key set, you set the notification-center delegate yourself and forward these five callbacks:

<!-- snippet:manual-forwarding -->
```swift
final class ForwardingAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Notti.Notifications.didFailToRegisterForRemoteNotifications(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(Notti.Notifications.didReceiveRemoteNotification(userInfo))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Notti.Notifications.willPresent(notification))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Notti.Notifications.didReceive(response)
        completionHandler()
    }
}
```

## Objective-C

The SDK is usable from Objective-C through the same module. The names below come from `@objc(...)` declarations in `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`. This block is **not** compiled by CI (the example app has no Objective-C target); the Swift snippets above are.

```objc
@import NottiSDK;

[Notti initializeWithAppId:@"YOUR_APP_ID" clientKey:@"YOUR_CLIENT_KEY" baseUrl:nil];
[NottiNotifications requestPermission:^(BOOL granted) { /* ... */ }];
[Notti login:@"user-123"];
[NottiUser addTag:@"plan" value:@"premium"];
NottiSubscription *sub = [NottiNotifications addClickedListener:^(NSDictionary *payload) { /* ... */ }];
[sub remove];
```

## Data the SDK handles

This section is derived from the code. Re-read it against `Sources/` before each release.

### Sent to the Notti backend

The base URL is the production host named in [Quick start](#quick-start) unless you pass `Notti.Options(baseUrl:)`. Requests go to `/v1/apps/<appId>/devices` (registration), `/v1/apps/<appId>/devices/<deviceId>` (every later update, so the device id travels in the path) and `/v1/apps/<appId>/notifications/<id>/events`, authenticated with your client key. Every device update also carries the push `token`.

| When | Fields |
|---|---|
| Registration | `token` (APNs push token), `platform` (`ios`) |
| `login` | `external_user_id` |
| `setEmail`, `setPhone` | `email`, `phone` |
| `addTag`, `addTags`, `removeTag`, `removeTags` | `tags` (your own key/value pairs) |
| Permission and `setSubscription` | `permission_status`, `subscribed`, `last_unsubscribed_at` |
| Device profile, synced when changed | `app_version`, `sdk_version`, `device_os`, `device_model`, `timezone_id`, `language` |
| Sessions | `first_session_at`, `last_session_at`, `session_count`, `session_time_seconds` |
| Location sharing on, and your app already holds location permission | `country` only (`null` when you turn sharing off) |
| A push is received, opened or clicked | `delivery_id`, `type` (`received`, `opened`, `clicked`), `token`, reported under the notification id |

Do not put personal data in tag keys or values unless your own basis for processing covers it.

Country is resolved on the device by reverse-geocoding a location fix that your app already holds. The SDK never asks for location permission, and only the country code is sent. Reverse geocoding itself is performed by Apple's service.

### Stored on the device

`UserDefaults` suite `notti_prefs`, unencrypted. The keys are:

`notti_device_id`, `notti_last_token`, `notti_external_user_id`, `notti_subscribed`, `notti_tags`, `notti_app_version`, `notti_first_session_at_ms`, `notti_last_session_at_ms`, `notti_session_count`, `notti_session_time_ms`, `notti_session_started_at_ms`, `notti_session_last_seen_at_ms`, `notti_location_sharing_enabled`, `notti_pending_country_clear`, `notti_last_synced_country`, `notti_last_synced_device_os`, `notti_last_synced_device_model`, `notti_last_synced_sdk_version`, `notti_last_synced_timezone_id`, `notti_last_synced_language`, `notti_last_synced_permission_status`, `notti_last_unsubscribed_at_ms`, `notti_pending_unsubscribe_at_ms`, `notti_pending_permission_unsubscribe_at_ms`, `notti_email`, `notti_phone`, `notti_last_synced_email`, `notti_last_synced_phone`, `notti_profile_field_ack_migrated`, `notti_pending_events`.

The keys are the same as in `react-native-notti` 0.6.0 (AD-002 in `.specs/project/STATE.md`).

Logs go through one logger, default level `error`. They never contain email, phone, push token, external user id or tag values, and errors are logged as `domain#code`.

### Privacy manifests

`NottiSDK` ships `PrivacyInfo.xcprivacy` with `NSPrivacyTracking` false and no tracking domains. It declares the required-reason API `UserDefaults` (`CA92.1`) and these collected data types, all linked and none used for tracking: Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types. Purposes are App Functionality for every type except Product Interaction, which declares Analytics only; Coarse Location declares both. `NottiSDKExtension` ships its own manifest with no collected data and no required-reason API.

Other Diagnostic Data and Other Data Types are a best-fit choice for fields Apple's list does not name. Confirm them with your privacy owner.

### What your app declares in App Store Connect

Your app's privacy answers must cover what the SDK collects in your configuration, in addition to your own collection. Based on the manifest above: Device ID; User ID if you call `login`; Email and Phone if you set them; Coarse Location only if you enable location sharing; Product Interaction; Other Diagnostic Data; and Other Data Types if you set tags. Linked to the user: yes. Used for tracking: no.

### LGPD

This README describes what the SDK does. It is not legal advice and does not state that your use is compliant with the LGPD. Before shipping, have your legal and privacy teams review the data above, the legal basis, the notice shown to users, and retention and deletion in your Notti backend.

## Known limitations

- **Rich media on a device only.** The Notification Service Extension is not exercised in the Simulator by this repo. Media rendering and the expiry fallback are unproven until the device checklist passes.
- **Backend release needed for `logout` and re-registration.** Two fixes live in `zeep-notti` (AD-039, not yet released at the time of writing): `PATCH` with `external_user_id: null` unlinks the device, and a registration that omits `external_user_id` and `tags` keeps them. Against an older backend, `logout` answers 200 but the device stays linked to the previous user (pushes for that user can keep arriving on a shared device), and every launch registration resets `external_user_id` and tags, so call `login` and `addTags` again at each launch. `react-native-notti` 0.6.0 has the same limits on an older backend.
- **Tags survive `logout`.** `logout` does not clear tags on the backend; clear them yourself (`removeTags`) if they describe the user.
- **Backups can carry the device identity to another device.** The `notti_prefs` suite is part of an iOS device backup. Restoring it on a different phone can aim updates at the original device's record before the SDK re-registers. If that matters for your app, exclude it from backup.
- **SwiftUI without `@UIApplicationDelegateAdaptor`.** The SDK does not swizzle SwiftUI's internal app delegate. It logs one warning (level `warn`, so you see nothing at the default `error` level) and does not see the APNs token, so the device never registers through the SDK. Use `@UIApplicationDelegateAdaptor` with your own delegate, or set `NottiDisableSwizzling` and forward the five calls yourself.
- **Legacy-only delegates get no silent-push `received`.** A host app delegate that implements only `application(_:didReceiveRemoteNotification:)` (not the `fetchCompletionHandler` variant) is not given a replacement, so a silent push produces no `received` event. Implement the modern method or use the manual API.
- **Double observation.** If your own delegate overrides a push callback and calls `super`, the SDK can observe the same callback twice.
- **No `received` for visible pushes without `notification_id`.** A push from another sender, or one without that field, is not reported as `received`.
- **No consent API in 0.1.0.** There is no call to hold collection until the user consents. Gate `Notti.initialize` and `Notti.login` yourself.
- **Personal data in `UserDefaults`.** Email, phone, external user id and tags are stored unencrypted in the `notti_prefs` suite.
- **No `Retry-After`.** A request is tried up to 5 times, with 2, 4, 8 and 16 second waits between attempts. Only network errors, 5xx, 408, 429 and (at registration) a 2xx without a valid device body are retried; other 4xx are final. Events that use up their attempts stay queued and are tried again at a later flush. A `Retry-After` header is ignored.
- **Not yet proven on a device:** APNs registration and token delivery, permission prompt states, geocoder and location sharing, device profile fields, cold-start click, silent and background `received`, the launch hook in a CocoaPods app, and an App Store Connect validation upload. See [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md).

## Example app

`Example/` is a SwiftUI app and a Notification Service Extension that call every public member. It needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). From `Example/`, run `xcodegen generate --spec project.yml` for SPM, or `xcodegen generate --spec project-pods.yml` and `NOTTI_LINKAGE=static|libs|dynamic pod install` for CocoaPods, and open the project or the `.xcworkspace`. The app starts uninitialized: tap **Initialize** on the Setup tab. It needs an `Example.local.xcconfig` with your own app id and key; without it the app reads `fixture` and never calls the SDK. The README snippets are excerpts of files under `Example/`, checked by `scripts/check-readme-snippets.sh`.

## License

MIT. See [LICENSE](LICENSE).
