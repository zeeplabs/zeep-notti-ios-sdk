import UIKit
import UserNotifications
import NottiSDK

/// Excerpts the README shows. This file is compiled into the app target and never called, so a snippet
/// that stops compiling fails the example build. `scripts/check-readme-snippets.sh` keeps the README
/// text equal to the `README:begin` / `README:end` regions below. Placeholders only: no real appId or key.
enum IntegrationSnippets {
    static func initialize() {
        // README:begin init
        Notti.initialize(appId: "YOUR_APP_ID", clientKey: "YOUR_CLIENT_KEY")

        Task {
            let granted = await Notti.Notifications.requestPermission()
            print("push permission granted: \(granted)")
        }
        // README:end init
    }

    static func identity() {
        // README:begin identity
        Notti.login("user-123")
        Notti.User.setEmail("person@example.invalid")
        Notti.User.addTags(["plan": "premium", "locale": "pt-BR"])
        Notti.User.removeTag("locale")

        Notti.logout()
        // README:end identity
    }

    static func listeners() {
        // README:begin listeners
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
        // README:end listeners
    }

    static func inAppMessages() {
        // README:begin in-app
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
        // README:end in-app
    }
}

// README:begin manual-forwarding
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
// README:end manual-forwarding
