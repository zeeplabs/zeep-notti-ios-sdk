import XCTest
@testable import NottiSDK

/// Freezes the UserDefaults key names `NottiDeviceStore` writes (CORE-09).
///
/// The list is copied verbatim from react-native-notti `52e4b55`
/// (`ios/NottiDeviceStore.swift:88-117`). An app moving from RN 0.6.0 keeps its
/// device id, session counters and acks only if every key stays byte-identical.
/// The test writes through the store's public surface and reads the raw
/// persistent domain, so it checks the strings that actually reach disk.
final class NottiDeviceStoreKeysTests: XCTestCase {
    private static let frozenKeys: Set<String> = [
        "notti_device_id",
        "notti_last_token",
        "notti_external_user_id",
        "notti_subscribed",
        "notti_tags",
        "notti_app_version",
        "notti_first_session_at_ms",
        "notti_last_session_at_ms",
        "notti_session_count",
        "notti_session_time_ms",
        "notti_session_started_at_ms",
        "notti_location_sharing_enabled",
        "notti_session_last_seen_at_ms",
        "notti_pending_country_clear",
        "notti_last_synced_country",
        "notti_last_synced_device_os",
        "notti_last_synced_device_model",
        "notti_last_synced_sdk_version",
        "notti_last_synced_timezone_id",
        "notti_last_synced_language",
        "notti_last_synced_permission_status",
        "notti_last_unsubscribed_at_ms",
        "notti_pending_unsubscribe_at_ms",
        "notti_pending_permission_unsubscribe_at_ms",
        "notti_email",
        "notti_phone",
        "notti_last_synced_email",
        "notti_last_synced_phone",
        "notti_profile_field_ack_migrated"
    ]

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "NottiDeviceStoreKeysTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_everyPersistedKeyMatchesTheFrozenRNKeyList() {
        let store = NottiDeviceStore(defaults: defaults)
        // Each writer must land on exactly this key. The migration runs first
        // because it removes the six read-once profile-field keys.
        let writers: [(key: String, write: () -> Void)] = [
            ("notti_profile_field_ack_migrated", { store.migrateProfileFieldAckIfNeeded() }),
            ("notti_device_id", { store.setDeviceId("device-fixture-id") }),
            ("notti_last_token", { store.setLastToken("fixture-token") }),
            ("notti_external_user_id", { store.setExternalUserId("fixture-user") }),
            ("notti_subscribed", { store.setSubscribed(true) }),
            ("notti_tags", { store.setTags(["fixture": "1"]) }),
            ("notti_app_version", { store.setAppVersion("1.0.0") }),
            ("notti_first_session_at_ms", { store.setFirstSessionAtMs(1) }),
            ("notti_last_session_at_ms", { store.setLastSessionAtMs(2) }),
            ("notti_session_count", { store.setSessionCount(3) }),
            ("notti_session_time_ms", { store.setSessionTimeMs(4) }),
            ("notti_session_started_at_ms", { store.setSessionStartedAtMs(5) }),
            ("notti_location_sharing_enabled", { store.setLocationSharingEnabled(true) }),
            ("notti_session_last_seen_at_ms", { store.setSessionLastSeenAtMs(6) }),
            ("notti_pending_country_clear", { store.setPendingCountryClear(true) }),
            ("notti_last_synced_country", { store.setLastSyncedCountry("ZZ") }),
            ("notti_last_synced_device_os", { store.setLastSyncedDeviceOs("os-fixture") }),
            ("notti_last_synced_device_model", { store.setLastSyncedDeviceModel("model-fixture") }),
            ("notti_last_synced_sdk_version", { store.setLastSyncedSdkVersion("0.0.0") }),
            ("notti_last_synced_timezone_id", { store.setLastSyncedTimezoneId("UTC") }),
            ("notti_last_synced_language", { store.setLastSyncedLanguage("xx") }),
            ("notti_last_synced_permission_status", { store.setLastSyncedPermissionStatus("granted") }),
            ("notti_last_unsubscribed_at_ms", { store.setLastUnsubscribedAtMs(7) }),
            ("notti_pending_unsubscribe_at_ms", { store.setPendingUnsubscribeAtMs(8) }),
            ("notti_pending_permission_unsubscribe_at_ms", { store.setPendingPermissionUnsubscribeAtMs(9) }),
            ("notti_email", { store.setEmail("test@example.invalid") }),
            ("notti_phone", { store.setPhone("+00000000000") }),
            ("notti_last_synced_email", { store.setLastSyncedEmail("test@example.invalid") }),
            ("notti_last_synced_phone", { store.setLastSyncedPhone("+00000000000") })
        ]

        var written: Set<String> = []
        for writer in writers {
            let before = Set(persistedKeys())
            writer.write()
            let added = Set(persistedKeys()).subtracting(before)
            XCTAssertEqual(added, [writer.key], "writer for \(writer.key) persisted under \(added)")
            written.formUnion(added)
        }

        XCTAssertEqual(Set(writers.map(\.key)), Self.frozenKeys, "every frozen key needs a writer")
        XCTAssertEqual(written, Self.frozenKeys)
        XCTAssertEqual(Set(persistedKeys()), Self.frozenKeys)
    }

    /// The production runtime (`NottiRuntime.shared`) opens this suite. RN 0.6.0
    /// stores everything in `notti_prefs`; another name orphans migrated state.
    /// Asserted on the constant so the real suite is never opened or mutated.
    func test_productionSuiteNameMatchesRN() {
        XCTAssertEqual(NottiRuntime.defaultsSuiteName, "notti_prefs")
    }

    private func persistedKeys() -> [String] {
        Array((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)
    }
}
