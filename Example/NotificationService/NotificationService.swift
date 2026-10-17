// README:begin nse
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
// README:end nse
