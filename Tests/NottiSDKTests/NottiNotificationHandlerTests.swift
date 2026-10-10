// Ported from react-native-notti 52e4b55 ios/Tests/NottiPushDelegateTests.swift (AD-002, design.md "Test Port Plan").
// Changes: the 15 RN tests drive `NottiNotificationHandler` with plain inputs instead of KVC-built
// `UNNotification`/`UNNotificationResponse` fixtures (those, and the completion-handler checks, move to
// `delegate-integration`); `NottiImpl.eventStore` / `NottiEventBuffer.shared` -> an isolated `NottiRuntime`
// per test. Renamed (RN-specific wording): `...StillBuffersTheJSClickForAColdStart` ->
// `...StillBuffersTheClickForAColdStart`, `...DoesNotEmitTheJSClickEvent` -> `...DoesNotBufferAClick`.
// New tests after the `// MARK: - Added` line (CORE-04, SDK-17 core layer).

import UserNotifications
import XCTest
@testable import NottiSDK

final class NottiNotificationHandlerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var handler: NottiNotificationHandler!
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiNotificationHandlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        runtime = makeRuntime()
        handler = NottiNotificationHandler(runtime: runtime)
    }

    override func tearDown() {
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        handler = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeRuntime() -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        return NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { $0("apns-token-fixture") }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
    }

    private func makeRemoteUserInfo(notificationId: String?, deliveryId: String?) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Hello", "body": "World"]]]
        if let notificationId = notificationId { userInfo["notification_id"] = notificationId }
        if let deliveryId = deliveryId { userInfo["delivery_id"] = deliveryId }
        return userInfo
    }

    private func willPresent(_ userInfo: [AnyHashable: Any], identifier: String = "test-notification") {
        XCTAssertTrue(handler.handleWillPresent(userInfo: userInfo, identifier: identifier))
    }

    private func didReceive(_ userInfo: [AnyHashable: Any], actionIdentifier: String, identifier: String = "test-notification") {
        handler.handleResponse(actionIdentifier: actionIdentifier, userInfo: userInfo, identifier: identifier)
    }

    private func drain(_ core: NottiCore?, file: StaticString = #filePath, line: UInt = #line) {
        guard let core else {
            XCTFail("no core", file: file, line: line)
            return
        }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func eventRequests() -> [(path: String, body: [String: Any])] {
        StubURLProtocol.recordedRequests()
            .filter { $0.url?.path.hasSuffix("/events") == true }
            .map { request in
                let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
                return (request.url?.path ?? "", body)
            }
    }

    // MARK: - willPresent (received)

    func test_willPresentWithNotificationAndDeliveryIdsEnqueuesAReceivedEvent() {
        willPresent(makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"))

        let events = runtime.eventStore.all()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.notificationId, "n-1")
        XCTAssertEqual(events.first?.deliveryId, "d-1")
        XCTAssertEqual(events.first?.type, "received")
    }

    func test_willPresentWithoutIdsSkipsEnqueue() {
        willPresent(makeRemoteUserInfo(notificationId: nil, deliveryId: nil))

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_willPresentWithAnEmptyIdSkipsEnqueue() {
        willPresent(makeRemoteUserInfo(notificationId: "", deliveryId: "d-1"))

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_willPresentWithAnEmptyDeliveryIdSkipsEnqueue() {
        willPresent(makeRemoteUserInfo(notificationId: "n-1", deliveryId: ""))

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_willPresentForANonRemotePushSkipsEnqueueEvenWithIds() {
        let userInfo: [AnyHashable: Any] = ["notification_id": "n-1", "delivery_id": "d-1"]
        willPresent(userInfo)

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - didReceive: body tap (opened + clicked) / action button (clicked)

    func test_didReceiveDefaultActionWithIdsEnqueuesExactlyOneOpenedAndOneClicked() {
        // SDKOPEN-01/03: the body tap is reported as both `opened` and `clicked`
        // so CTR keeps counting body taps (D1).
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        let events = runtime.eventStore.all()
        XCTAssertEqual(events.map(\.type), ["opened", "clicked"])
        XCTAssertTrue(events.allSatisfy { $0.notificationId == "n-1" && $0.deliveryId == "d-1" })
    }

    func test_didReceiveDefaultActionWithAURLInDataEnqueuesTheSameOpenedAndClickedPair() {
        // SDKOPEN-03 / D1: a URL in custom data does not change the events.
        var userInfo = makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1")
        userInfo["url"] = "https://example.com/promo"
        userInfo["deep_link"] = "app://orders/42"
        didReceive(userInfo, actionIdentifier: UNNotificationDefaultActionIdentifier)

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["opened", "clicked"])
    }

    func test_didReceiveDefaultActionStillBuffersTheClickForAColdStart() {
        // SDKOPEN-02/10: nothing listens on a cold start; the event is queued
        // natively and the payload stays available to `takeInitialClick()`.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["opened", "clicked"])
        XCTAssertNotNil(runtime.eventBuffer.takeInitialClick())
    }

    func test_eachDefaultActionResponseEnqueuesItsOwnOpenedAndClickedPair() {
        // SDKOPEN-04: one `didReceive` per tap, one pair per `didReceive`.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        didReceive(
            makeRemoteUserInfo(notificationId: "n-2", deliveryId: "d-2"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        let events = runtime.eventStore.all()
        XCTAssertEqual(events.map(\.deliveryId), ["d-1", "d-1", "d-2", "d-2"])
        XCTAssertEqual(events.map(\.type), ["opened", "clicked", "opened", "clicked"])
    }

    func test_didReceiveCustomActionEnqueuesOneClickedEventAndNoOpened() {
        // SDKOPEN-05 / D2: a category action button is `clicked` only; the
        // backend already counts a clicked delivery as opened.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: "CUSTOM_ACTION"
        )

        let events = runtime.eventStore.all()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.notificationId, "n-1")
        XCTAssertEqual(events.first?.deliveryId, "d-1")
        XCTAssertEqual(events.first?.type, "clicked")
    }

    func test_didReceiveCustomActionDoesNotBufferAClick() {
        // SDKOPEN-07: the click event stays body-tap only.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: "CUSTOM_ACTION"
        )

        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
    }

    func test_didReceiveDefaultActionWithoutIdsSkipsEnqueue() {
        // SDKOPEN-08.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: nil),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_didReceiveCustomActionWithoutIdsSkipsEnqueue() {
        // SDKOPEN-08.
        didReceive(
            makeRemoteUserInfo(notificationId: nil, deliveryId: nil),
            actionIdentifier: "CUSTOM_ACTION"
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_didReceiveCustomActionForANonRemotePushSkipsEnqueueEvenWithIds() {
        // SDKOPEN-08: a local notification's action is not this SDK's event.
        didReceive(
            ["notification_id": "n-1", "delivery_id": "d-1"],
            actionIdentifier: "CUSTOM_ACTION"
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_didReceiveDismissActionSkipsEnqueueEvenWithIds() {
        // SDKOPEN-06.
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: UNNotificationDismissActionIdentifier
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_didReceiveNonRemotePushSkipsEnqueueEvenWithIds() {
        didReceive(
            ["notification_id": "n-1", "delivery_id": "d-1"],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - Added

    /// SDK-17 (core layer): a foreground remote push reaches the received
    /// handler with the parsed payload; a non-remote one does not.
    func test_willPresentEmitsTheParsedPayloadToTheReceivedHandlerOnlyForARemotePush() {
        var payloads: [[String: Any]] = []
        runtime.eventBuffer.setHandler(.received) { payloads.append($0) }

        var userInfo = makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1")
        userInfo["promo"] = "fixture"
        willPresent(userInfo, identifier: "req-1")
        willPresent(["notification_id": "n-2", "delivery_id": "d-2"], identifier: "req-2")

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["title"] as? String, "Hello")
        XCTAssertEqual(payloads.first?["body"] as? String, "World")
        XCTAssertEqual(
            payloads.first?["data"] as? [String: String],
            ["notification_id": "n-1", "delivery_id": "d-1", "promo": "fixture"]
        )
    }

    /// SDK-18 / SDKOPEN-02 (core layer): with a click handler attached, a body
    /// tap is delivered to it once and is not left buffered; dismiss emits nothing.
    func test_bodyTapEmitsOneClickToTheAttachedHandlerAndDismissEmitsNothing() {
        var clicks: [[String: Any]] = []
        runtime.eventBuffer.setHandler(.clicked) { clicks.append($0) }

        let userInfo = makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1")
        didReceive(userInfo, actionIdentifier: UNNotificationDefaultActionIdentifier, identifier: "req-1")
        didReceive(userInfo, actionIdentifier: UNNotificationDismissActionIdentifier, identifier: "req-2")

        XCTAssertEqual(clicks.count, 1)
        XCTAssertEqual(clicks.first?["title"] as? String, "Hello")
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["opened", "clicked"])
    }

    /// CORE-04: an event handled before `start` is persisted, and the first
    /// successful registration flushes it with its original ids.
    func test_coldStartEventsHandledBeforeStartAreFlushedAfterRegistration() {
        XCTAssertNil(runtime.core)
        didReceive(
            makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"),
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        XCTAssertEqual(runtime.eventStore.all().map(\.type), ["opened", "clicked"])
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty, "no core, no network")

        StubURLProtocol.enqueue(.echoDevice()) // registration
        StubURLProtocol.enqueue(.status(204)) // opened
        StubURLProtocol.enqueue(.status(204)) // clicked
        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        drain(runtime.core)

        let events = eventRequests()
        XCTAssertEqual(events.map(\.path), Array(repeating: "/v1/apps/app-fixture/notifications/n-1/events", count: 2))
        XCTAssertEqual(events.compactMap { $0.body["type"] as? String }, ["opened", "clicked"])
        XCTAssertEqual(events.compactMap { $0.body["delivery_id"] as? String }, ["d-1", "d-1"])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    /// RN `enqueueIfReportable`: with a registered core, handling an event
    /// triggers an opportunistic flush through `runtime.core`.
    func test_eventHandledWithARegisteredCoreIsFlushedRightAway() {
        StubURLProtocol.enqueue(.echoDevice()) // registration
        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        drain(runtime.core)

        StubURLProtocol.enqueue(.status(204)) // received
        willPresent(makeRemoteUserInfo(notificationId: "n-1", deliveryId: "d-1"))
        drain(runtime.core)

        XCTAssertEqual(eventRequests().compactMap { $0.body["type"] as? String }, ["received"])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }
}
