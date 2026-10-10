import Foundation

/// Push payload keys shared by the app SDK and the Notification Service Extension.
///
/// Values are frozen: they are part of the contract with the `zeep-notti` backend
/// and match `react-native-notti` 0.6.0 (`52e4b55`) byte for byte.
package enum NottiPayloadKeys {
    /// APNs dictionary. Present only on a real remote push.
    package static let aps = "aps"
    /// Backend notification id. Required (with `deliveryId`) to report an event.
    package static let notificationId = "notification_id"
    /// Backend delivery id. Required (with `notificationId`) to report an event.
    package static let deliveryId = "delivery_id"
    /// Rich-push attachment URL, consumed by the NSE. Never part of `payload.data`.
    package static let imageUrl = "notti_image_url"

    /// Transport metadata that must never reach `payload.data`
    /// (RN `NottiNotificationParsing.swift:50-58`).
    package static let internalKeys: Set<String> = [
        aps, "from", "collapse_key", "fcm_options", "content-available",
        "mutable-content", "content_available", "mutable_content",
        imageUrl
    ]

    /// Key prefixes the OS / FCM inject that must never reach `payload.data`.
    package static let internalKeyPrefixes = ["gcm.", "google.", "aps."]
}
