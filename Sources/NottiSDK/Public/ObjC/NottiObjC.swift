import Foundation
import UIKit
import UserNotifications

// Objective-C interop layer (API-13). Swift namespaces (`Notti.User`, ...) are
// invisible to Objective-C, so these `NSObject` classes expose the same
// capabilities under the ObjC names `NottiSDK`, `NottiUser`, `NottiNotifications`
// and `NottiInAppMessages`.
// The Swift names carry an `ObjC` suffix because `Notti` is the Swift namespace
// enum. Swift hosts should use `Notti`; these classes exist for Objective-C hosts
// and the React Native bridge.
//
// The facade class is `NottiSDK` in Objective-C, not `Notti` (AD-021):
// react-native-notti's TurboModule class is `@interface Notti`, and two classes
// with one runtime name cannot link into the same app.
//
// The layer bridges types only (`String?`, `NSDictionary`, blocks, `NSArray`) and
// forwards to `NottiFacade.shared`: no behavior of its own, except dropping
// non-string tag values through `NottiRuntime.sanitizeTags` (RN parity).
//
// Notification payloads reach Objective-C as an `NSDictionary` with `title` and
// `body` (absent when the push has none) and `data` (string keys and values).
// In-App clicks reach it as an `NSDictionary` with exactly `messageId`,
// `buttonId` and `action` (`@{type, value}`, or `NSNull`, never absent).

/// Objective-C name: `NottiSDK` (AD-021). Initialize, identity, location sharing and log level.
@objc(NottiSDK)
@available(iOSApplicationExtension, unavailable)
public final class NottiObjC: NSObject {

    /// Starts the SDK. `baseUrl` may be `nil` (default host). Same as passing
    /// `opensInAppURLs:YES`: a call with this selector turns In-App link opening
    /// back on after `opensInAppURLs:NO`. Invalid values are logged without their
    /// content and ignored.
    @objc(initializeWithAppId:clientKey:baseUrl:)
    public static func initialize(appId: String, clientKey: String, baseUrl: String?) {
        NottiFacade.shared.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
    }

    /// Starts the SDK and sets whether it opens In-App `http`/`https` `url`
    /// actions in the browser after the click listeners (`YES` is what
    /// `initializeWithAppId:clientKey:baseUrl:` uses). `NO` opens none
    /// (`Notti.Options.opensInAppURLs`). Every valid call sets the option, so use
    /// this selector with the same value on every call.
    @objc(initializeWithAppId:clientKey:baseUrl:opensInAppURLs:)
    public static func initialize(appId: String, clientKey: String, baseUrl: String?, opensInAppURLs: Bool) {
        NottiFacade.shared.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, opensInAppURLs: opensInAppURLs)
    }

    @objc(login:)
    public static func login(_ externalUserId: String) {
        NottiFacade.shared.login(externalUserId)
    }

    @objc(logout)
    public static func logout() {
        NottiFacade.shared.logout()
    }

    /// The persisted device id; `nil` for a device that never registered.
    @objc(deviceId)
    public static var deviceId: String? {
        NottiFacade.shared.deviceId
    }

    /// Calls `handler` on the main thread on each device-id change. Keep the
    /// returned subscription and call `-remove` to stop.
    @discardableResult
    @objc(addDeviceIdChangedListener:)
    public static func addDeviceIdChangedListener(_ handler: @escaping (String) -> Void) -> NottiSubscription {
        NottiFacade.shared.addDeviceIdChangedListener(handler)
    }

    @objc(setLocationSharingEnabled:)
    public static func setLocationSharingEnabled(_ enabled: Bool) {
        NottiFacade.shared.setLocationSharingEnabled(enabled)
    }

    @objc(logLevel)
    public static var logLevel: NottiLogLevelObjC {
        get { NottiFacade.shared.logLevel }
        set { NottiFacade.shared.logLevel = newValue }
    }

    /// Reports an app event for In-App messages. Matched on the device: the
    /// name is never sent, stored or logged. Empty names and calls before
    /// initialize do nothing.
    @objc(trackEvent:)
    public static func trackEvent(_ name: String) {
        NottiFacade.shared.trackEvent(name)
    }
}

/// Objective-C name: `NottiInAppMessages`. Taps on In-App messages.
@objc(NottiInAppMessages)
@available(iOSApplicationExtension, unavailable)
public final class NottiInAppMessagesObjC: NSObject {

    /// `handler` runs on the main thread with `messageId`, `buttonId` and
    /// `action` (`@{type, value}`, or `NSNull` for a button without a valid
    /// action and for a `push_permission` button). After it, the SDK opens an
    /// `http`/`https` `url` in the browser unless `opensInAppURLs` was `NO`;
    /// it never opens a `deeplink`.
    @discardableResult
    @objc(addClickListener:)
    public static func addClickListener(_ handler: @escaping (NSDictionary) -> Void) -> NottiSubscription {
        NottiFacade.shared.addInAppClickListener { handler($0.objcDictionary) }
    }
}

/// Objective-C name: `NottiUser`. Tags, email, phone and subscription.
@objc(NottiUser)
@available(iOSApplicationExtension, unavailable)
public final class NottiUserObjC: NSObject {

    @objc(addTag:value:)
    public static func addTag(_ key: String, value: String) {
        NottiFacade.shared.addTags([key: value])
    }

    /// Entries whose key or value is not a string are dropped, not coerced.
    @objc(addTags:)
    public static func addTags(_ tags: [AnyHashable: Any]) {
        NottiFacade.shared.addTags(NottiRuntime.sanitizeTags(tags))
    }

    @objc(removeTag:)
    public static func removeTag(_ key: String) {
        NottiFacade.shared.removeTags([key])
    }

    /// Elements that are not strings are dropped, as in `addTags:`. Typed `NSArray` on purpose: bridging an
    /// array with a non-string element to `[String]` traps at the call (PRF-06).
    @objc(removeTags:)
    public static func removeTags(_ keys: [Any]) {
        NottiFacade.shared.removeTags(keys.compactMap { $0 as? String })
    }

    @objc(setEmail:)
    public static func setEmail(_ email: String) {
        NottiFacade.shared.setEmail(email)
    }

    @objc(clearEmail)
    public static func clearEmail() {
        NottiFacade.shared.clearEmail()
    }

    @objc(setPhone:)
    public static func setPhone(_ phone: String) {
        NottiFacade.shared.setPhone(phone)
    }

    @objc(clearPhone)
    public static func clearPhone() {
        NottiFacade.shared.clearPhone()
    }

    @objc(setSubscription:)
    public static func setSubscription(_ enabled: Bool) {
        NottiFacade.shared.setSubscription(enabled)
    }
}

/// Objective-C name: `NottiNotifications`. Permission, listeners and the launch notification.
@objc(NottiNotifications)
@available(iOSApplicationExtension, unavailable)
public final class NottiNotificationsObjC: NSObject {

    /// `completion` runs once, on the main thread. `NO` before initialize.
    @objc(requestPermission:)
    public static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        NottiFacade.shared.requestPermission(completion: completion)
    }

    @discardableResult
    @objc(addReceivedListener:)
    public static func addReceivedListener(_ handler: @escaping (NSDictionary) -> Void) -> NottiSubscription {
        NottiFacade.shared.addReceivedListener { handler($0.objcDictionary) }
    }

    @discardableResult
    @objc(addClickedListener:)
    public static func addClickedListener(_ handler: @escaping (NSDictionary) -> Void) -> NottiSubscription {
        NottiFacade.shared.addClickedListener { handler($0.objcDictionary) }
    }

    /// The latest tap that arrived while no clicked listener was attached
    /// (normally the launch tap), once; `nil` afterwards and when a listener
    /// already received it.
    @objc(takeInitialClick)
    public static func takeInitialClick() -> NSDictionary? {
        NottiFacade.shared.takeInitialClick()?.objcDictionary
    }

    // MARK: - Manual forwarding (DEL-12)
    //
    // For hosts that set `NottiDisableSwizzling` to YES. Same semantics as `Notti.Notifications` in Swift:
    // the same adapter entry points, ignored with one warning while swizzling is on.

    @objc(didRegisterForRemoteNotificationsWithDeviceToken:)
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        NottiFacade.shared.pushAdapter.manualDidRegister(deviceToken: deviceToken)
    }

    @objc(didFailToRegisterForRemoteNotificationsWithError:)
    public static func didFailToRegisterForRemoteNotifications(error: Error) {
        NottiFacade.shared.pushAdapter.manualDidFail(error: error)
    }

    /// Returns the result to pass to the fetch completion handler (`UIBackgroundFetchResultNoData`).
    @discardableResult
    @objc(didReceiveRemoteNotification:)
    public static func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        NottiFacade.shared.pushAdapter.manualDidReceiveRemoteNotification(userInfo: userInfo)
    }

    /// Banner, list, sound and badge for a Notti push, none for anything else.
    @discardableResult
    @objc(willPresentNotification:)
    public static func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        let request = notification.request
        return NottiFacade.shared.pushAdapter.manualWillPresent(
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
    }

    @objc(didReceiveNotificationResponse:)
    public static func didReceive(_ response: UNNotificationResponse) {
        let request = response.notification.request
        NottiFacade.shared.pushAdapter.manualDidReceive(
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
    }
}

extension NottiNotificationPayload {
    /// `title` and `body` only when present, `data` always.
    var objcDictionary: NSDictionary {
        var result: [String: Any] = ["data": data]
        if let title { result["title"] = title }
        if let body { result["body"] = body }
        return result as NSDictionary
    }
}

extension NottiInAppClick {
    /// Exactly `messageId`, `buttonId` and `action`; `action` is `{type, value}` or `NSNull`, never absent
    /// (RN `InAppClick.payload`).
    var objcDictionary: NSDictionary {
        let actionValue: Any = action.map { ["type": $0.type.rawValue, "value": $0.value] as NSDictionary } ?? NSNull()
        return ["messageId": messageId, "buttonId": buttonId, "action": actionValue] as NSDictionary
    }
}
