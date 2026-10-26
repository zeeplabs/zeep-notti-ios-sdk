# NottiSDK for iOS

Native iOS SDK for [Zeep Notti](https://github.com/zeeplabs) push notifications: device registration, user identity, tags, engagement events (`received` / `opened` / `clicked`), rich media in a Notification Service Extension, and In-App Messages.

> **Status: `0.1.0`, first release.** It ports `react-native-notti` 0.8.0 to iOS, In-App Messages included. The [device checklist](docs/DEVICE_CHECKLIST.md) passed on the maintainer's devices and App Store validation passed; a beta in a production host app follows. See [Known limitations](#known-limitations) and the [CHANGELOG](CHANGELOG.md).

## Requirements

- iOS 15.0+
- Xcode 15.3 or later. The extension target uses `nonisolated(unsafe)`, which needs Swift 5.10. Only Xcode 26.6 and 27.1 are tested.
- A Notti backend (`zeep-notti`) that accepts what the SDK sends: v0.10.0 or later for the device-profile fields, v0.11.0 or later for the `opened` event, v0.23.0 or later for In-App Messages and v0.24.0 or later for the `logout` unlink (see [Known limitations](#known-limitations)). An older backend rejects those fields or events and the SDK drops them.
- An Apple Developer account with push notifications and an APNs key configured in your Notti app

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/zeeplabs/zeep-notti-ios-sdk.git
```

Choose the dependency rule **Up to Next Major Version** from `0.1.0`.

- Add the **`NottiSDK`** product to your app target.
- Add the **`NottiSDKExtension`** product to your Notification Service Extension target (optional, for rich media).

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/zeeplabs/zeep-notti-ios-sdk.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "NottiSDK", package: "zeep-notti-ios-sdk")]),
    .target(name: "YourNotificationServiceExtension", dependencies: [.product(name: "NottiSDKExtension", package: "zeep-notti-ios-sdk")]),
]
```

Swift Package Manager is the recommended way for native apps.

### CocoaPods

```ruby
platform :ios, '15.0'

target 'YourApp' do
  pod 'NottiSDK', '~> 0.1'
end

target 'YourNotificationServiceExtension' do
  pod 'NottiSDKExtension', '~> 0.1'
end
```

Then run `pod install` and open the `.xcworkspace`.

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

Without options the SDK talks to the production host `https://app.zeepnotti.app`. To target another host, pass `Notti.Options(baseUrl:)`. `Notti.Options(opensInAppURLs: false)` stops the SDK from opening In-App web links (see [In-App Messages](#in-app-messages)). The SDK never requests location permission.

## Identity and tags

`login` links the device to your own user id. Email, phone and tags are optional and are sent only when you set them. `logout` clears the link on the device, sends `external_user_id: null` to unlink it on the backend, and clears email and phone; tags stay. The unlink is kept on the device until the backend acknowledges it: a `logout` made offline, before `Notti.initialize`, or whose request failed is sent again at the next registration (a later `login` made after `Notti.initialize` replaces it). `login`, tag and `setSubscription` calls made before `Notti.initialize` are dropped, each with one warning (level `warn`): call them after `initialize`. `logout` is the only identity call kept from before `initialize`. After `initialize` and before the first registration, only the latest `login` or `logout` call is sent. Unlinking on the backend needs `zeep-notti` v0.24.0 or later: see [Known limitations](#known-limitations).

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

Listeners receive the payload of a push that arrived while the app runs (`received`) and of a tap (`clicked`). The SDK never opens a push URL: the push `data` reaches your code untouched and you decide what a link means. (In-App Messages differ: the SDK opens an In-App `http`/`https` `url` action and, for a `push_permission` button, the system notification settings page: see [In-App Messages](#in-app-messages).)

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

A tap goes to the clicked listeners when at least one is attached at that moment. A tap that arrives while none is attached is kept, and `takeInitialClick()` returns the latest kept tap once. On UIKit the launch tap arrives after `application(_:didFinishLaunchingWithOptions:)` returns, so a listener added there receives it live and `takeInitialClick()` returns `nil`; with no listener yet, a later tap is also returned by `takeInitialClick()`. Handle a launch from both paths, whichever comes first.

Remove a listener with `remove()` on the returned subscription. `Notti.addDeviceIdChangedListener` calls your handler on the main thread each time the device id changes, and is removed the same way.

## In-App Messages

> **Links.** By default the SDK opens an In-App `url` action whose value is an `http` or `https` link in Safari, after your click listener ran: **do not open it again in the listener**. It never opens a `deeplink`, nor a `url` with any other scheme (`tel:`, `sms:`, custom schemes): those are yours, through the click listener. Without a listener, a tap on such a button still reports `click` to Notti and closes the message, nothing opens, and the SDK logs one warning (level `warn`). To open web links yourself, pass `Notti.Options(opensInAppURLs: false)` to `Notti.initialize`.

Messages are authored in the Notti dashboard and need `zeep-notti` v0.23.0 or later. The SDK asks the backend once per foreground session, after this process registered the device, which messages this device can see (`POST /v1/apps/<appId>/in-app-messages/eligible`). It shows the first `session_start` message at once and keeps `event` messages in memory until your app reports a matching event. At most one message is visible, and each message shows at most once per session. Whether it shows again in a later session is the backend's decision: the SDK keeps no "already shown" state.

<!-- snippet:in-app -->
```swift
// Add it before `Notti.initialize`, so a message shown right after launch already has a listener.
let inAppClicks = Notti.InAppMessages.addClickListener { click in
    // nil for a `push_permission` button and for a button without a valid action.
    guard let action = click.action else { return }
    // `action.value` is the author's link, untouched.
    if action.type == .deeplink {
        // The SDK never opens a deeplink: route it inside the app.
        print("route the deeplink inside the app")
    } else {
        // The SDK opens an http(s) url in Safari after this listener returns: do not open it again.
        print("url click, opened by the SDK")
    }
}

// Shows the oldest waiting message whose trigger is this event name (exact, case-sensitive).
Notti.trackEvent("checkout_completed")

inAppClicks.remove()
```

- **`Notti.trackEvent(_:)`** matches on the device only: the name is never sent, stored or logged. An empty or whitespace-only name does nothing. A call before `Notti.initialize`, or in the background after a session ended, is ignored. A call after `Notti.initialize` and before the first session opens is remembered for that session (up to 32 distinct names), so `initialize` followed by `trackEvent` at launch works. This launch ordering is not yet proven on a device.
- **The click listener** runs on the main thread for a tap on a button, on a tappable image, or on the body of a `top` or `bottom` message that has buttons (it acts as the first button). `NottiInAppClick` carries `messageId`, `buttonId` (`image` for the image) and `action`: a `NottiInAppAction` with `type` (`url` or `deeplink`) and the untouched `value`, or nil. Keep the returned subscription and call `remove()` to stop.
- **Web links.** With `opensInAppURLs` true (the default), after the listeners ran and the message closed, the SDK opens a `url` action in the external browser (`UIApplication.open`) when its value is an `http` or `https` URL (any letter case) with a host and no spaces. An `https` universal link opens its app, as iOS decides. Any other value is not opened and logs one fixed line at level `debug`; a failed open is not retried. The listener receives every click either way, with the value untouched, and the SDK never logs the link. A `deeplink` is never opened by the SDK. A second `Notti.initialize` with the same app id, client key and base URL and another `opensInAppURLs` applies the option without restarting the SDK. Every valid `Notti.initialize` sets the option to the value it carries, like `baseUrl`: a later call without options turns it back on, so pass the same `Notti.Options` on every call (in Objective-C, use the `opensInAppURLs:` selector every time).
- **`push_permission` buttons** run the system permission flow instead of a link: the listener gets the click with `action == nil`, the message closes, and then the SDK asks for push permission if it was never asked, opens the app's notification settings in the Settings app if permission is denied (iOS 16 and later; the app's settings page on iOS 15), and does nothing more if it is already granted. That settings page is a fixed system constant, never author data. Apart from it, the only URLs the SDK opens are the `http`/`https` `url` actions above (two allowlisted files in `scripts/check-no-url-open.sh`). The dashboard cannot target devices with `push_permission` messages yet: the backend needs a per-SDK minimum version first.
- **Events.** The SDK reports `impression` (once per display, always first), `click` (with the button id) and `dismiss` (reason `close_button`, `swipe`, `outside_tap` or `auto`). They are queued on the device, sent in order with a client-generated `event_id` that survives retries and restarts, and dropped after 7 days; past 100 queued events the oldest is dropped.
- **Presentation.** Four layouts: `top` and `bottom` bars, a `center` card over a dimmed backdrop, and `full` inside the safe area. Each message has a close control (44 pt, label "Close", or "Fechar" when the first preferred language is Portuguese). Bars dismiss with a swipe, `center` with a tap on the backdrop, and `full` only with the close control or a button. An optional `dismiss_after_seconds` (1 to 300) closes the message on its own; the countdown pauses in the background.
- **Its own window.** The message shows in a separate `UIWindow` at level `.alert` (above your app's windows, like `react-native-notti`) that never becomes the key window, so it does not take the keyboard focus from your app. Touches outside a bar reach your app. The window follows the root view controller of your key window for supported orientations and the status bar. How it stacks with the keyboard, Control Center and Picture in Picture is not yet proven on a device.
- **Animation.** A bar slides 24 pt in from its edge while fading in (0.25 s); `center` and `full` fade in (0.25 s); every exit fades out in 0.2 s, and touches pass through while it does. With Reduce Motion on, entrance and exit are a 0.15 s cross-fade with no movement.
- **Plain text only.** `title` and `body` are shown character for character: HTML, Markdown and links are not rendered. Colors from the dashboard (`#RRGGBB`) are applied as sent; an invalid value falls back to the default, and the defaults follow dark mode. Text scales with Dynamic Type; long text scrolls while the close control and the buttons stay reachable.
- **Accessibility.** The title is a header, followed by the body and the buttons. `center` and `full` are modal for VoiceOver, take the focus, and close with the escape gesture (two-finger Z) as `close_button`; bars are announced and do not take the focus.
- **Images.** Only `https` images, at most 5 MiB, downloaded without your client key, token or cookies. If the image is not ready within 3 seconds the message shows without it.

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

The SDK is usable from Objective-C through the same module. The names below come from `@objc(...)` declarations in `Sources/NottiSDK/Public/ObjC/NottiObjC.swift`. The entry class is `NottiSDK`, not `Notti`, so it can live in the same app as `react-native-notti`, whose module class is `Notti`. This block is **not** compiled by CI (the example app has no Objective-C target); the Swift snippets above are.

```objc
@import NottiSDK;

[NottiSDK initializeWithAppId:@"YOUR_APP_ID" clientKey:@"YOUR_CLIENT_KEY" baseUrl:nil];
// Or, to open In-App web links in your own code instead of the SDK:
// [NottiSDK initializeWithAppId:@"YOUR_APP_ID" clientKey:@"YOUR_CLIENT_KEY" baseUrl:nil opensInAppURLs:NO];
[NottiNotifications requestPermission:^(BOOL granted) { /* ... */ }];
[NottiSDK login:@"user-123"];
[NottiUser addTag:@"plan" value:@"premium"];
NottiSubscription *sub = [NottiNotifications addClickedListener:^(NSDictionary *payload) { /* ... */ }];
[sub remove];

[NottiSDK trackEvent:@"checkout_completed"];
// payload: messageId, buttonId, action (@{@"type": @"url" or @"deeplink", @"value": ...} or NSNull)
NottiSubscription *clicks = [NottiInAppMessages addClickListener:^(NSDictionary *payload) { /* ... */ }];
```

## Data the SDK handles

This section is derived from the code. Re-read it against `Sources/` before each release.

### Sent to the Notti backend

The base URL is the production host named in [Quick start](#quick-start) unless you pass `Notti.Options(baseUrl:)`. Requests go to `/v1/apps/<appId>/devices` (registration), `/v1/apps/<appId>/devices/<deviceId>` (every later update, so the device id travels in the path), `/v1/apps/<appId>/notifications/<id>/events`, `/v1/apps/<appId>/in-app-messages/eligible` and `/v1/apps/<appId>/in-app-messages/<messageId>/events`, authenticated with your client key. Every device update also carries the push `token`.

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
| In-App fetch, once per foreground session | `device_id`, `token` |
| An In-App message is shown, tapped or closed | `device_id`, `token`, `event_id`, `type` (`impression`, `click`, `dismiss`), `occurred_at`, `button_id` (click only, the author's id), `reason` (dismiss only, a fixed value), reported under the message id |

Do not put personal data in tag keys or values unless your own basis for processing covers it.

Country is resolved on the device by reverse-geocoding a location fix that your app already holds. The SDK never asks for location permission, and only the country code is sent. Reverse geocoding itself is performed by Apple's service.

### Stored on the device

`UserDefaults` suite `notti_prefs`, unencrypted. The keys are:

`notti_device_id`, `notti_last_token`, `notti_external_user_id`, `notti_subscribed`, `notti_tags`, `notti_app_version`, `notti_first_session_at_ms`, `notti_last_session_at_ms`, `notti_session_count`, `notti_session_time_ms`, `notti_session_started_at_ms`, `notti_session_last_seen_at_ms`, `notti_location_sharing_enabled`, `notti_pending_country_clear`, `notti_pending_external_user_id_clear`, `notti_last_synced_country`, `notti_last_synced_device_os`, `notti_last_synced_device_model`, `notti_last_synced_sdk_version`, `notti_last_synced_timezone_id`, `notti_last_synced_language`, `notti_last_synced_permission_status`, `notti_last_unsubscribed_at_ms`, `notti_pending_unsubscribe_at_ms`, `notti_pending_permission_unsubscribe_at_ms`, `notti_email`, `notti_phone`, `notti_last_synced_email`, `notti_last_synced_phone`, `notti_profile_field_ack_migrated`, `notti_pending_events`, `notti_pending_inapp_events`.

The keys are the same as in `react-native-notti` 0.8.0 (AD-017 and AD-018 in `.specs/project/STATE.md`). `notti_pending_external_user_id_clear` is a flag with no personal data: a `logout` unlink the backend has not acknowledged yet. `notti_pending_inapp_events` is the In-App event queue (message id, event type, button id or dismiss reason, time and app id; no token, device id, message text or event name), in the same format as `react-native-notti`, so pending events carry over when an app moves from the React Native module to this SDK.

Logs go through one logger, default level `error`. They never contain email, phone, push token, device id, external user id or tag values, nor In-App message ids, titles, bodies, button labels, links, image URLs or `trackEvent` names, and errors are logged as `domain#code`.

### Privacy manifests

`NottiSDK` ships `PrivacyInfo.xcprivacy` with `NSPrivacyTracking` false and no tracking domains. It declares the required-reason API `UserDefaults` (`CA92.1`) and these collected data types, all linked and none used for tracking: Device ID, User ID, Email Address, Phone Number, Coarse Location, Product Interaction, Other Diagnostic Data and Other Data Types. Purposes are App Functionality for every type except Product Interaction, which declares Analytics only; Coarse Location declares both. `NottiSDKExtension` ships its own manifest with no collected data and no required-reason API. In-App Messages add no data type: their `impression`, `click` and `dismiss` events are Product Interaction, and the device id and push token sent with each In-App request are Device ID.

Other Diagnostic Data and Other Data Types are a best-fit choice for fields Apple's list does not name. Confirm them with your privacy owner.

### What your app declares in App Store Connect

Your app's privacy answers must cover what the SDK collects in your configuration, in addition to your own collection. Based on the manifest above: Device ID; User ID if you call `login`; Email and Phone if you set them; Coarse Location only if you enable location sharing; Product Interaction; Other Diagnostic Data; and Other Data Types if you set tags. Linked to the user: yes. Used for tracking: no.

### LGPD

This README describes what the SDK does. It is not legal advice and does not state that your use is compliant with the LGPD. Before shipping, have your legal and privacy teams review the data above, the legal basis, the notice shown to users, and retention and deletion in your Notti backend. That review includes In-App Messages: each In-App request carries the device id and the push token, and each message the user sees, taps or closes becomes an event linked to the device record. `trackEvent` names stay on the device.

## Known limitations

- **Rich media on a device only.** The Notification Service Extension is not exercised in the Simulator by this repo; media rendering and the expiry fallback were checked on the maintainer's devices ([device checklist](docs/DEVICE_CHECKLIST.md)). Test rich media on a physical device.
- **`logout` and re-registration need `zeep-notti` v0.24.0 or later.** From that release, `PATCH` with `external_user_id: null` unlinks the device, and a registration that omits `external_user_id` and `tags` keeps them. Against an older backend, the unlink answers 2xx but the backend keeps the stored value, so the device stays linked to the previous user until the next launch (pushes for that user can keep arriving on a shared device); the SDK counts the 2xx as delivered and does not retry. An older backend also resets `external_user_id` and tags at every launch registration, so call `login` and `addTags` again at each launch. `react-native-notti` 0.8.0 has the same limits on an older backend.
- **Tags survive `logout`.** `logout` does not clear tags on the backend; clear them yourself (`removeTags`) if they describe the user.
- **Backups can carry the device identity to another device.** The `notti_prefs` suite is part of an iOS device backup. Restoring it on a different phone can aim updates at the original device's record before the SDK re-registers. If that matters for your app, exclude it from backup.
- **SwiftUI without `@UIApplicationDelegateAdaptor`.** The SDK does not swizzle SwiftUI's internal app delegate. It logs one warning (level `warn`, so you see nothing at the default `error` level) and does not see the APNs token, so the device never registers through the SDK. Use `@UIApplicationDelegateAdaptor` with your own delegate, or set `NottiDisableSwizzling` and forward the five calls yourself.
- **Legacy-only delegates get no silent-push `received`.** A host app delegate that implements only `application(_:didReceiveRemoteNotification:)` (not the `fetchCompletionHandler` variant) is not given a replacement, so a silent push produces no `received` event. Implement the modern method or use the manual API.
- **Double observation.** If your own delegate overrides a push callback and calls `super`, the SDK can observe the same callback twice.
- **No `received` for visible pushes without `notification_id`.** A push from another sender, or one without that field, is not reported as `received`.
- **In-App Messages on a device.** The In-App device checks passed on the maintainer's devices without a per-item record. The window level against the keyboard, Control Center and Picture in Picture, legacy apps without scenes, and the launch ordering of `initialize`, `trackEvent` and the first session are not separately proven and are confirmed in a beta in a production host app.
- **`push_permission` messages are not delivered yet.** The backend has a single SDK minimum version for them, empty today, so no device receives them until `zeep-notti` adds a per-SDK minimum.
- **In-App `403` does not re-register.** On a `403` from the In-App routes the SDK logs one warning per session and route, stops fetching messages for the rest of the session (the next foreground session fetches again) and keeps the queued events, which are sent again at the next flush. It does not re-register as the server contract suggests.
- **No consent API in 0.1.0.** There is no call to hold collection until the user consents. Gate `Notti.initialize` and `Notti.login` yourself, and call `login` after `initialize`: before it, `login` is dropped (one warning).
- **Personal data in `UserDefaults`.** Email, phone, external user id and tags are stored unencrypted in the `notti_prefs` suite.
- **No `Retry-After`.** A request is tried up to 5 times, with 2, 4, 8 and 16 second waits between attempts. Only network errors, 5xx, 408, 429 and (at registration) a 2xx without a valid device body are retried; other 4xx are final. Events that use up their attempts stay queued and are tried again at a later flush. A `Retry-After` header is ignored.
- **Device proof.** The [device checklist](docs/DEVICE_CHECKLIST.md) (APNs registration, permission states, location sharing, profile fields, cold-start click, silent and background `received`, the launch hook with CocoaPods) passed on the maintainer's devices without a per-item record of device and iOS version. App Store Connect validation passed with static and dynamic frameworks.

## Example app

`Example/` is a SwiftUI app and a Notification Service Extension that call every public member. It needs [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). From `Example/`, run `xcodegen generate --spec project.yml` for SPM, or `xcodegen generate --spec project-pods.yml` and `NOTTI_LINKAGE=static|libs|dynamic pod install` for CocoaPods, and open the project or the `.xcworkspace`. The app starts uninitialized: tap **Initialize** on the Setup tab (it also adds the In-App click listener, which logs only the action type). The Push tab has a **Track event** button that calls `Notti.trackEvent("example_event")`. It needs an `Example.local.xcconfig` with your own app id and key; without it the app reads `fixture` and never calls the SDK. The README snippets are excerpts of files under `Example/`, checked by `scripts/check-readme-snippets.sh`.

## License

MIT. See [LICENSE](LICENSE).
