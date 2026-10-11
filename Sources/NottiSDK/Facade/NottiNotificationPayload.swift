import Foundation

/// A notification delivered to the host's `received` or `clicked` listener, or
/// returned by `takeInitialClick()`.
///
/// Carries only what RN's `NotificationPayload` carries: the alert `title` and
/// `body` (absent for a silent push) and the integrator's own `data`, with the
/// transport metadata (`aps`, `gcm.*`, ...) already removed.
public struct NottiNotificationPayload: Equatable, Sendable {
    public let title: String?
    public let body: String?
    public let data: [String: String]

    init(title: String?, body: String?, data: [String: String]) {
        self.title = title
        self.body = body
        self.data = data
    }

    /// Builds the typed payload from the `[String: Any]` the core's event buffer
    /// holds (`ParsedNotification.toEventPayload()`). A missing or non-dictionary
    /// `data` becomes `[:]`, and a `data` value that is not a string is dropped
    /// (RN parity). Never throws.
    init(eventPayload: [String: Any]) {
        let rawData = eventPayload[Keys.data] as? [String: Any] ?? [:]
        self.init(
            title: eventPayload[Keys.title] as? String,
            body: eventPayload[Keys.body] as? String,
            data: rawData.compactMapValues { $0 as? String }
        )
    }

    /// Key names of `ParsedNotification.toEventPayload()`, which has no shared
    /// constants. The handler round-trip test fails if they drift.
    private enum Keys {
        static let title = "title"
        static let body = "body"
        static let data = "data"
    }
}
