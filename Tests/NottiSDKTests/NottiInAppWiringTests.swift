import UIKit
import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-01, 06, 11, 33, 51, 52: the two core hooks and the runtime wiring of the In-App engine (RN
/// `NottiCore.swift:763,1047`, `NottiImpl.swift:46-85`). Real `NottiCore`s over `StubURLProtocol`, an
/// isolated `NottiRuntime` with its own `NotificationCenter` for the process observers, and an engine on the
/// fake scheduler, network and presenter. The core's own lifecycle observers listen on
/// `NotificationCenter.default`, so a post there reaches the core and a post on `center` reaches only the
/// runtime. Synthetic values only; no real network, no `NottiRuntime.shared`.
final class NottiInAppWiringTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://notti.example.invalid"
    private static let registered = #"{"id":"fixture-device","tags":{}}"#

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var engine: NottiInAppEngine!
    private var center: NotificationCenter!
    private var sessions: [URLSession] = []
    private var cores: [NottiCore] = []
    private var runtimes: [NottiRuntime] = []
    private var savedLevel = NottiLogLevel.error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        savedLevel = NottiLogger.level
        suiteName = "NottiInAppWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
        center = NotificationCenter()
        let clock = scheduler!
        let network = self.network!
        engine = NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) }),
            identity: NottiInAppEngine.deviceIdentity(defaults: defaults),
            presenter: presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { $0() },
            clientFactory: { network.transport(appId: $0.appId) }
        )
    }

    override func tearDown() {
        for runtime in runtimes {
            let core = runtime.core
            runtime.stop()
            core?.waitForPendingWork(timeout: 20)
        }
        runtimes.removeAll()
        for core in cores { core.waitForPendingWork(timeout: 20) }
        cores.removeAll()
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private final class HookCounter {
        private let lock = NSLock()
        private var sessions = 0
        private var registrations = 0
        var sessionCount: Int { lock.withLock { sessions } }
        var registrationCount: Int { lock.withLock { registrations } }

        var hooks: NottiInAppHooks {
            NottiInAppHooks(
                onSessionStarted: { [unowned self] in self.lock.withLock { self.sessions += 1 } },
                onDeviceRegistered: { [unowned self] in self.lock.withLock { self.registrations += 1 } }
            )
        }
    }

    /// Holds the core's work queue inside the HTTP client's retry sleep until `release` (a retrying request).
    private final class QueueBlocker {
        private let lock = NSLock()
        private var armed = false
        private var blocked = false
        let entered = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)

        var isBlocked: Bool { lock.withLock { blocked } }
        func arm() { lock.withLock { armed = true } }

        func sleep() {
            let block: Bool = lock.withLock {
                guard armed else { return false }
                armed = false
                blocked = true
                return true
            }
            guard block else { return }
            entered.signal()
            released.wait()
            lock.withLock { blocked = false }
        }
    }

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        return session
    }

    private func makeCore(active: Bool, hooks: NottiInAppHooks, gate: NottiCore.SessionGate = NottiCore.SessionGate()) -> NottiCore {
        let session = stubSession()
        let core = NottiCore(
            deviceStore: NottiDeviceStore(defaults: defaults),
            eventStore: NottiEventStore(defaults: defaults),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            tokenProvider: { $0("fixture-token") },
            permissionRequester: { $0(true) },
            appStateProvider: { $0(active) },
            inAppHooks: hooks,
            sessionGate: gate
        )
        cores.append(core)
        return core
    }

    private func makeRuntime(
        active: @escaping () -> Bool = { false },
        observers: Bool = false,
        blocker: QueueBlocker? = nil
    ) -> NottiRuntime {
        let session = stubSession()
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("fixture-token") },
                permissionRequester: { $0(true) },
                appStateProvider: { $0(active()) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in blocker?.sleep() })
            },
            startObservers: observers,
            inAppEngine: engine,
            notificationCenter: center
        )
        runtimes.append(runtime)
        return runtime
    }

    private func drain(_ core: NottiCore?, file: StaticString = #filePath, line: UInt = #line) {
        guard let core = core else { return XCTFail("no core", file: file, line: line) }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core did not drain", file: file, line: line)
    }

    /// Drains the core, then runs the engine queue.
    private func settle(_ runtime: NottiRuntime, file: StaticString = #filePath, line: UInt = #line) {
        drain(runtime.core, file: file, line: line)
        scheduler.drain()
    }

    private func start(_ runtime: NottiRuntime, app: String? = nil) {
        runtime.start(appId: app ?? appId, clientKey: clientKey, baseUrl: baseUrl)
    }

    private var eligibleCount: Int { network.routes.filter { $0 == "eligible" }.count }

    private func persistedAppIds() -> [String] {
        guard let data = defaults.data(forKey: "notti_pending_inapp_events"),
              let records = try? JSONDecoder().decode([NottiInAppEventRecord].self, from: data) else { return [] }
        return records.map(\.appId)
    }

    // MARK: - Core hooks (D4)

    func test_theCoreCallsOnSessionStartedOncePerRealSession() {
        let counter = HookCounter()
        let core = makeCore(active: true, hooks: counter.hooks)
        drain(core)
        XCTAssertEqual(counter.sessionCount, 1, "the cold-start session")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drain(core)
        XCTAssertEqual(counter.sessionCount, 1, "a repeat activation is not a session")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drain(core)
        XCTAssertEqual(counter.sessionCount, 2)
        XCTAssertEqual(counter.registrationCount, 0, "never registered")
    }

    func test_theCoreNeverCallsOnSessionStartedForAnAdoptedSession() {
        let gate = NottiCore.SessionGate()
        let first = HookCounter()
        let firstCore = makeCore(active: true, hooks: first.hooks, gate: gate)
        drain(firstCore)
        firstCore.invalidate()

        let second = HookCounter()
        let secondCore = makeCore(active: true, hooks: second.hooks, gate: gate)
        drain(secondCore)

        XCTAssertEqual(first.sessionCount, 1)
        XCTAssertEqual(second.sessionCount, 0, "the replacement core adopts the open session")
    }

    func test_theCoreCallsOnDeviceRegisteredAfterEachSuccess() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        let counter = HookCounter()
        let core = makeCore(active: false, hooks: counter.hooks)
        core.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(core)
        XCTAssertEqual(counter.registrationCount, 1)
        let deviceStore = NottiDeviceStore(defaults: defaults)
        XCTAssertEqual(deviceStore.getDeviceId(), "fixture-device", "stored before the hook ran")

        core.onTokenRefreshed("fixture-token-2")
        drain(core)
        XCTAssertEqual(counter.registrationCount, 2)
        XCTAssertEqual(counter.sessionCount, 0)
    }

    func test_theCoreDoesNotCallOnDeviceRegisteredAfterAFailure() {
        StubURLProtocol.enqueue(.status(400))
        let counter = HookCounter()
        let core = makeCore(active: false, hooks: counter.hooks)
        core.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(core)

        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)
        XCTAssertEqual(counter.registrationCount, 0)
    }

    // MARK: - Runtime

    func test_anIsolatedRuntimeDeliversBothHooksToItsEngine() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages())
        let runtime = makeRuntime(active: { true })
        start(runtime)
        settle(runtime)

        XCTAssertTrue(runtime.inAppEngine === engine)
        XCTAssertTrue(engine.sessionOpen)
        XCTAssertTrue(engine.registeredInProcess)
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertEqual(network.requests.first?.deviceId, "fixture-device", "identity read from NottiDeviceStore")
        XCTAssertEqual(network.requests.first?.token, "fixture-token")
        XCTAssertEqual(engine.fetchState, .done)
    }

    func test_replacingTheCoreKeepsTheEngineAndResetsItOnlyForAChangedConfig() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages())
        let runtime = makeRuntime(active: { true })
        start(runtime)
        settle(runtime)
        let firstCore = runtime.core

        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        start(runtime)
        settle(runtime)
        XCTAssertFalse(runtime.core === firstCore, "the core was replaced")
        XCTAssertTrue(runtime.inAppEngine === engine)
        XCTAssertEqual(engine.fetchState, .done, "same config: the session's fetch stands")
        XCTAssertEqual(eligibleCount, 1)

        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages())
        start(runtime, app: "fixture-app-2")
        settle(runtime)
        XCTAssertTrue(runtime.inAppEngine === engine)
        XCTAssertEqual(engine.config?.appId, "fixture-app-2")
        XCTAssertEqual(eligibleCount, 2, "a changed config resets the fetch; the new registration fetches again")
        XCTAssertEqual(network.requests.last?.appId, "fixture-app-2")
    }

    func test_didEnterBackgroundEndsTheEngineSessionWithNoLiveCore() {
        let runtime = makeRuntime(observers: true)
        engine.configure(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        engine.sessionStarted()
        scheduler.drain()
        XCTAssertTrue(engine.sessionOpen)
        XCTAssertNil(runtime.core)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        scheduler.drain()

        XCTAssertFalse(engine.sessionOpen)
        XCTAssertFalse(engine.appForeground)
    }

    func test_willEnterForegroundBeforeAnySessionOpensNothing() {
        _ = makeRuntime(observers: true)
        engine.configure(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        scheduler.drain()

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        scheduler.drain()

        XCTAssertFalse(engine.sessionOpen)
        XCTAssertTrue(network.requests.isEmpty)
    }

    func test_willEnterForegroundOpensTheNextSessionWhileTheCoreIsBlocked() {
        let blocker = QueueBlocker()
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages())
        let runtime = makeRuntime(active: { true }, observers: true, blocker: blocker)
        start(runtime)
        settle(runtime)
        XCTAssertEqual(eligibleCount, 1)

        // A token refresh whose registration retries: the core's work queue sleeps in the client.
        StubURLProtocol.enqueue(.status(500))
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        blocker.arm()
        runtime.core?.onTokenRefreshed("fixture-token-2")
        XCTAssertEqual(blocker.entered.wait(wallTimeout: .now() + 20), .success, "the core never blocked")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        scheduler.drain()
        XCTAssertFalse(engine.sessionOpen)

        network.enqueue(.messages())
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        scheduler.drain()
        XCTAssertTrue(engine.sessionOpen)
        XCTAssertEqual(eligibleCount, 2, "the session opened and fetched without the core")
        XCTAssertTrue(blocker.isBlocked, "the core was still blocked")

        // The core hears the activation late, after its retry: its session report is ignored.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        blocker.released.signal()
        settle(runtime)
        XCTAssertEqual(eligibleCount, 2)
        XCTAssertTrue(engine.sessionOpen)
    }

    func test_onNetworkAvailableFlushesAndResumesATransientGiveUp() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        let runtime = makeRuntime(active: { true })
        start(runtime)
        settle(runtime)
        scheduler.advance(30)
        XCTAssertEqual(eligibleCount, 5)
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: true))

        let store = NottiInAppEventStore(defaults: defaults)
        store.enqueue(appId: appId, messageId: "fixture-queued", type: "impression")
        network.enqueue(.status(201), .messages())
        runtime.onNetworkAvailable()
        scheduler.drain()

        XCTAssertTrue(network.routes.contains("events:fixture-queued"), "the engine flushed")
        XCTAssertEqual(eligibleCount, 6, "the fetch resumed once")
        XCTAssertEqual(engine.fetchState, .done)
    }

    func test_startThenTrackEventOnTheSameThreadKeepsTheNameForTheFirstSession() {
        var active = false
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        let runtime = makeRuntime(active: { active })
        start(runtime)
        engine.trackEvent("fixture_event")
        settle(runtime)

        XCTAssertFalse(engine.sessionOpen, "no session while the app is inactive")
        XCTAssertTrue(engine.awaitingFirstSession)
        XCTAssertEqual(engine.selector.earlyNames, ["fixture_event"])
        XCTAssertTrue(network.requests.isEmpty)

        active = true
        network.enqueue(.messages(InAppFixtureJSON.event("fixture-event-msg", "fixture_event")))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        settle(runtime)

        XCTAssertTrue(engine.sessionOpen, "opened through the core hook")
        XCTAssertEqual(presenter.presentedIds, ["fixture-event-msg"])
    }

    func test_reinitializeWithTheSameConfigLeavesTheEngineStateUntouched() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages(InAppFixtureJSON.sessionStart("fixture-msg")))
        let runtime = makeRuntime(active: { true })
        start(runtime)
        settle(runtime)
        let display = engine.display
        XCTAssertNotNil(display)

        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        start(runtime)
        settle(runtime)

        XCTAssertTrue(engine.display === display)
        XCTAssertTrue(presenter.tornDown.isEmpty)
        XCTAssertTrue(engine.registeredInProcess)
        XCTAssertEqual(engine.fetchState, .done)
        XCTAssertEqual(eligibleCount, 1)
        XCTAssertEqual(presenter.presentedIds, ["fixture-msg"])
    }

    func test_reinitializeWithADifferentConfigResetsAndPurgesOtherAppsRecords() {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        network.enqueue(.messages(InAppFixtureJSON.sessionStart("fixture-msg")))
        let runtime = makeRuntime(active: { true })
        start(runtime)
        settle(runtime)
        let display = engine.display
        network.holding = true
        let store = NottiInAppEventStore(defaults: defaults)
        store.enqueue(appId: appId, messageId: "fixture-old", type: "impression")
        store.enqueue(appId: "fixture-app-2", messageId: "fixture-new", type: "impression")
        XCTAssertEqual(persistedAppIds(), [appId, "fixture-app-2"])

        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        start(runtime, app: "fixture-app-2")
        settle(runtime)

        XCTAssertEqual(persistedAppIds(), ["fixture-app-2"], "the old app's records are purged from the suite")
        XCTAssertEqual(presenter.tornDown.map(\.id), display.map { [$0.id] } ?? [], "torn down silently")
        XCTAssertNil(engine.display)
        XCTAssertEqual(engine.config?.appId, "fixture-app-2")
    }

    func test_startSkipsTheEngineConfigForInvalidInput() {
        let runtime = makeRuntime()
        runtime.start(appId: "", clientKey: clientKey, baseUrl: baseUrl)
        runtime.start(appId: appId, clientKey: "", baseUrl: baseUrl)
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: "not a url")
        settle(runtime)
        XCTAssertNil(engine.config)

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl + "/")
        settle(runtime)
        XCTAssertEqual(engine.config?.baseUrl, NottiApiClient.validatedBaseUrl(baseUrl + "/"))
        XCTAssertEqual(engine.config?.appId, appId)
    }

    func test_theDeviceIdentityReaderNeedsBothStoredValues() {
        let read = NottiInAppEngine.deviceIdentity(defaults: defaults)
        let deviceStore = NottiDeviceStore(defaults: defaults)
        XCTAssertNil(read())

        deviceStore.setDeviceId("fixture-device")
        XCTAssertNil(read(), "no token yet")

        deviceStore.setLastToken("fixture-token")
        XCTAssertEqual(read(), NottiInAppIdentity(deviceId: "fixture-device", token: "fixture-token"))

        deviceStore.setLastToken("")
        XCTAssertNil(read())
    }
}
