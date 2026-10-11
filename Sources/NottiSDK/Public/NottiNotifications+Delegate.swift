import UIKit
import UserNotifications

/// Manual forwarding for hosts that turn delegate swizzling off (`NottiDisableSwizzling` = `YES` in
/// `Info.plist`). Call each method from the matching delegate callback of the app. They feed the same
/// internal entry points as the swizzled path, so the result is the same.
///
/// While swizzling is on, every call here is ignored with one warning in the log, so an event is never
/// processed twice. Calls made before `Notti.initialize` are buffered like the swizzled path.
@available(iOSApplicationExtension, unavailable)
extension Notti.Notifications {

    /// Forward from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        NottiFacade.shared.pushAdapter.manualDidRegister(deviceToken: deviceToken)
    }

    /// Forward from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    public static func didFailToRegisterForRemoteNotifications(error: Error) {
        NottiFacade.shared.pushAdapter.manualDidFail(error: error)
    }

    /// Forward from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and pass the
    /// returned result (`.noData`) to its completion handler, or choose your own.
    @discardableResult
    public static func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) -> UIBackgroundFetchResult {
        NottiFacade.shared.pushAdapter.manualDidReceiveRemoteNotification(userInfo: userInfo)
    }

    /// Forward from `userNotificationCenter(_:willPresent:withCompletionHandler:)`. Returns
    /// `[.banner, .list, .sound, .badge]` for a Notti push and `[]` for anything else; the host may use,
    /// combine or ignore the value.
    @discardableResult
    public static func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        let request = notification.request
        return NottiFacade.shared.pushAdapter.manualWillPresent(
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
    }

    /// Forward from `userNotificationCenter(_:didReceive:withCompletionHandler:)`. The host still calls
    /// its own completion handler.
    public static func didReceive(_ response: UNNotificationResponse) {
        let request = response.notification.request
        NottiFacade.shared.pushAdapter.manualDidReceive(
            actionIdentifier: response.actionIdentifier,
            userInfo: request.content.userInfo,
            identifier: request.identifier
        )
    }
}
