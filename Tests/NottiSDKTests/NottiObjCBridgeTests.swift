import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// API-13: the `@objc` classes only bridge types and reach the facade. They run
/// here (Swift calling the ObjC-facing classes) against an isolated facade; the
/// `NottiSDKObjCTests` target proves the same surface compiles from Objective-C.
final class NottiObjCBridgeTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    private final class Log {
        private let lock = NSLock()
        private var items: [NSDictionary] = []
        func append(_ value: NSDictionary) { lock.withLock { items.append(value) } }
        var values: [NSDictionary] { lock.withLock { items } }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var sessions: [URLSession] = []
    private var savedLevel: NottiLogLevel = .error
    private var swizzlingActive = false

    override func setUp() {
        super.setUp()
        swizzlingActive = false
        StubURLProtocol.reset()
        suiteName = "NottiObjCBridgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("apns-token-fixture") },
                permissionRequester: { $0(true) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        facade = NottiFacade(
            runtime: runtime,
            dispatcher: { $0() },
            isSwizzlingActive: { [weak self] in self?.swizzlingActive ?? false }
        )
        NottiFacade.setSharedForTesting(facade)
    }

    override func tearDown() {
        NottiFacade.setSharedForTesting(nil)
        NottiLogger.level = savedLevel
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        facade = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func patchBodies() -> [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "PATCH" }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
    }

    private func initializeThroughObjC() {
        StubURLProtocol.enqueue(.echoDevice())
        NottiObjC.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
    }

    // MARK: - Tests

    func test_nonStringTagValuesAreDroppedThroughTheObjCPath() {
        initializeThroughObjC()
        StubURLProtocol.enqueue(.echoDevice())
        let tags: [AnyHashable: Any] = ["plan": "vip", "count": NSNumber(value: 3), "flag": true, 7: "numeric-key"]

        NottiUserObjC.addTags(tags)
        drain()

        let sent = patchBodies().compactMap { $0["tags"] as? [String: String] }
        XCTAssertEqual(sent, [["plan": "vip"]])
    }

    func test_userMethodsReachTheFacade() {
        initializeThroughObjC()
        for _ in 0..<4 { StubURLProtocol.enqueue(.echoDevice()) }

        NottiUserObjC.addTag("lang", value: "pt")
        NottiUserObjC.removeTags(["lang"])
        NottiUserObjC.setEmail("user@example.invalid")
        NottiUserObjC.setSubscription(false)
        drain()

        let sent = patchBodies()
        XCTAssertTrue(sent.contains { ($0["tags"] as? [String: String]) == ["lang": "pt"] })
        XCTAssertTrue(sent.contains { ($0["tags"] as? [String: String]) == [:] })
        XCTAssertTrue(sent.contains { $0["email"] as? String == "user@example.invalid" })
        XCTAssertTrue(sent.contains { $0["subscribed"] as? Bool == false })
    }

    func test_nottiObjCReachesTheFacade() {
        NottiObjC.setLocationSharingEnabled(true)
        XCTAssertTrue(NottiDeviceStore(defaults: defaults).getLocationSharingEnabled())
        NottiObjC.logLevel = .verbose
        XCTAssertEqual(NottiLogger.level, .verbose)
        XCTAssertNil(NottiObjC.deviceId)
        NottiDeviceStore(defaults: defaults).setDeviceId("device-fixture")
        XCTAssertEqual(NottiObjC.deviceId, "device-fixture")

        initializeThroughObjC()
        StubURLProtocol.enqueue(.echoDevice())
        NottiObjC.login("user-fixture")
        drain()
        XCTAssertTrue(patchBodies().contains { $0["external_user_id"] as? String == "user-fixture" })
    }

    func test_listenersReceiveTheNSDictionaryShapeAndTakeInitialClickReturnsIt() {
        let received = Log()
        let subscription = NottiNotificationsObjC.addReceivedListener { received.append($0) }
        let full = ParsedNotification(title: "Title fixture", body: "Body fixture", data: ["id": "n-1"]).toEventPayload()
        runtime.eventBuffer.emit(.received, identifier: "n-1", payload: full)
        subscription.remove()

        XCTAssertEqual(received.values.count, 1)
        let dict = received.values.first
        XCTAssertEqual(dict?["title"] as? String, "Title fixture")
        XCTAssertEqual(dict?["body"] as? String, "Body fixture")
        XCTAssertEqual(dict?["data"] as? [String: String], ["id": "n-1"])

        let silent = ParsedNotification(title: nil, body: nil, data: [:]).toEventPayload()
        runtime.eventBuffer.emit(.clicked, identifier: "n-2", payload: silent)
        let initial = NottiNotificationsObjC.takeInitialClick()
        XCTAssertNil(initial?["title"], "absent, not NSNull")
        XCTAssertNil(initial?["body"])
        XCTAssertEqual(initial?["data"] as? [String: String], [:])
        XCTAssertNil(NottiNotificationsObjC.takeInitialClick())
    }

    func test_clickedListenerAndDeviceIdListenerReachTheFacade() {
        let clicks = Log()
        let clickSub = NottiNotificationsObjC.addClickedListener { clicks.append($0) }
        let ids = Log()
        let idSub = NottiObjC.addDeviceIdChangedListener { ids.append(["id": $0]) }

        runtime.eventBuffer.emit(
            .clicked,
            identifier: "n-3",
            payload: ParsedNotification(title: "T", body: "B", data: [:]).toEventPayload()
        )
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-new-fixture","tags":{}}"#))
        NottiObjC.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
        clickSub.remove()
        idSub.remove()

        XCTAssertEqual(clicks.values.count, 1)
        XCTAssertEqual(ids.values.first?["id"] as? String, "device-new-fixture")
    }

    func test_requestPermissionCompletionReachesTheFacade() {
        initializeThroughObjC()
        let done = expectation(description: "permission")
        NottiNotificationsObjC.requestPermission { granted in
            XCTAssertTrue(granted)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    // MARK: - Manual forwarding (DEL-12)

    private func fixtureNotification() -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "aps": ["alert": ["title": "Title fixture", "body": "Body fixture"]],
            "notification_id": "n-1",
            "delivery_id": "d-1"
        ]
        let request = UNNotificationRequest(identifier: "req-1", content: content, trigger: nil)
        guard let notification = (UNNotification.self as NSObject.Type).init() as? UNNotification else {
            fatalError("could not allocate UNNotification")
        }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    private func fixtureResponse() -> UNNotificationResponse {
        guard let response = (UNNotificationResponse.self as NSObject.Type).init() as? UNNotificationResponse else {
            fatalError("could not allocate UNNotificationResponse")
        }
        response.setValue(fixtureNotification(), forKey: "notification")
        response.setValue(UNNotificationDefaultActionIdentifier, forKey: "actionIdentifier")
        return response
    }

    func test_objcManualForwardingReachesTheAdapter() {
        let options = NottiNotificationsObjC.willPresent(fixtureNotification())
        NottiNotificationsObjC.didReceive(fixtureResponse())
        let result = NottiNotificationsObjC.didReceiveRemoteNotification(["aps": ["content-available": 1], "delivery_id": "d-s"])

        XCTAssertEqual(options, [.banner, .list, .sound, .badge])
        XCTAssertEqual(result, .noData)
        XCTAssertEqual(Set(runtime.eventStore.all().map(\.type)), ["received", "opened", "clicked"])
        XCTAssertEqual(NottiNotificationsObjC.takeInitialClick()?["title"] as? String, "Title fixture")
    }

    func test_objcManualForwardingIsIgnoredWhileSwizzlingIsActive() {
        swizzlingActive = true

        NottiNotificationsObjC.didRegisterForRemoteNotifications(deviceToken: Data([0x01]))
        NottiNotificationsObjC.didFailToRegisterForRemoteNotifications(error: NSError(domain: "fixture.apns", code: 1))
        NottiNotificationsObjC.didReceive(fixtureResponse())
        let result = NottiNotificationsObjC.didReceiveRemoteNotification(["aps": ["content-available": 1], "delivery_id": "d-s"])

        XCTAssertEqual(result, .noData)
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
        XCTAssertNil(NottiNotificationsObjC.takeInitialClick())
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }
}
