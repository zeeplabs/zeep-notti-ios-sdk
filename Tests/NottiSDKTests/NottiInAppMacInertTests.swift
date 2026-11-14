#if os(macOS)
import AppKit
import XCTest
@testable import NottiSDK

/// AD-025, design D8 (UNCONFIRMED): the In-App API compiles on macOS and does nothing. After `NottiRuntime.start`
/// the engine has no config, so it never fetches, flushes or writes `notti_pending_inapp_events`, and no In-App
/// request reaches the transport. Synthetic values only.
final class NottiInAppMacInertTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "fixture-key"
    private let baseUrl = "https://notti.example.invalid"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var engine: NottiInAppEngine!
    private var sessions: [URLSession] = []
    private var runtimes: [NottiRuntime] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiInAppMacInertTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        let clock = scheduler!
        let network = self.network!
        engine = NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) }),
            identity: NottiInAppEngine.deviceIdentity(defaults: defaults),
            presenter: NottiInAppPlaceholderPresenter(),
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
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        super.tearDown()
    }

    private func makeRuntime(notificationCenter: NotificationCenter = NotificationCenter(), observers: Bool = false) -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { $0("fixture-token") }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            startObservers: observers,
            inAppEngine: engine,
            notificationCenter: notificationCenter
        )
        runtimes.append(runtime)
        return runtime
    }

    private var pendingEventsData: Data? {
        defaults.data(forKey: NottiInAppEventStore.keyPendingEvents)
    }

    func test_startNeverConfiguresTheEngine() {
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime()

        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        runtime.core?.waitForPendingWork(timeout: 25)
        scheduler.drain()

        XCTAssertNil(engine.config, "supportsInApp is false: no In-App config on macOS")
        XCTAssertTrue(network.requests.isEmpty, "no eligible-messages or event request")
        XCTAssertNil(pendingEventsData, "nothing written to notti_pending_inapp_events")
    }

    func test_aSessionStartAndARegistrationReachNoInAppRequest() {
        StubURLProtocol.enqueue(.echoDevice())
        let runtime = makeRuntime()
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        runtime.core?.waitForPendingWork(timeout: 25)
        scheduler.drain()

        XCTAssertNil(engine.config)
        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertNil(pendingEventsData)
    }

    func test_trackEventIsAnInertNoOp() {
        let runtime = makeRuntime()
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)

        runtime.inAppEngine.trackEvent("fixture-event")
        runtime.inAppEngine.trackEvent("   ")
        scheduler.drain()

        XCTAssertNil(engine.config)
        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertNil(pendingEventsData)
    }

    func test_aClickListenerCompilesAndIsNeverCalled() {
        let runtime = makeRuntime()
        var calls = 0
        runtime.inAppClicks.handler = { _ in calls += 1 }
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        runtime.inAppEngine.trackEvent("fixture-event")
        scheduler.drain()

        XCTAssertEqual(calls, 0)
    }

    func test_theProcessObserversDoNotReachTheEngineOnForeground() {
        let center = NotificationCenter()
        let runtime = makeRuntime(notificationCenter: center, observers: true)
        runtime.start(appId: appId, clientKey: clientKey, baseUrl: baseUrl)

        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        scheduler.drain()
        XCTAssertFalse(engine.appForeground, "resign active pauses the (inert) engine like a background")

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        scheduler.drain()
        XCTAssertFalse(engine.appForeground, "no foreground observer is registered on macOS (D3)")
        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertNil(engine.config)
    }

    func test_thePlaceholderPresenterShowsNothing() {
        let presenter = NottiInAppPlaceholderPresenter()
        XCTAssertNil(presenter.events)
        presenter.events = engine
        XCTAssertNotNil(presenter.events)
        presenter.close(displayId: "none")
    }
}
#endif
