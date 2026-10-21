import UIKit
import UserNotifications
import NottiSDK

/// The five `Notti.Notifications` forwarding methods, behind a seam so tests can count them.
protocol ForwardingSink {
    func didRegister(deviceToken: Data)
    func didFail(error: Error)
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult
    func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions
    func didReceive(_ response: UNNotificationResponse)
}

struct LiveForwardingSink: ForwardingSink {
    func didRegister(deviceToken: Data) {
        Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func didFail(error: Error) {
        Notti.Notifications.didFailToRegisterForRemoteNotifications(error: error)
    }

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        Notti.Notifications.didReceiveRemoteNotification(userInfo)
    }

    func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        Notti.Notifications.willPresent(notification)
    }

    func didReceive(_ response: UNNotificationResponse) {
        Notti.Notifications.didReceive(response)
    }
}

/// Forwards to the SDK only when `Info.plist` carries `NottiDisableSwizzling = true` (the
/// `Debug-Manual` configuration, EXR-04). In the default mode nothing is forwarded, so the SDK's own
/// swizzling is the only path and a double observation is never masked.
struct ManualForwarding {
    static let plistKey = "NottiDisableSwizzling"

    let isEnabled: Bool
    let sink: ForwardingSink

    init(isEnabled: Bool, sink: ForwardingSink = LiveForwardingSink()) {
        self.isEnabled = isEnabled
        self.sink = sink
    }

    init(bundle: Bundle = .main, sink: ForwardingSink = LiveForwardingSink()) {
        self.init(isEnabled: bundle.object(forInfoDictionaryKey: Self.plistKey) as? Bool == true, sink: sink)
    }

    func didRegister(deviceToken: Data) {
        guard isEnabled else { return }
        sink.didRegister(deviceToken: deviceToken)
    }

    func didFail(error: Error) {
        guard isEnabled else { return }
        sink.didFail(error: error)
    }

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        guard isEnabled else { return .noData }
        return sink.didReceiveRemoteNotification(userInfo)
    }

    func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        guard isEnabled else { return [] }
        return sink.willPresent(notification)
    }

    func didReceive(_ response: UNNotificationResponse) {
        guard isEnabled else { return }
        sink.didReceive(response)
    }
}
