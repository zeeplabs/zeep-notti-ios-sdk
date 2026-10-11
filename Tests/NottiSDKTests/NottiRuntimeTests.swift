import UIKit
import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiRuntimeTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtimes: [NottiRuntime] = []
    private var sessions: [URLSession] = []
    private var logs: [(NottiLogLevel, String)] = []
    private let logLock = NSLock()
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiRuntimeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        logs = []
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
    }

    override func tearDown() {
        for runtime in runtimes {
            let core = runtime.core
            runtime.stop()
            core?.waitForPendingWork(timeout: 20)
        }
        runtimes.removeAll()
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRuntime(
        providers: NottiPlatformProviders = NottiPlatformProviders(
            tokenProvider: { $0("apns-token-fixture") },
            permissionRequester: { $0(true) }
        ),
        pathMonitor: NottiPathMonitoring = FakePathMonitor(),
        sdkVersion: String = NottiSDKVersion.current,
        startObservers: Bool = false
    ) -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: providers,
            pathMonitor: pathMonitor,
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: sdkVersion,
            startObservers: startObservers
        )
        runtimes.append(runtime)
        return runtime
    }

    private func drain(_ core: NottiCore?, file: StaticString = #filePath, line: UInt = #line) {
        guard let core else {
            XCTFail("no core", file: file, line: line)
            return
        }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func bodies(_ method: String) -> [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == method }.map { request in
            let data = request.httpBody ?? Data()
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }

    private var capturedLogs: [(NottiLogLevel, String)] {
        logLock.withLock { logs }
    }

    // MARK: - CORE-05: sdk_version comes from the native constant

    func test_startSendsSdkVersionEqualToTheNativeConstant() {
        StubURLProtocol.enqueue(.echoDevice()) // registration
        StubURLProtocol.enqueue(.echoDevice()) // sdk_version PATCH
        let runtime = makeRuntime()

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)

        let patches = bodies("PATCH")
        XCTAssertFalse(NottiSDKVersion.current.isEmpty)
        XCTAssertEqual(patches.compactMap { $0["sdk_version"] as? String }, [NottiSDKVersion.current])
    }

    func test_startWithAnEmptySdkVersionOmitsTheField() {
        StubURLProtocol.enqueue(.echoDevice()) // registration
        let runtime = makeRuntime(sdkVersion: "")

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)

        XCTAssertEqual(bodies("POST").count, 1, "registration ran")
        XCTAssertTrue(bodies("PATCH").allSatisfy { $0["sdk_version"] == nil })
        XCTAssertNil(NottiDeviceStore(defaults: defaults).getLastSyncedSdkVersion())
    }

    // MARK: - start twice (RN JS-reload parity, SEGTEL-08 notes)

    func test_startTwiceInvalidatesTheFirstCoreAndTheSecondAdoptsTheOpenSession() {
        let backgroundTasks = LockedCounter()
        let providers = NottiPlatformProviders(
            tokenProvider: { _ in },
            permissionRequester: { $0(true) },
            appStateProvider: { $0(true) },
            beginBackgroundTask: {
                backgroundTasks.increment()
                return {}
            }
        )
        let runtime = makeRuntime(providers: providers)
        let store = NottiDeviceStore(defaults: defaults)

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        let first = runtime.core
        drain(first)
        let startedAt = store.getSessionStartedAtMs()
        XCTAssertNotNil(startedAt)
        XCTAssertTrue(runtime.sessionGate.isOpen)

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        let second = runtime.core
        drain(second)
        XCTAssertNotNil(second)
        XCTAssertFalse(first === second, "start builds a new core")
        XCTAssertEqual(store.getSessionCount(), 0, "the open session is not closed as an orphan")
        XCTAssertEqual(store.getSessionStartedAtMs(), startedAt, "the open session is adopted, not reopened")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        drain(first)
        drain(second)
        XCTAssertEqual(backgroundTasks.value, 1, "only the second core reacts: the first was invalidated")
        XCTAssertEqual(store.getSessionCount(), 1)
    }

    func test_stopInvalidatesAndClearsTheCore() {
        let backgroundTasks = LockedCounter()
        let providers = NottiPlatformProviders(
            tokenProvider: { _ in },
            permissionRequester: { $0(true) },
            beginBackgroundTask: {
                backgroundTasks.increment()
                return {}
            }
        )
        let runtime = makeRuntime(providers: providers)
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        let core = runtime.core
        drain(core)

        runtime.stop()

        XCTAssertNil(runtime.core)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        drain(core)
        XCTAssertEqual(backgroundTasks.value, 0, "a stopped core no longer observes lifecycle")
    }

    // MARK: - APNs callbacks

    func test_onApnsTokenConvertsBytesToLowercaseHexAndRegistersWithIt() {
        StubURLProtocol.enqueue(.echoDevice()) // registration
        let runtime = makeRuntime(providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }))
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty, "no token yet, no registration")

        runtime.onApnsToken(Data([0xAB, 0x01, 0xFF, 0x00, 0x7C]))
        drain(runtime.core)

        let posts = bodies("POST")
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?["token"] as? String, "ab01ff007c")
        XCTAssertEqual(NottiDeviceStore(defaults: defaults).getLastToken(), "ab01ff007c")
    }

    /// SDK-04 (core layer): a missing push prerequisite surfaces as the APNs
    /// failure callback. It is logged, never thrown, triggers no registration,
    /// and the core still registers once a token does arrive.
    func test_onApnsRegistrationFailedLogsDomainAndCodeWithoutRegisteringAndTheCoreStaysUsable() {
        let runtime = makeRuntime(providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }))
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)
        let error = NSError(
            domain: "fixture.apns",
            code: 3000,
            userInfo: [NSLocalizedDescriptionKey: "no valid aps-environment entitlement for https://notti.example.invalid/v1/apps/app-fixture"]
        )

        runtime.onApnsRegistrationFailed(error)
        drain(runtime.core)

        let errors = capturedLogs.filter { $0.0 == .error }.map(\.1)
        XCTAssertEqual(errors, ["Notti: failed to register for remote notifications - fixture.apns#3000"])
        XCTAssertFalse(errors.contains { $0.contains("entitlement") || $0.contains("example.invalid") })
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty, "no registration attempt")

        StubURLProtocol.enqueue(.echoDevice())
        runtime.onApnsToken(Data([0x01, 0x02]))
        drain(runtime.core)
        XCTAssertEqual(bodies("POST").first?["token"] as? String, "0102")
    }

    // MARK: - Network

    func test_onNetworkAvailableWithoutACoreIsANoOp() {
        let runtime = makeRuntime()
        _ = runtime.eventStore.enqueue(notificationId: "n-fixture", deliveryId: "d-fixture", type: NottiEventType.received)

        runtime.onNetworkAvailable()

        XCTAssertNil(runtime.core)
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
        XCTAssertEqual(runtime.eventStore.all().map(\.deliveryId), ["d-fixture"], "the event stays queued")
    }

    /// CORE-03: the network observer is started by the runtime and its
    /// reconnect callback reaches the live core (RN `NottiNetworkObserver.shared`).
    func test_networkObserverStartedByTheRuntimeFlushesQueuedEventsOnReconnect() {
        let monitor = FakePathMonitor()
        StubURLProtocol.enqueue(.status(503)) // registration fails: nothing flushes yet
        let runtime = makeRuntime(pathMonitor: monitor, startObservers: true)
        XCTAssertEqual(monitor.startCount, 1)
        let store = NottiDeviceStore(defaults: defaults)
        store.setLastToken("apns-token-fixture")
        _ = runtime.eventStore.enqueue(notificationId: "n-fixture", deliveryId: "d-fixture", type: NottiEventType.received)
        for _ in 0..<4 { StubURLProtocol.enqueue(.status(503)) } // registration retries
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)
        XCTAssertEqual(runtime.eventStore.all().count, 1)
        let before = StubURLProtocol.recordedRequests().count

        StubURLProtocol.enqueue(.status(204)) // event
        monitor.pathUpdateHandler?(.satisfied)
        drain(runtime.core)

        let events = StubURLProtocol.recordedRequests().dropFirst(before)
        XCTAssertEqual(events.map { $0.url?.path }, ["/v1/apps/app-fixture/notifications/n-fixture/events"])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)
    }

    /// CORE-03: the background observer closes the session gate even with no core (RN `processBackgroundObserver`).
    func test_backgroundObserverClosesTheSessionGateWithoutACore() {
        let runtime = makeRuntime(startObservers: true)
        XCTAssertTrue(runtime.sessionGate.tryOpen())

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertNil(runtime.core)
        XCTAssertFalse(runtime.sessionGate.isOpen)
    }

    // MARK: - Device id change

    func test_deviceIdChangeFromTheCoreReachesTheRuntimeHandler() {
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture","tags":{}}"#))
        let runtime = makeRuntime()
        let received = LockedStrings()
        runtime.onDeviceIdChanged = { received.append($0) }

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)

        XCTAssertEqual(received.values, ["device-fixture"])
    }

    // MARK: - Tags (RN NottiImpl.addTags filter; SDK-12, SDK-13 at the core layer)

    func test_sanitizeTagsKeepsOnlyStringKeysWithStringValues() {
        let input: [AnyHashable: Any] = [
            "plan": "vip",
            "count": 1,
            "ratio": 1.5,
            "flag": true,
            "none": NSNull(),
            42: "numeric-key",
            "empty": ""
        ]

        XCTAssertEqual(NottiRuntime.sanitizeTags(input), ["plan": "vip", "empty": ""])
    }

    /// SDK-12: addTags merges into the cached map and PATCHes the full result.
    func test_addTagsThroughTheRuntimeCorePatchesTheFullMergedMap() {
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture","tags":{"plan":"basic","lang":"pt"}}"#))
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime(sdkVersion: "")
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)

        runtime.core?.mutateTags(add: NottiRuntime.sanitizeTags(["plan": "vip", "tier": 2]), remove: nil)
        drain(runtime.core)

        let patches = bodies("PATCH")
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches.first?["tags"] as? [String: String], ["plan": "vip", "lang": "pt"])
        XCTAssertEqual(NottiDeviceStore(defaults: defaults).getTags(), ["plan": "vip", "lang": "pt"])
    }

    /// SDK-13: removeTags removes from the cached map and PATCHes the remaining map.
    func test_removeTagsThroughTheRuntimeCorePatchesTheRemainingMap() {
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture","tags":{"plan":"basic","lang":"pt"}}"#))
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime(sdkVersion: "")
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(runtime.core)

        runtime.core?.mutateTags(add: nil, remove: ["plan", "missing"])
        drain(runtime.core)

        let patches = bodies("PATCH")
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches.first?["tags"] as? [String: String], ["lang": "pt"])
        XCTAssertEqual(NottiDeviceStore(defaults: defaults).getTags(), ["lang": "pt"])
    }

    // MARK: - ensureCore (public-api API-05, API-07)

    func test_ensureCoreReturnsTheSameInstanceAndSetsTheCurrentCore() {
        let runtime = makeRuntime()
        XCTAssertNil(runtime.core)

        let first = runtime.ensureCore()
        let second = runtime.ensureCore()

        XCTAssertTrue(first === second)
        XCTAssertTrue(runtime.core === first)
    }

    func test_ensureCoreReturnsTheCoreCreatedByStart() {
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime(sdkVersion: "")
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        let started = runtime.core

        XCTAssertTrue(runtime.ensureCore() === started)
        drain(started)
    }

    func test_startAfterEnsureCoreInvalidatesTheEnsuredCoreAndInstallsANewOne() {
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime(sdkVersion: "")
        let ensured = runtime.ensureCore()

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        let started = runtime.core

        XCTAssertNotNil(started)
        XCTAssertFalse(started === ensured)
        drain(started)
        XCTAssertEqual(bodies("POST").count, 1, "the new core registered once")
    }

    func test_anUninitializedEnsuredCoreSendsNothingOnDidBecomeActive() {
        let runtime = makeRuntime(startObservers: false)
        let core = runtime.ensureCore()

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drain(core)

        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }

    func test_setEmailOnTheEnsuredCorePersistsInTheSuiteWithoutANetworkCall() {
        let runtime = makeRuntime()
        let core = runtime.ensureCore()

        core.setEmail("user@example.invalid")
        drain(core)

        XCTAssertEqual(NottiDeviceStore(defaults: defaults).getEmail(), "user@example.invalid")
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class LockedStrings {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.withLock { storage.append(value) } }
    var values: [String] { lock.withLock { storage } }
}
