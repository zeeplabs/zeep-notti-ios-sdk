// Split from react-native-notti 52e4b55 ios/NottiPushDelegate.swift:51-138 (AD-002, design.md "NottiNotificationHandler").
// Changes: takes plain inputs (`userInfo`, request identifier, action identifier) instead of
// `UNNotification`/`UNNotificationResponse`; `NottiEventBuffer.shared` / `NottiImpl.eventStore` /
// `NottiImpl.activeCore` -> the injected `NottiRuntime`; the completion-handler calls stay with the
// `UNUserNotificationCenterDelegate` adapter (`delegate-integration`); payload keys come from `NottiPayloadKeys`.
// The reporting decisions are unchanged.

import Foundation
import UserNotifications
#if canImport(NottiShared)
import NottiShared
#endif

/// What the SDK does with a remote notification: report `received` /
/// `opened` / `clicked` to the offline event store and hand the payload to the
/// event buffer. The `UNUserNotificationCenterDelegate` adapter that extracts
/// these inputs belongs to `delegate-integration`.
final class NottiNotificationHandler {

    private let runtime: NottiRuntime

    init(runtime: NottiRuntime) {
        self.runtime = runtime
    }

    /// Foreground receive (RN `willPresent`). Returns whether the notification
    /// should be presented: always `true`, as in RN, which called the completion
    /// handler with `[.banner, .list, .sound, .badge]` for every notification.
    @discardableResult
    func handleWillPresent(userInfo: [AnyHashable: Any], identifier: String) -> Bool {
        // I4 (found in pre-release review): the README has the host app hand
        // over its *single* `UNUserNotificationCenter` delegate, so this method
        // also runs for local notifications and any other push SDK's remote
        // notifications sharing the same app - neither should be parsed into
        // `payload.data` or reported as this SDK's own event. `aps` is present
        // only on a real APNs remote push; a local notification's `userInfo`
        // never carries it.
        if Self.isRemotePush(userInfo) {
            let parsed = parseUserInfo(userInfo)
            runtime.eventBuffer.emit(
                .received,
                identifier: identifier,
                payload: parsed.toEventPayload()
            )
            enqueueIfReportable(parsed, type: NottiEventType.received)
        }
        return true
    }

    /// Any-app-state response (RN `didReceive response:`).
    func handleResponse(actionIdentifier: String, userInfo: [AnyHashable: Any], identifier: String) {
        guard Self.isRemotePush(userInfo) else {
            return
        }
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            let parsed = parseUserInfo(userInfo)
            // Cold launch from a tap fires this before anything listens -
            // `NottiEventBuffer` holds the payload until a click handler exists
            // or `takeInitialClick()` consumes it.
            runtime.eventBuffer.emit(
                .clicked,
                identifier: identifier,
                payload: parsed.toEventPayload()
            )
            // A body tap is reported as both `opened` and `clicked` (one of each),
            // with or without a URL in `data`, so CTR keeps counting body taps
            // (opened-event-reporting D1).
            enqueueIfReportable(parsed, type: NottiEventType.opened)
            enqueueIfReportable(parsed, type: NottiEventType.clicked)
        case UNNotificationDismissActionIdentifier:
            // Delivered only when the category sets `customDismissAction`; a
            // dismissal is not engagement and is never reported.
            break
        default:
            // A button from a category the host app registered (`aps.category`).
            // Reported as `clicked` only: the backend already counts a clicked
            // delivery as opened (D2). No click event to the buffer, as before (A8).
            enqueueIfReportable(parseUserInfo(userInfo), type: NottiEventType.clicked)
        }
    }

    /// Queues the offline-reportable event for `parsed` when its payload carries
    /// both `notification_id` and `delivery_id` (the same detection rule as
    /// Android), then opportunistically triggers a flush through the live core.
    /// On cold start no core exists yet (`runtime.core` is nil), so the event
    /// simply stays queued until registration success, the next app
    /// foreground, or the network observer flushes it. Skipped silently
    /// otherwise.
    private func enqueueIfReportable(_ parsed: ParsedNotification, type: String) {
        guard let notificationId = parsed.data[NottiPayloadKeys.notificationId], !notificationId.isEmpty,
              let deliveryId = parsed.data[NottiPayloadKeys.deliveryId], !deliveryId.isEmpty
        else {
            return
        }
        _ = runtime.eventStore.enqueue(notificationId: notificationId, deliveryId: deliveryId, type: type)
        runtime.core?.onNetworkAvailable()
    }

    private static func isRemotePush(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo[NottiPayloadKeys.aps] != nil
    }
}
