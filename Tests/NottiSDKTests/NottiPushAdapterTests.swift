import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// `NottiPushAdapter` over an isolated runtime: the swizzled path and the manual path, with plain inputs.
final class NottiPushAdapterTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"
    private let allOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var adapter: NottiPushAdapter!
    private var swizzlingActive = false
    private var sessions: [URLSession] = []
    private var logs: [(NottiLogLevel, String)] = []
    private let logLock = NSLock()
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiPushAdapterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        logs = []
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
        swizzlingActive = false
        runtime = makeRuntime()
        adapter = NottiPushAdapter(runtime: runtime, isSwizzlingActive: { [unowned self] in self.swizzlingActive })
    }

    override func tearDown() {
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        adapter = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
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
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
    }

    private func startCore() {
        StubURLProtocol.enqueue(.echoDevice()) // registration
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
        StubURLProtocol.reset()
    }

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else {
            XCTFail("no core", file: file, line: line)
            return
        }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func makeRemoteUserInfo(notificationId: String? = "n-1", deliveryId: String? = "d-1") -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = ["aps": ["alert": ["title": "Hello", "body": "World"]]]
        if let notificationId = notificationId { userInfo["notification_id"] = notificationId }
        if let deliveryId = deliveryId { userInfo["delivery_id"] = deliveryId }
        return userInfo
    }

    private func makeSilentUserInfo() -> [AnyHashable: Any] {
        ["aps": ["content-available": 1], "notification_id": "n-1", "delivery_id": "d-1"]
    }

    private var postBodies: [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "POST" }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
    }

    private var capturedLogs: [(NottiLogLevel, String)] {
        logLock.withLock { logs }
    }

    private var storedTypes: [String] {
        runtime.eventStore.all().map(\.type)
    }

    // MARK: - Token

    func test_didRegisterReachesTheRuntimeOnceWithTheHexToken() {
        startCore()
        StubURLProtocol.enqueue(.echoDevice())

        adapter.didRegister(deviceToken: Data([0xAB, 0x01, 0xFF]))
        drain()

        XCTAssertEqual(postBodies.count, 1)
        XCTAssertEqual(postBodies.first?["token"] as? String, "ab01ff")
    }

    func test_didFailLogsDomainAndCodeOnlyAndRegistersNothing() {
        startCore()
        let error = NSError(
            domain: "fixture.apns",
            code: 3000,
            userInfo: [NSLocalizedDescriptionKey: "entitlement problem for https://notti.example.invalid/v1/apps/app-fixture"]
        )

        adapter.didFail(error: error)
        drain()

        let errors = capturedLogs.filter { $0.0 == .error }.map(\.1)
        XCTAssertEqual(errors, ["Notti: failed to register for remote notifications - fixture.apns#3000"])
        XCTAssertFalse(capturedLogs.contains { $0.1.contains("entitlement") || $0.1.contains("example.invalid") })
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }

    // MARK: - willPresent

    func test_willPresentForANottiPushReportsOnceAndReturnsTheD2Options() {
        let options = adapter.willPresent(userInfo: makeRemoteUserInfo(), identifier: "req-1")

        XCTAssertEqual(options, allOptions)
        XCTAssertEqual(storedTypes, ["received"])
    }

    func test_willPresentForALocalNotificationReturnsNoOptionsAndReportsNothing() {
        var emitted = 0
        runtime.eventBuffer.setHandler(.received) { _ in emitted += 1 }

        let options = adapter.willPresent(userInfo: ["notification_id": "n-1", "delivery_id": "d-1"], identifier: "req-1")

        XCTAssertEqual(options, [])
        XCTAssertEqual(emitted, 0)
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_willPresentForARemotePushWithoutANonEmptyNotificationIdReturnsNoOptionsAndReportsNothing() {
        var emitted = 0
        runtime.eventBuffer.setHandler(.received) { _ in emitted += 1 }

        XCTAssertEqual(adapter.willPresent(userInfo: makeRemoteUserInfo(notificationId: nil), identifier: "req-1"), [])
        XCTAssertEqual(adapter.willPresent(userInfo: makeRemoteUserInfo(notificationId: ""), identifier: "req-2"), [])

        XCTAssertEqual(emitted, 0)
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - didReceive

    func test_bodyTapQueuesOneOpenedAndOneClicked() {
        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: makeRemoteUserInfo(),
            identifier: "req-1"
        )

        XCTAssertEqual(storedTypes, ["opened", "clicked"])
    }

    func test_dismissQueuesNothing() {
        adapter.didReceive(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: makeRemoteUserInfo(),
            identifier: "req-1"
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    /// Closes STATE F7: the `didReceive` path itself, not only the handler, queues nothing for an empty id.
    func test_didReceiveWithAnEmptyDeliveryIdQueuesNoReport() {
        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: makeRemoteUserInfo(deliveryId: ""),
            identifier: "req-1"
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    func test_aLocalNotificationResponseIsNeitherParsedNorReported() {
        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["notification_id": "n-1", "delivery_id": "d-1"],
            identifier: "req-1"
        )

        XCTAssertTrue(runtime.eventStore.all().isEmpty)
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
    }

    func test_coldStartTapBeforeInitializeIsBufferedOnceAndReportsAreQueued() {
        XCTAssertNil(runtime.core)

        adapter.didReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: makeRemoteUserInfo(),
            identifier: "req-1"
        )

        XCTAssertEqual(storedTypes, ["opened", "clicked"])
        let click = runtime.eventBuffer.takeInitialClick()
        XCTAssertEqual(click?["title"] as? String, "Hello")
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
    }

    // MARK: - Silent push

    func test_silentPushReportsReceivedAndReturnsNoData() {
        let result = adapter.didReceiveRemoteNotification(userInfo: makeSilentUserInfo())

        XCTAssertEqual(result, .noData)
        XCTAssertEqual(storedTypes, ["received"])
    }

    func test_visiblePushOnTheSilentPathReportsNothingAndReturnsNoData() {
        let result = adapter.didReceiveRemoteNotification(userInfo: makeRemoteUserInfo())

        XCTAssertEqual(result, .noData)
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    // MARK: - Manual path

    func test_manualEntryPointsFeedTheSameCallsWhenSwizzlingIsOff() {
        startCore()
        StubURLProtocol.enqueue(.echoDevice())

        adapter.manualDidRegister(deviceToken: Data([0x01, 0x02]))
        drain()
        XCTAssertEqual(postBodies.first?["token"] as? String, "0102")

        XCTAssertEqual(adapter.manualWillPresent(userInfo: makeRemoteUserInfo(), identifier: "req-1"), allOptions)
        adapter.manualDidReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: makeRemoteUserInfo(),
            identifier: "req-1"
        )
        XCTAssertEqual(adapter.manualDidReceiveRemoteNotification(userInfo: makeSilentUserInfo()), .noData)
        adapter.manualDidFail(error: NSError(domain: "fixture.apns", code: 1))

        XCTAssertEqual(Set(storedTypes), ["received", "opened", "clicked"])
        XCTAssertFalse(capturedLogs.contains { $0.0 == .warn })
        XCTAssertEqual(capturedLogs.filter { $0.0 == .error }.count, 1)
    }

    func test_manualEntryPointsAreIgnoredWithOneWarnEachWhileSwizzlingIsActive() {
        startCore()
        swizzlingActive = true
        let sentinelToken = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let userInfo = makeRemoteUserInfo(notificationId: "n-sentinel", deliveryId: "d-sentinel")

        let calls: [() -> Void] = [
            { self.adapter.manualDidRegister(deviceToken: sentinelToken) },
            { self.adapter.manualDidFail(error: NSError(domain: "fixture.sentinel", code: 77)) },
            { _ = self.adapter.manualWillPresent(userInfo: userInfo, identifier: "req-sentinel") },
            {
                self.adapter.manualDidReceive(
                    actionIdentifier: UNNotificationDefaultActionIdentifier,
                    userInfo: userInfo,
                    identifier: "req-sentinel"
                )
            },
            { _ = self.adapter.manualDidReceiveRemoteNotification(userInfo: self.makeSilentUserInfo()) }
        ]
        for (index, call) in calls.enumerated() {
            call()
            XCTAssertEqual(capturedLogs.filter { $0.0 == .warn }.count, index + 1, "one warn per ignored call")
        }
        drain()

        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty, "no registration")
        XCTAssertTrue(runtime.eventStore.all().isEmpty, "nothing reported")
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
        XCTAssertEqual(capturedLogs.count, 5, "only the five warnings")
        for (_, message) in capturedLogs {
            for sentinel in ["deadbeef", "sentinel", "n-sentinel", "d-sentinel", "Hello", "World", "77"] {
                XCTAssertFalse(message.contains(sentinel), "log leaked \(sentinel)")
            }
        }
    }

    func test_manualWillPresentWhileSwizzlingIsActiveStillReturnsTheOptionsWithoutReporting() {
        swizzlingActive = true

        XCTAssertEqual(adapter.manualWillPresent(userInfo: makeRemoteUserInfo(), identifier: "req-1"), allOptions)
        XCTAssertEqual(adapter.manualWillPresent(userInfo: ["a": "b"], identifier: "req-2"), [])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }
}
