import Foundation

// Objective-C interop layer (API-13). Swift namespaces (`Notti.User`, ...) are
// invisible to Objective-C, so these three `NSObject` classes expose the same
// capabilities under the ObjC names `Notti`, `NottiUser` and `NottiNotifications`.
// The Swift names carry an `ObjC` suffix because `Notti` is the Swift namespace
// enum. Swift hosts should use `Notti`; these classes exist for Objective-C hosts
// and the React Native bridge.
//
// The layer bridges types only (`String?`, `NSDictionary`, blocks, `NSArray`) and
// forwards to `NottiFacade.shared`: no behavior of its own, except dropping
// non-string tag values through `NottiRuntime.sanitizeTags` (RN parity).
//
// Notification payloads reach Objective-C as an `NSDictionary` with `title` and
// `body` (absent when the push has none) and `data` (string keys and values).

/// Objective-C name: `Notti`. Initialize, identity, location sharing and log level.
@objc(Notti)
@available(iOSApplicationExtension, unavailable)
public final class NottiObjC: NSObject {

    /// Starts the SDK. `baseUrl` may be `nil` (default host). Invalid values are
    /// logged without their content and ignored.
    @objc(initializeWithAppId:clientKey:baseUrl:)
    public static func initialize(appId: String, clientKey: String, baseUrl: String?) {
        NottiFacade.shared.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
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

    @objc(removeTags:)
    public static func removeTags(_ keys: [String]) {
        NottiFacade.shared.removeTags(keys)
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

    /// The notification that launched the app, once; `nil` afterwards.
    @objc(takeInitialClick)
    public static func takeInitialClick() -> NSDictionary? {
        NottiFacade.shared.takeInitialClick()?.objcDictionary
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
