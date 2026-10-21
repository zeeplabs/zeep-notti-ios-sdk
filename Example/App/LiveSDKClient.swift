import Foundation
import NottiSDK

/// The real SDK behind `ExampleSDKClient`. Every public member of `Notti`, `Notti.User` and
/// `Notti.Notifications` is called from here or from `ManualForwarding` (EXR-02, drift guard T5).
struct LiveSDKClient: ExampleSDKClient {
    func initialize(appId: String, clientKey: String, baseUrl: String?) {
        Notti.initialize(appId: appId, clientKey: clientKey, options: Notti.Options(baseUrl: baseUrl))
    }

    func requestPermission() async -> Bool {
        await Notti.Notifications.requestPermission()
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        Notti.Notifications.requestPermission(completion: completion)
    }

    func login(_ externalUserId: String) { Notti.login(externalUserId) }
    func logout() { Notti.logout() }
    func setEmail(_ email: String) { Notti.User.setEmail(email) }
    func clearEmail() { Notti.User.clearEmail() }
    func setPhone(_ phone: String) { Notti.User.setPhone(phone) }
    func clearPhone() { Notti.User.clearPhone() }
    func addTag(_ key: String, value: String) { Notti.User.addTag(key, value: value) }
    func addTags(_ tags: [String: String]) { Notti.User.addTags(tags) }
    func removeTag(_ key: String) { Notti.User.removeTag(key) }
    func removeTags(_ keys: [String]) { Notti.User.removeTags(keys) }
    func setSubscription(_ enabled: Bool) { Notti.User.setSubscription(enabled) }
    func setLocationSharingEnabled(_ enabled: Bool) { Notti.setLocationSharingEnabled(enabled) }

    func setLogLevel(_ level: ExampleLogLevel) {
        switch level {
        case .none: Notti.logLevel = .none
        case .error: Notti.logLevel = .error
        case .warn: Notti.logLevel = .warn
        case .info: Notti.logLevel = .info
        case .debug: Notti.logLevel = .debug
        case .verbose: Notti.logLevel = .verbose
        }
    }

    func currentLogLevel() -> ExampleLogLevel {
        switch Notti.logLevel {
        case .none: return .none
        case .error: return .error
        case .warn: return .warn
        case .info: return .info
        case .debug: return .debug
        case .verbose: return .verbose
        @unknown default: return .error
        }
    }

    func deviceId() -> String? { Notti.deviceId }

    func addReceivedListener(_ handler: @escaping PayloadHandler) -> () -> Void {
        let subscription = Notti.Notifications.addReceivedListener { payload in
            let keys = Self.keys(of: payload)
            Task { @MainActor in handler(keys) }
        }
        return { subscription.remove() }
    }

    func addClickedListener(_ handler: @escaping PayloadHandler) -> () -> Void {
        let subscription = Notti.Notifications.addClickedListener { payload in
            let keys = Self.keys(of: payload)
            Task { @MainActor in handler(keys) }
        }
        return { subscription.remove() }
    }

    func addDeviceIdChangedListener(_ handler: @escaping @MainActor @Sendable (String) -> Void) -> () -> Void {
        let subscription = Notti.addDeviceIdChangedListener { id in
            Task { @MainActor in handler(id) }
        }
        return { subscription.remove() }
    }

    func takeInitialClick() -> [String]? {
        Notti.Notifications.takeInitialClick().map(Self.keys(of:))
    }

    /// Key names only. `title` and `body` count as keys by presence; no value is read out.
    private static func keys(of payload: NottiNotificationPayload) -> [String] {
        var keys = Array(payload.data.keys)
        if payload.title != nil { keys.append("title") }
        if payload.body != nil { keys.append("body") }
        return keys
    }
}
