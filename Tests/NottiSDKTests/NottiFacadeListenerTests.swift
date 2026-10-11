import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiFacadeListenerTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    private final class RecordingDispatcher {
        private let lock = NSLock()
        private var queue: [() -> Void] = []
        var pending: Int { lock.withLock { queue.count } }
        func dispatch(_ block: @escaping () -> Void) { lock.withLock { queue.append(block) } }
        func drain() {
            while true {
                let next: (() -> Void)? = lock.withLock { queue.isEmpty ? nil : queue.removeFirst() }
                guard let block = next else { return }
                block()
            }
        }
    }

    private final class Log {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ value: String) { lock.withLock { items.append(value) } }
        var values: [String] { lock.withLock { items } }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var dispatcher: RecordingDispatcher!
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiFacadeListenerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        dispatcher = RecordingDispatcher()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { $0("apns-token-fixture") }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        let recording = dispatcher!
        facade = NottiFacade(runtime: runtime, dispatcher: { recording.dispatch($0) })
    }

    override func tearDown() {
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

    private func emit(_ event: NottiNotificationEvent, id: String, title: String = "Title fixture") {
        let parsed = ParsedNotification(title: title, body: "Body fixture", data: ["id": id])
        runtime.eventBuffer.emit(event, identifier: id, payload: parsed.toEventPayload())
    }

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func register(deviceBody: String) {
        StubURLProtocol.enqueue(.status(200, body: deviceBody))
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
    }

    // MARK: - received

    func test_twoReceivedListenersGetALiveEventOnceInOrderThroughTheDispatcher() {
        let log = Log()
        _ = facade.addReceivedListener { log.append("A:\($0.data["id"] ?? "")") }
        _ = facade.addReceivedListener { log.append("B:\($0.data["id"] ?? "")") }

        emit(.received, id: "live-1")

        XCTAssertEqual(log.values, [], "delivery is never inline")
        XCTAssertEqual(dispatcher.pending, 1)
        dispatcher.drain()
        XCTAssertEqual(log.values, ["A:live-1", "B:live-1"])
    }

    func test_theFirstListenerGetsTheBufferedReplayAndTheSecondDoesNot() {
        emit(.received, id: "buffered-1")
        let first = Log()
        let second = Log()

        _ = facade.addReceivedListener { first.append($0.data["id"] ?? "") }
        _ = facade.addReceivedListener { second.append($0.data["id"] ?? "") }
        dispatcher.drain()

        XCTAssertEqual(first.values, ["buffered-1"])
        XCTAssertEqual(second.values, [])
    }

    func test_removingTheLastListenerDetachesSoLaterEventsAreBufferedForTheNextFirstListener() {
        let log = Log()
        let a = facade.addReceivedListener { log.append("A:\($0.data["id"] ?? "")") }
        let b = facade.addReceivedListener { log.append("B:\($0.data["id"] ?? "")") }
        a.remove()
        b.remove()

        emit(.received, id: "while-away")
        dispatcher.drain()
        XCTAssertEqual(log.values, [], "nobody listens, the event waits in the buffer")

        let next = Log()
        _ = facade.addReceivedListener { next.append($0.data["id"] ?? "") }
        dispatcher.drain()
        XCTAssertEqual(next.values, ["while-away"])
    }

    func test_aReceivedListenerRegisteredBeforeInitializeReceivesEvents() {
        let log = Log()
        _ = facade.addReceivedListener { log.append($0.data["id"] ?? "") }
        XCTAssertNil(runtime.core, "no initialize yet")

        emit(.received, id: "pre-init")
        dispatcher.drain()

        XCTAssertEqual(log.values, ["pre-init"])
    }

    func test_deliveredPayloadIsTheTypedPayload() {
        var delivered: NottiNotificationPayload?
        _ = facade.addReceivedListener { delivered = $0 }

        emit(.received, id: "typed-1", title: "Typed title")
        dispatcher.drain()

        XCTAssertEqual(
            delivered,
            NottiNotificationPayload(title: "Typed title", body: "Body fixture", data: ["id": "typed-1"])
        )
    }

    // MARK: - clicked and initial click

    func test_aColdStartClickIsNeverReplayedToListenersAndIsTakenOnce() {
        emit(.clicked, id: "cold-start")
        let log = Log()

        _ = facade.addClickedListener { log.append($0.data["id"] ?? "") }
        dispatcher.drain()
        XCTAssertEqual(log.values, [], "clicks are not replayed")

        let taken = facade.takeInitialClick()
        XCTAssertEqual(taken?.data["id"], "cold-start")
        XCTAssertEqual(taken?.title, "Title fixture")
        XCTAssertNil(facade.takeInitialClick(), "second call returns nil")
    }

    func test_aLiveClickReachesEveryClickedListener() {
        let log = Log()
        _ = facade.addClickedListener { log.append("A:\($0.data["id"] ?? "")") }
        _ = facade.addClickedListener { log.append("B:\($0.data["id"] ?? "")") }

        emit(.clicked, id: "live-click")
        dispatcher.drain()

        XCTAssertEqual(log.values, ["A:live-click", "B:live-click"])
        XCTAssertNil(facade.takeInitialClick(), "a delivered click is not an initial click")
    }

    // MARK: - deviceIdChanged

    func test_deviceIdChangedFiresOncePerRealChangeAndNotOnAReRegistrationWithTheSameId() {
        let log = Log()
        _ = facade.addDeviceIdChangedListener { log.append($0) }

        register(deviceBody: #"{"id":"device-one-fixture","tags":{}}"#)
        dispatcher.drain()
        XCTAssertEqual(log.values, ["device-one-fixture"])

        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-one-fixture","tags":{}}"#))
        facade.initialize(appId: "other-app-fixture", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        dispatcher.drain()
        XCTAssertEqual(log.values, ["device-one-fixture"], "same id again: no event")

        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-two-fixture","tags":{}}"#))
        facade.initialize(appId: "third-app-fixture", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        dispatcher.drain()
        XCTAssertEqual(log.values, ["device-one-fixture", "device-two-fixture"])
    }

    func test_everyDeviceIdListenerIsCalledAndARemovedOneIsNot() {
        let kept = Log()
        let removed = Log()
        _ = facade.addDeviceIdChangedListener { kept.append($0) }
        let subscription = facade.addDeviceIdChangedListener { removed.append($0) }

        register(deviceBody: #"{"id":"device-one-fixture","tags":{}}"#)
        dispatcher.drain()
        XCTAssertEqual(kept.values, ["device-one-fixture"])
        XCTAssertEqual(removed.values, ["device-one-fixture"])

        subscription.remove()
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-two-fixture","tags":{}}"#))
        facade.initialize(appId: "other-app-fixture", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        dispatcher.drain()

        XCTAssertEqual(kept.values, ["device-one-fixture", "device-two-fixture"])
        XCTAssertEqual(removed.values, ["device-one-fixture"], "not called again after remove()")
    }

    func test_removingTheLastDeviceIdListenerClearsTheRuntimeHandler() {
        let subscription = facade.addDeviceIdChangedListener { _ in }
        XCTAssertNotNil(runtime.onDeviceIdChanged)

        subscription.remove()

        XCTAssertNil(runtime.onDeviceIdChanged)
    }

    func test_aDeviceIdChangeIsDeliveredThroughTheDispatcher() {
        let log = Log()
        _ = facade.addDeviceIdChangedListener { log.append($0) }

        register(deviceBody: #"{"id":"device-one-fixture","tags":{}}"#)

        XCTAssertEqual(log.values, [], "never inline")
        XCTAssertEqual(dispatcher.pending, 1)
    }

    func test_afterTheLastClickedListenerIsRemovedAClickWaitsForTakeInitialClick() {
        let log = Log()
        let subscription = facade.addClickedListener { log.append($0.data["id"] ?? "") }
        subscription.remove()

        emit(.clicked, id: "while-away")
        dispatcher.drain()

        XCTAssertEqual(log.values, [])
        XCTAssertEqual(facade.takeInitialClick()?.data["id"], "while-away")
    }

    func test_aRemovedReceivedListenerIsNotCalledAgainWhileAnotherKeepsListening() {
        let kept = Log()
        let removed = Log()
        _ = facade.addReceivedListener { kept.append($0.data["id"] ?? "") }
        let subscription = facade.addReceivedListener { removed.append($0.data["id"] ?? "") }

        subscription.remove()
        emit(.received, id: "after-remove")
        dispatcher.drain()

        XCTAssertEqual(kept.values, ["after-remove"])
        XCTAssertEqual(removed.values, [])
    }
}
