import NottiSDKExtension
import UserNotifications

/// The same two-call Notification Service Extension as the iOS example, for macOS (AD-025): rich media from the
/// push payload, with the original content as the fallback.
@objc(NotificationServiceMac)
final class NotificationServiceMac: UNNotificationServiceExtension {
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
