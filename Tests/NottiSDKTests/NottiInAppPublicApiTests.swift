import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-08, IAM-11, IAM-24, IAM-25, IAM-44: the public In-App shell. `Notti.trackEvent` and
/// `Notti.InAppMessages.addClickListener` go through `NottiFacade.shared`, routed by the internal test seam
/// to a facade on an isolated runtime whose engine runs on the fake scheduler, network and presenter. The
/// facade keeps its production main-thread dispatcher, so delivery on the main thread is real. Payload
/// values, action types and the warning are asserted as literals. Synthetic values only; no real network,
/// no `NottiRuntime.shared`.
final class NottiInAppPublicApiTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://notti.example.invalid"
    private let messageId = "fixture-msg"
    private let linkValue = "https://example.invalid/sentinel?a=1&b=%20x#frag"
    private let noListenerWarning = "Notti.inapp: click reported but no click listener is registered"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var relay: NottiInAppClickRelay!
    private var engine: NottiInAppEngine!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var sessions: [URLSession] = []
    private var logs: InAppLevelLogSink!
    private var savedLevel = NottiLogLevel.error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        savedLevel = NottiLogger.level
        suiteName = "NottiInAppPublicApiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
        relay = NottiInAppClickRelay()
        let clock = scheduler!
        let network = self.network!
        let relay = self.relay!
        engine = NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) }),
            identity: { NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token") },
            presenter: presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { $0() },
            clientFactory: { network.transport(appId: $0.appId) },
            emitClick: { relay.emit($0) }
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("fixture-token") },
                permissionRequester: { $0(true) },
                appStateProvider: { $0(false) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false,
            inAppEngine: engine,
            inAppClicks: relay
        )
        facade = NottiFacade(runtime: runtime)
        NottiFacade.setSharedForTesting(facade)
        let sink = InAppLevelLogSink()
        logs = sink
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in sink.append(level, message) }
    }

    override func tearDown() {
        NottiFacade.setSharedForTesting(nil)
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        facade = nil
        engine = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func drainCore(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    /// Runs every block already queued on the main queue (the hub's deliveries).
    private func drainMain() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func initialize() {
        Notti.initialize(appId: appId, clientKey: clientKey, options: Notti.Options(baseUrl: baseUrl))
        drainCore()
        scheduler.drain()
    }

    /// Opens an engine session that fetches `entries`; later event sends are held.
    private func openSession(_ entries: String...) {
        network.enqueue(.messages(entries.joined(separator: ",")))
        engine.sessionStarted()
        engine.deviceRegistered()
        scheduler.drain()
        network.holding = true
    }

    /// Initializes, shows a session-start message with `extra`, makes it visible and taps `buttonId`.
    private func showAndTap(extra: String, buttonId: String, action: NottiInAppButtonAction?,
                            file: StaticString = #filePath, line: UInt = #line) {
        initialize()
        openSession(InAppFixtureJSON.sessionStart(messageId, extra: extra))
        guard let display = presenter.presented.last else { return XCTFail("nothing presented", file: file, line: line) }
        engine.displayAttached(displayId: display.id, attached: true)
        engine.becameVisible(displayId: display.id)
        scheduler.drain()
        engine.userTapped(displayId: display.id, buttonId: buttonId, action: action)
        scheduler.drain()
        drainMain()
    }

    private var linkButton: String {
        #","buttons":[{"id":"fixture-btn","label":"fixture","action":{"type":"url","value":"\#(linkValue)"}}]"#
    }

    private var linkAction: NottiInAppButtonAction {
        .link(NottiInAppLinkAction(type: .url, value: linkValue))
    }

    private final class Received {
        private let lock = NSLock()
        private var items: [InAppReceivedClick] = []
        func append(_ click: NottiInAppClick, tag: String = "") {
            let item = InAppReceivedClick(click: click, onMain: Thread.isMainThread, tag: tag)
            lock.withLock { items.append(item) }
        }
        var clicks: [NottiInAppClick] { lock.withLock { items.map(\.click) } }
        var onMain: [Bool] { lock.withLock { items.map(\.onMain) } }
        var tags: [String] { lock.withLock { items.map(\.tag) } }
    }

    // MARK: - trackEvent (IAM-08, IAM-11)

    func test_trackEventReachesTheEngineThroughTheFacade() {
        initialize()
        openSession(InAppFixtureJSON.event(messageId, "fixture_event"))
        XCTAssertTrue(presenter.presented.isEmpty, "an event message waits for its name")

        Notti.trackEvent("fixture_event")
        scheduler.drain()

        XCTAssertEqual(presenter.presentedIds, ["fixture-msg"])
        XCTAssertTrue(network.routes.allSatisfy { !$0.contains("fixture_event") }, "the name is never sent")
    }

    func test_aBlankNameIsASilentNoOp() {
        initialize()
        openSession(InAppFixtureJSON.event(messageId, "fixture_event"))
        drainCore()
        let before = logs.messages.count

        Notti.trackEvent("")
        Notti.trackEvent("   ")
        Notti.trackEvent(" \t\n")
        scheduler.drain()

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertEqual(logs.messages.count, before, "no log line at any level")
        Notti.trackEvent("fixture_event")
        scheduler.drain()
        XCTAssertEqual(presenter.presentedIds, ["fixture-msg"], "the session itself was live")
    }

    func test_trackEventBeforeInitializeIsANoOpAndNeverLogged() {
        Notti.trackEvent("fixture_early_name")
        scheduler.drain()

        initialize()
        openSession(InAppFixtureJSON.event(messageId, "fixture_early_name"))
        drainCore()

        XCTAssertTrue(presenter.presented.isEmpty, "a name sent before initialize is not remembered")
        XCTAssertFalse(logs.messages.contains { $0.contains("fixture_early_name") })
    }

    // MARK: - Click listener (IAM-24, IAM-25)

    func test_aListenerReceivesTheClickOnTheMainThreadWithTheUntouchedLink() {
        let received = Received()
        Notti.InAppMessages.addClickListener { received.append($0) }

        showAndTap(extra: linkButton, buttonId: "fixture-btn", action: linkAction)

        XCTAssertEqual(received.onMain, [true])
        let click = received.clicks.first
        XCTAssertEqual(click?.messageId, "fixture-msg")
        XCTAssertEqual(click?.buttonId, "fixture-btn")
        XCTAssertEqual(click?.action?.type, .url)
        XCTAssertEqual(click?.action?.type.rawValue, "url")
        XCTAssertEqual(click?.action?.value, "https://example.invalid/sentinel?a=1&b=%20x#frag")
        XCTAssertFalse(logs.warnings.contains(noListenerWarning))
    }

    func test_anImageClickCarriesTheDeeplinkAndButtonIdImage() {
        let received = Received()
        Notti.InAppMessages.addClickListener { received.append($0) }

        let image = #","image_url":"https://example.invalid/i.png","#
            + #""image_action":{"type":"deeplink","value":"fixture://sentinel/a"}"#
        showAndTap(
            extra: image,
            buttonId: "image",
            action: .link(NottiInAppLinkAction(type: .deeplink, value: "fixture://sentinel/a"))
        )

        XCTAssertEqual(received.clicks.first?.buttonId, "image")
        XCTAssertEqual(received.clicks.first?.action?.type.rawValue, "deeplink")
        XCTAssertEqual(received.clicks.first?.action?.value, "fixture://sentinel/a")
    }

    func test_aPushPermissionClickArrivesWithANilAction() {
        let received = Received()
        Notti.InAppMessages.addClickListener { received.append($0) }

        let button = #","buttons":[{"id":"fixture-perm","label":"fixture","action":{"type":"push_permission"}}]"#
        showAndTap(extra: button, buttonId: "fixture-perm", action: .pushPermission)

        XCTAssertEqual(received.clicks.count, 1)
        XCTAssertEqual(received.clicks.first?.buttonId, "fixture-perm")
        XCTAssertNil(received.clicks.first?.action)
        XCTAssertEqual(received.onMain, [true])
    }

    func test_twoListenersBothReceiveTheClickInRegistrationOrder() {
        let received = Received()
        Notti.InAppMessages.addClickListener { received.append($0, tag: "first") }
        Notti.InAppMessages.addClickListener { received.append($0, tag: "second") }

        showAndTap(extra: linkButton, buttonId: "fixture-btn", action: linkAction)

        XCTAssertEqual(received.tags, ["first", "second"])
        XCTAssertEqual(received.clicks.map(\.buttonId), ["fixture-btn", "fixture-btn"])
    }

    func test_removeStopsDeliveryAndTheEngineIsToldNobodyListens() {
        let received = Received()
        let kept = Received()
        let removed = Notti.InAppMessages.addClickListener { received.append($0) }
        let other = Notti.InAppMessages.addClickListener { kept.append($0) }
        removed.remove()
        other.remove()

        showAndTap(extra: linkButton, buttonId: "fixture-btn", action: linkAction)

        XCTAssertTrue(received.clicks.isEmpty)
        XCTAssertTrue(kept.clicks.isEmpty)
        XCTAssertEqual(logs.warnings.filter { $0 == noListenerWarning }.count, 1)
    }

    func test_withNoListenerTheClickIsStillReportedAndTheEngineLogsOneWarning() {
        showAndTap(extra: linkButton, buttonId: "fixture-btn", action: linkAction)

        XCTAssertEqual(logs.warnings.filter { $0 == noListenerWarning }.count, 1)
        XCTAssertEqual(presenter.closed.count, 1, "the display still closes")
        XCTAssertFalse(logs.messages.contains { $0.contains("sentinel") || $0.contains("example.invalid") })
    }

    func test_theRelayReportsWhetherAListenerIsRegistered() {
        let click = NottiInAppClick(messageId: "fixture-msg", buttonId: "fixture-btn", action: nil)
        XCTAssertFalse(relay.emit(click), "no listener yet")

        let subscription = Notti.InAppMessages.addClickListener { _ in }
        XCTAssertTrue(relay.emit(click))

        subscription.remove()
        XCTAssertFalse(relay.emit(click), "the last listener left")
        drainMain()
    }

    func test_theActionTypesAreTheContractLiterals() {
        XCTAssertEqual(NottiInAppAction.ActionType.url.rawValue, "url")
        XCTAssertEqual(NottiInAppAction.ActionType.deeplink.rawValue, "deeplink")
        XCTAssertEqual(
            NottiInAppAction(link: NottiInAppLinkAction(type: .url, value: "fixture://a")),
            NottiInAppAction(type: .url, value: "fixture://a")
        )
        XCTAssertEqual(
            NottiInAppAction(link: NottiInAppLinkAction(type: .deeplink, value: "fixture://b")),
            NottiInAppAction(type: .deeplink, value: "fixture://b")
        )
    }
}

/// One delivery seen by a test listener: the click, whether it ran on the main thread, and a listener tag.
private struct InAppReceivedClick {
    let click: NottiInAppClick
    let onMain: Bool
    let tag: String
}
