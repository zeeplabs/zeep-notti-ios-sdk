import Foundation
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// Downloads the media of a Notti push and attaches it, from a Notification Service Extension.
///
/// Wiring in the host's Notification Service Extension target (two forwarding calls, no download code):
///
/// ```swift
/// import NottiSDKExtension
/// import UserNotifications
///
/// @objc(NotificationService)
/// final class NotificationService: UNNotificationServiceExtension {
///     private var contentHandler: ((UNNotificationContent) -> Void)?
///     private var bestAttemptContent: UNNotificationContent?
///
///     override func didReceive(
///         _ request: UNNotificationRequest,
///         withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
///     ) {
///         self.contentHandler = contentHandler
///         bestAttemptContent = request.content
///         NottiNotificationServiceExtension.didReceive(request, withContentHandler: contentHandler)
///     }
///
///     override func serviceExtensionTimeWillExpire() {
///         guard let contentHandler else { return }
///         NottiNotificationServiceExtension.serviceExtensionTimeWillExpire(
///             for: bestAttemptContent, contentHandler: contentHandler
///         )
///     }
/// }
/// ```
///
/// Every outcome ends in exactly one handler call: the content with one attachment, or the original content
/// (invalid URL, non-https URL or redirect, network failure, over 10 MiB, 20 s deadline, expiry).
/// Nothing is logged with the URL, host, query, title or body.
@objc(NottiNotificationServiceExtension)
public final class NottiNotificationServiceExtension: NSObject {
    private override init() { super.init() }

    /// Forward `UNNotificationServiceExtension.didReceive(_:withContentHandler:)` here.
    @objc(didReceive:withContentHandler:)
    public static func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        didReceive(request, withContentHandler: contentHandler, environment: .live)
    }

    /// Forward `UNNotificationServiceExtension.serviceExtensionTimeWillExpire()` here with the best-attempt
    /// content. `nil` content does nothing.
    @objc(serviceExtensionTimeWillExpireFor:contentHandler:)
    public static func serviceExtensionTimeWillExpire(
        for content: UNNotificationContent?,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        serviceExtensionTimeWillExpire(for: content, contentHandler: contentHandler, environment: .live)
    }

    // MARK: - Internal, with an injectable environment

    static func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
        environment: NottiRichMediaEnvironment
    ) {
        guard let copy = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        switch NottiRichMediaURL.parse(request.content.userInfo) {
        case .absent:
            contentHandler(copy)
        case .invalid:
            NottiLogger.log(.error, "rich media dropped: \(NottiRichMediaDropReason.invalidURL.code)", category: "nse")
            contentHandler(copy)
        case .valid(let url):
            let job = NottiRichMediaJob(
                content: copy, gate: NottiHandlerGate(contentHandler), environment: environment
            )
            environment.registry.add(job)
            job.start(url: url)
        }
    }

    static func serviceExtensionTimeWillExpire(
        for content: UNNotificationContent?,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        environment: NottiRichMediaEnvironment
    ) {
        guard let content else { return }
        let jobs = environment.registry.jobs(matching: content.userInfo)
        guard !jobs.isEmpty else {
            contentHandler(content)
            return
        }
        for job in jobs { job.expire(with: content) }
    }
}
