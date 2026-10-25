import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-29, IAM-30. Port of RN `NottiInAppEventStoreTests` (0.8.0) plus the continuity cases of AD-019
/// decision 2. Contract literals (the key, the record keys, 7 days, 100) are written out here, never read
/// from the store's constants. Synthetic values only.
final class NottiInAppEventStoreTests: XCTestCase {

    private let appId = "fixture-app"
    private let otherApp = "fixture-other-app"
    private let messageId = "fixture-message"
    private let day: Int64 = 24 * 60 * 60 * 1000
    private let key = "notti_pending_inapp_events"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var now: Int64 = 1_000_000_000_000
    private var store: NottiInAppEventStore!

    override func setUp() {
        super.setUp()
        suiteName = "NottiInAppEventStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        now = 1_000_000_000_000
        store = makeStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    private func makeStore() -> NottiInAppEventStore {
        NottiInAppEventStore(defaults: defaults, clock: { [unowned self] in self.now })
    }

    private func storedObjects() throws -> [[String: Any]] {
        let data = try XCTUnwrap(defaults.data(forKey: key))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func isLowercaseUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil && value == value.lowercased() && value.count == 36
    }

    private func captureLogs(_ body: () -> Void) -> [(NottiLogLevel, String)] {
        let sink = LogSink()
        var levels: [NottiLogLevel] = []
        let levelLock = NSLock()
        let savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in
            levelLock.lock(); levels.append(level); levelLock.unlock()
            sink.append(message)
        }
        defer {
            NottiLogger.sink = nil
            NottiLogger.level = savedLevel
        }
        body()
        return Array(zip(levels, sink.messages))
    }

    // MARK: - Persistence and identity (IAM-29, IAM-30)

    func test_recordsSurviveANewStoreInInsertionOrderWithEveryField() throws {
        let impression = store.enqueue(appId: appId, messageId: messageId, type: "impression")
        now += 5
        let click = store.enqueue(appId: appId, messageId: messageId, type: "click", buttonId: "fixture-button")
        now += 5
        let dismiss = store.enqueue(appId: otherApp, messageId: messageId, type: "dismiss", reason: "close_button")

        let reread = makeStore().all()

        XCTAssertEqual(reread, [impression, click, dismiss])
        XCTAssertEqual(reread.map(\.appId), [appId, appId, otherApp])
        XCTAssertEqual(reread.map(\.occurredAtMs), [1_000_000_000_000, 1_000_000_000_005, 1_000_000_000_010])
        XCTAssertEqual(reread[1].buttonId, "fixture-button")
        XCTAssertNil(reread[1].reason)
        XCTAssertEqual(reread[2].reason, "close_button")
        XCTAssertNil(reread[2].buttonId)
        XCTAssertNil(reread[0].buttonId)
        XCTAssertNil(reread[0].reason)
    }

    func test_idAndEventIdAreDistinctLowercaseUUIDsStableAcrossInstances() {
        let first = makeStore().enqueue(appId: appId, messageId: messageId, type: "impression")
        let second = store.enqueue(appId: appId, messageId: messageId, type: "impression")

        for record in [first, second] {
            XCTAssertTrue(isLowercaseUUID(record.id), "id must be a lowercase UUID")
            XCTAssertTrue(isLowercaseUUID(record.eventId), "eventId must be a lowercase UUID")
            XCTAssertNotEqual(record.id, record.eventId)
        }
        XCTAssertNotEqual(first.eventId, second.eventId)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(makeStore().all().map(\.eventId), [first.eventId, second.eventId])
        XCTAssertEqual(makeStore().all().map(\.id), [first.id, second.id])
    }

    func test_allReturnsInsertionOrderAndRemoveDeletesOnlyThatRecord() {
        let first = store.enqueue(appId: appId, messageId: "m1", type: "impression")
        let second = store.enqueue(appId: appId, messageId: "m2", type: "impression")
        let third = store.enqueue(appId: appId, messageId: "m3", type: "impression")
        XCTAssertEqual(store.all().map(\.id), [first.id, second.id, third.id])

        store.remove(id: second.id)
        store.remove(id: "fixture-unknown")

        XCTAssertEqual(store.all().map(\.id), [first.id, third.id])
        XCTAssertEqual(makeStore().all().map(\.id), [first.id, third.id])
    }

    func test_allForAppNeverReturnsAnotherAppsRecords() {
        let mine = store.enqueue(appId: appId, messageId: "m1", type: "impression")
        store.enqueue(appId: otherApp, messageId: "m2", type: "impression")
        let mineLater = store.enqueue(appId: appId, messageId: "m3", type: "impression")

        XCTAssertEqual(store.all(forApp: appId).map(\.id), [mine.id, mineLater.id])
        XCTAssertEqual(store.all(forApp: otherApp).count, 1)
        XCTAssertTrue(store.all(forApp: "fixture-unknown").isEmpty)
    }

    // MARK: - RN continuity (AD-019 decision 2)

    func test_aQueueWrittenByReactNativeDecodesIntoTheSameRecords() throws {
        let rnJson = """
        [{"id":"00000000-0000-4000-8000-000000000001","eventId":"00000000-0000-4000-8000-000000000002",\
        "appId":"fixture-app","messageId":"fixture-message","type":"impression","occurredAtMs":1000000000000},\
        {"id":"00000000-0000-4000-8000-000000000003","eventId":"00000000-0000-4000-8000-000000000004",\
        "appId":"fixture-app","messageId":"fixture-message","type":"click","buttonId":"fixture-button",\
        "occurredAtMs":1000000000001},\
        {"id":"00000000-0000-4000-8000-000000000005","eventId":"00000000-0000-4000-8000-000000000006",\
        "appId":"fixture-app","messageId":"fixture-message","type":"dismiss","reason":"swipe",\
        "occurredAtMs":1000000000002}]
        """
        defaults.set(Data(rnJson.utf8), forKey: "notti_pending_inapp_events")

        let records = makeStore().all()

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.map(\.id), [
            "00000000-0000-4000-8000-000000000001",
            "00000000-0000-4000-8000-000000000003",
            "00000000-0000-4000-8000-000000000005"
        ])
        XCTAssertEqual(records.map(\.eventId), [
            "00000000-0000-4000-8000-000000000002",
            "00000000-0000-4000-8000-000000000004",
            "00000000-0000-4000-8000-000000000006"
        ])
        XCTAssertEqual(records.map(\.appId), ["fixture-app", "fixture-app", "fixture-app"])
        XCTAssertEqual(records.map(\.messageId), ["fixture-message", "fixture-message", "fixture-message"])
        XCTAssertEqual(records.map(\.type), ["impression", "click", "dismiss"])
        XCTAssertEqual(records.map(\.buttonId), [nil, "fixture-button", nil])
        XCTAssertEqual(records.map(\.reason), [nil, nil, "swipe"])
        XCTAssertEqual(records.map(\.occurredAtMs), [1_000_000_000_000, 1_000_000_000_001, 1_000_000_000_002])
    }

    func test_theWrittenDataHasExactlyTheReactNativeKeysUnderTheReactNativeKey() throws {
        store.enqueue(appId: appId, messageId: messageId, type: "impression")
        store.enqueue(appId: appId, messageId: messageId, type: "click", buttonId: "fixture-button")
        store.enqueue(appId: appId, messageId: messageId, type: "dismiss", reason: "auto")

        let objects = try storedObjects()
        let required: Set<String> = ["id", "eventId", "appId", "messageId", "type", "occurredAtMs"]
        XCTAssertEqual(objects.count, 3)
        XCTAssertEqual(Set(objects[0].keys), required)
        XCTAssertEqual(Set(objects[1].keys), required.union(["buttonId"]))
        XCTAssertEqual(Set(objects[2].keys), required.union(["reason"]))
        XCTAssertEqual(objects[1]["buttonId"] as? String, "fixture-button")
        XCTAssertEqual(objects[2]["reason"] as? String, "auto")
        XCTAssertEqual((objects[0]["occurredAtMs"] as? NSNumber)?.int64Value, 1_000_000_000_000)
        XCTAssertEqual(defaults.persistentDomain(forName: suiteName).map { Array($0.keys) }, [key])
    }

    func test_theStoredJsonContainsNoTokenAndNoDeviceId() throws {
        store.enqueue(appId: appId, messageId: messageId, type: "click", buttonId: "fixture-button")
        store.enqueue(appId: appId, messageId: messageId, type: "dismiss", reason: "outside_tap")

        let raw = try XCTUnwrap(String(bytes: try XCTUnwrap(defaults.data(forKey: key)), encoding: .utf8))
        XCTAssertFalse(raw.contains("token"))
        XCTAssertFalse(raw.contains("device_id"))
        XCTAssertFalse(raw.contains("deviceId"))
        XCTAssertFalse(raw.contains("device"))
    }

    // MARK: - Limits (IAM-30)

    func test_the101stRecordDropsTheOldest() {
        let ids = (0..<101).map { store.enqueue(appId: appId, messageId: "m\($0)", type: "impression").id }

        let stored = store.all()
        XCTAssertEqual(stored.count, 100)
        XCTAssertEqual(stored.map(\.id), Array(ids.dropFirst()))
    }

    func test_aRecordExactly7DaysOldIsKeptAndOneMillisecondOlderIsDropped() {
        let record = store.enqueue(appId: appId, messageId: messageId, type: "impression")
        let sevenDays: Int64 = 604_800_000

        XCTAssertTrue(store.expire(now: record.occurredAtMs + sevenDays).isEmpty)
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.expire(now: record.occurredAtMs + sevenDays + 1).map(\.id), [record.id])
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(makeStore().all().isEmpty)
    }

    func test_expireReturnsOnlyTheExpiredRecordsAndDefaultsToTheClock() {
        let old = store.enqueue(appId: appId, messageId: "old", type: "impression")
        now += day
        let recent = store.enqueue(appId: appId, messageId: "recent", type: "impression")

        XCTAssertEqual(store.expire(now: old.occurredAtMs + 7 * day + 1).map(\.id), [old.id])
        XCTAssertEqual(store.all().map(\.id), [recent.id])

        now += 7 * day + 1
        XCTAssertEqual(store.expire().map(\.id), [recent.id])
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_enqueueDropsExpiredRecordsFirst() {
        store.enqueue(appId: appId, messageId: "old", type: "impression")
        now += 1
        let kept = store.enqueue(appId: appId, messageId: "kept", type: "impression")
        now += 604_800_000

        let fresh = store.enqueue(appId: appId, messageId: "fresh", type: "impression")

        XCTAssertEqual(store.all().map(\.id), [kept.id, fresh.id])
    }

    // MARK: - App purge (IAM-30)

    func test_purgeOtherAppsRemovesOtherAppsAndKeepsTheCurrentAppInOrder() {
        let first = store.enqueue(appId: appId, messageId: "m1", type: "impression")
        store.enqueue(appId: otherApp, messageId: "m2", type: "impression")
        let second = store.enqueue(appId: appId, messageId: "m3", type: "click", buttonId: "fixture-button")
        store.enqueue(appId: otherApp, messageId: "m4", type: "dismiss", reason: "auto")

        store.purgeOtherApps(appId)

        XCTAssertEqual(store.all().map(\.id), [first.id, second.id])
        XCTAssertEqual(makeStore().all().map(\.id), [first.id, second.id])
    }

    func test_purgeOtherAppsIsANoOpWhenEveryRecordMatches() throws {
        store.enqueue(appId: appId, messageId: "m1", type: "impression")
        store.enqueue(appId: appId, messageId: "m2", type: "impression")
        let before = try XCTUnwrap(defaults.data(forKey: key))

        store.purgeOtherApps(appId)

        XCTAssertEqual(defaults.data(forKey: key), before)
        XCTAssertEqual(store.all().count, 2)
    }

    // MARK: - Self-heal

    func test_corruptBytesSelfHealToEmptyWithOneContentFreeWarning() throws {
        defaults.set(Data("fixture not json".utf8), forKey: key)

        var records: [NottiInAppEventRecord] = []
        let logs = captureLogs { records = store.all() }

        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.0, .warn)
        XCTAssertFalse(try XCTUnwrap(logs.first?.1).contains("fixture"))
        store.enqueue(appId: appId, messageId: messageId, type: "impression")
        XCTAssertEqual(store.all().count, 1)
    }

    func test_aRecordWithoutAppIdSelfHealsTheWholeQueueToEmpty() throws {
        let json = """
        [{"id":"00000000-0000-4000-8000-000000000001","eventId":"00000000-0000-4000-8000-000000000002",\
        "messageId":"fixture-message","type":"impression","occurredAtMs":1000000000000}]
        """
        defaults.set(Data(json.utf8), forKey: key)

        var records: [NottiInAppEventRecord] = []
        let logs = captureLogs { records = store.all() }

        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(logs.map(\.0), [.warn])
        XCTAssertFalse(try XCTUnwrap(logs.first?.1).contains("fixture-message"))
        XCTAssertFalse(try XCTUnwrap(logs.first?.1).contains("00000000"))
    }

    func test_aValueOfTheWrongTypeSelfHealsToEmpty() {
        defaults.set("fixture not data", forKey: key)

        var records: [NottiInAppEventRecord] = []
        let logs = captureLogs { records = store.all() }

        XCTAssertTrue(records.isEmpty)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(logs.map(\.0), [.warn])
    }

    func test_anEmptyQueueLogsNothing() {
        let logs = captureLogs {
            XCTAssertTrue(store.all().isEmpty)
            store.purgeOtherApps(appId)
            XCTAssertTrue(store.expire(now: now).isEmpty)
        }
        XCTAssertTrue(logs.isEmpty)
    }

    // MARK: - Independence from the CTR queue

    func test_theCtrQueueKeyIsUntouchedByEveryOperation() throws {
        let ctr = Data("fixture-ctr-queue".utf8)
        defaults.set(ctr, forKey: "notti_pending_events")

        let first = store.enqueue(appId: appId, messageId: "m1", type: "impression")
        store.enqueue(appId: otherApp, messageId: "m2", type: "impression")
        _ = store.all()
        _ = store.all(forApp: appId)
        store.purgeOtherApps(appId)
        store.remove(id: first.id)
        store.expire(now: now + 604_800_001)
        defaults.set(Data("fixture corrupt".utf8), forKey: key)
        _ = captureLogs { _ = store.all() }

        XCTAssertEqual(defaults.data(forKey: "notti_pending_events"), ctr)
    }

    func test_fillingTheInAppQueueNeverEvictsThePushEventQueue() {
        let push = NottiEventStore(defaults: defaults)
        _ = push.enqueue(notificationId: "fixture-notification", deliveryId: "fixture-delivery", type: "received")

        for index in 0..<101 { store.enqueue(appId: appId, messageId: "m\(index)", type: "impression") }

        XCTAssertEqual(push.all().count, 1)
        XCTAssertEqual(store.all().count, 100)
    }
}
