import UIKit
import UserNotifications

/// App delegate used through `@UIApplicationDelegateAdaptor` (build flag `USE_ADAPTOR`).
///
/// Default mode: the SDK swizzles this class and sees each callback once; the forwarding below is
/// inert. `Debug-Manual` mode: `NottiDisableSwizzling` is on, so the app sets itself as the
/// notification-center delegate and forwards the five calls by hand.
final class ExampleAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let forwarding = ManualForwarding()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if forwarding.isEnabled {
            UNUserNotificationCenter.current().delegate = self
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        forwarding.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        forwarding.didFail(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(forwarding.didReceiveRemoteNotification(userInfo))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(forwarding.willPresent(notification))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        forwarding.didReceive(response)
        completionHandler()
    }
}
