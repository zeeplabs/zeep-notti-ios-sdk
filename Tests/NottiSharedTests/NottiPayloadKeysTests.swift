import XCTest
@testable import NottiShared

/// Freezes the payload key strings. A change here breaks the backend contract
/// and parity with react-native-notti 0.6.0.
final class NottiPayloadKeysTests: XCTestCase {
    func test_keyValuesAreFrozen() {
        XCTAssertEqual(NottiPayloadKeys.aps, "aps")
        XCTAssertEqual(NottiPayloadKeys.notificationId, "notification_id")
        XCTAssertEqual(NottiPayloadKeys.deliveryId, "delivery_id")
        XCTAssertEqual(NottiPayloadKeys.imageUrl, "notti_image_url")
        XCTAssertEqual(
            NottiPayloadKeys.internalKeys,
            [
                "aps", "from", "collapse_key", "fcm_options", "content-available",
                "mutable-content", "content_available", "mutable_content", "notti_image_url"
            ]
        )
        XCTAssertEqual(NottiPayloadKeys.internalKeyPrefixes, ["gcm.", "google.", "aps."])
    }
}
