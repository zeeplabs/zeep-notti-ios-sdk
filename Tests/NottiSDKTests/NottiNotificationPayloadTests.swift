import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiNotificationPayloadTests: XCTestCase {

    func test_fullPayloadMapsAllThreeFields() {
        let payload = NottiNotificationPayload(eventPayload: [
            "title": "Title fixture",
            "body": "Body fixture",
            "data": ["screen": "inbox", "id": "42"]
        ])

        XCTAssertEqual(payload.title, "Title fixture")
        XCTAssertEqual(payload.body, "Body fixture")
        XCTAssertEqual(payload.data, ["screen": "inbox", "id": "42"])
    }

    func test_titleOnlyLeavesBodyNil() {
        let payload = NottiNotificationPayload(eventPayload: ["title": "Only title", "data": [String: String]()])

        XCTAssertEqual(payload.title, "Only title")
        XCTAssertNil(payload.body)
        XCTAssertEqual(payload.data, [:])
    }

    func test_bodyOnlyLeavesTitleNil() {
        let payload = NottiNotificationPayload(eventPayload: ["body": "Only body"])

        XCTAssertNil(payload.title)
        XCTAssertEqual(payload.body, "Only body")
    }

    func test_missingDataBecomesAnEmptyDictionary() {
        let payload = NottiNotificationPayload(eventPayload: [:])

        XCTAssertNil(payload.title)
        XCTAssertNil(payload.body)
        XCTAssertEqual(payload.data, [:])
    }

    func test_nonStringDataValuesAreDroppedAndStringsKept() {
        let payload = NottiNotificationPayload(eventPayload: [
            "data": ["keep": "yes", "number": 7, "null": NSNull(), "nested": ["a": 1]] as [String: Any]
        ])

        XCTAssertEqual(payload.data, ["keep": "yes"])
    }

    func test_aNonDictionaryDataValueBecomesAnEmptyDictionary() {
        let payload = NottiNotificationPayload(eventPayload: ["title": "t", "data": "not-a-dictionary"])

        XCTAssertEqual(payload.title, "t")
        XCTAssertEqual(payload.data, [:])
    }

    func test_nilTitleAndBodyBoxedAsOptionalAnyAreTreatedAsAbsent() {
        let missing: String? = nil
        let payload = NottiNotificationPayload(eventPayload: ["title": missing as Any, "body": missing as Any])

        XCTAssertNil(payload.title)
        XCTAssertNil(payload.body)
    }

    /// The key names come from `ParsedNotification.toEventPayload()`, so a rename
    /// there breaks this test instead of silently emptying the payload.
    func test_aPayloadBuiltByTheCoreParsingRoundTrips() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Title fixture", "body": "Body fixture"]],
            "notification_id": "n-fixture",
            "delivery_id": "d-fixture",
            "screen": "inbox",
            "count": 3
        ]
        let parsed = parseUserInfo(userInfo)

        let payload = NottiNotificationPayload(eventPayload: parsed.toEventPayload())

        XCTAssertEqual(payload.title, "Title fixture")
        XCTAssertEqual(payload.body, "Body fixture")
        XCTAssertEqual(payload.data["screen"], "inbox")
        XCTAssertEqual(payload.data["count"], "3")
        XCTAssertNil(payload.data["aps"])
        XCTAssertEqual(payload, NottiNotificationPayload(title: parsed.title, body: parsed.body, data: parsed.data))
    }

    func test_aSilentPushBuiltByTheNotificationHandlerHasNoTitleOrBody() throws {
        let suiteName = "NottiNotificationPayloadTests.\(UUID().uuidString)"
        let runtimeDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { runtimeDefaults.removePersistentDomain(forName: suiteName) }
        let runtime = NottiRuntime(
            defaults: runtimeDefaults,
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            startObservers: false
        )
        let handler = NottiNotificationHandler(runtime: runtime)
        var received: [String: Any]?
        runtime.eventBuffer.setHandler(.received) { received = $0 }

        handler.handleWillPresent(
            userInfo: ["aps": ["content-available": 1], "k": "v"],
            identifier: "id-fixture"
        )

        let payload = NottiNotificationPayload(eventPayload: try XCTUnwrap(received))
        XCTAssertNil(payload.title)
        XCTAssertNil(payload.body)
        XCTAssertEqual(payload.data, ["k": "v"])
    }
}
