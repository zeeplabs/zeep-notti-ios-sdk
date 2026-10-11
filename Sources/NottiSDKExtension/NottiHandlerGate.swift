import Foundation
import UserNotifications

/// Calls the host's content handler at most once, from any thread.
///
/// Every exit of a download (success, drop, deadline, expiry) goes through the gate, so "exactly one call"
/// does not depend on the order in which those exits race.
final class NottiHandlerGate {
    private let lock = NSLock()
    private var fired = false
    private let handler: (UNNotificationContent) -> Void

    init(_ handler: @escaping (UNNotificationContent) -> Void) {
        self.handler = handler
    }

    /// Returns `true` when this call ran the handler, `false` when an earlier call already did.
    /// The handler runs outside the lock.
    @discardableResult
    func fire(_ content: UNNotificationContent) -> Bool {
        let shouldCall = lock.withLock { () -> Bool in
            if fired { return false }
            fired = true
            return true
        }
        guard shouldCall else { return false }
        handler(content)
        return true
    }
}
