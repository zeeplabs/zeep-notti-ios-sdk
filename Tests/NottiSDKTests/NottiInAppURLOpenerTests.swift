import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// AD-020, in-app-open-url IOU-01, IOU-02, IOU-06, IOU-08: the URL validator table, the injected platform call,
/// the failure log and the source pin of the second allowlisted URL-opening file. No `UIApplication.shared`.
/// Synthetic values only.
final class NottiInAppURLOpenerTests: XCTestCase {

    private let failedLog = "Notti.inapp: url action could not be opened"

    // MARK: - Validator

    func test_httpAndHttpsWithAHostAreAcceptedAndReturnedUnchanged() {
        let accepted = [
            "https://example.invalid",
            "https://example.invalid/",
            "http://example.invalid/path",
            "HTTPS://EXAMPLE.INVALID/UPPER",
            "hTtPs://example.invalid/mixed",
            "https://example.invalid:8443/a/b?x=1&y=2#frag",
            "https://example.invalid/caf%C3%A9?q=a%20b",
            "https://xn--exmple-cua.invalid/idn",
            "https://fixture.example.invalid/a?redirect=https%3A%2F%2Fexample.invalid"
        ]
        for value in accepted {
            let url = NottiInAppURLOpener.openableURL(from: value)
            XCTAssertNotNil(url, value)
            XCTAssertEqual(url?.absoluteString, value, "\(value): not rewritten")
        }
    }

    func test_otherSchemesAreRefused() {
        let refused = [
            "tel:+000fixture", "sms:fixture", "mailto:fixture@example.invalid", "facetime:fixture",
            "fixture-app://sentinel", "itms-apps://example.invalid", "javascript:alert(1)", "JavaScript://example.invalid",
            "file:///etc/hosts", "data:text/html,fixture", "ftp://example.invalid/x", "about:blank"
        ]
        for value in refused {
            XCTAssertNil(NottiInAppURLOpener.openableURL(from: value), value)
        }
    }

    func test_missingHostEmptyRelativeAndMalformedValuesAreRefused() {
        let refused = [
            "", "https://", "https:///path", "https:example.invalid", "http:/example.invalid",
            "/relative/path", "relative/path", "example.invalid/path", "//example.invalid/x", "?q=1", "#frag",
            "https//example.invalid", "://example.invalid"
        ]
        for value in refused {
            XCTAssertNil(NottiInAppURLOpener.openableURL(from: value), "'\(value)'")
        }
    }

    func test_whitespaceAndControlCharactersAreRefusedBeforeParsing() {
        let refused = [
            " ", "   ", "\t", "\n", " https://example.invalid", "https://example.invalid ", "https://example.invalid/a b",
            "https://exa mple.invalid", "https://example.invalid/\n", "\thttps://example.invalid",
            "https://example.invalid/\u{0000}", "https://example.invalid/\u{007F}", "https://example.invalid/\u{00A0}"
        ]
        for value in refused {
            XCTAssertNil(NottiInAppURLOpener.openableURL(from: value), value.debugDescription)
        }
    }

    func test_theAllowedSchemesAreExactlyHttpAndHttps() {
        XCTAssertEqual(NottiInAppURLOpener.allowedSchemes, ["http", "https"])
    }

    // MARK: - Opening

    private final class Recorder {
        var opened: [URL] = []
        var logs: [String] = []
    }

    private func makeOpener(answer: Bool, recorder: Recorder) -> NottiInAppURLOpener {
        NottiInAppURLOpener(
            platform: NottiInAppURLOpener.Platform(open: { url, completion in
                recorder.opened.append(url)
                completion(answer)
            }),
            logger: { recorder.logs.append($0) }
        )
    }

    func test_openHandsTheURLToThePlatformOnceAndLogsNothingOnSuccess() throws {
        let recorder = Recorder()
        let url = try XCTUnwrap(NottiInAppURLOpener.openableURL(from: "https://example.invalid/sentinel"))
        makeOpener(answer: true, recorder: recorder).open(url)

        XCTAssertEqual(recorder.opened, [url])
        XCTAssertEqual(recorder.logs, [])
    }

    func test_aFailedOpenIsNotRetriedAndLogsOneFixedLineWithoutTheURL() throws {
        let recorder = Recorder()
        let url = try XCTUnwrap(NottiInAppURLOpener.openableURL(from: "https://sentinel.example.invalid/fixture"))
        makeOpener(answer: false, recorder: recorder).open(url)

        XCTAssertEqual(recorder.opened.count, 1, "no retry")
        XCTAssertEqual(recorder.logs, [failedLog])
        XCTAssertFalse(recorder.logs.joined().contains("sentinel"))
        XCTAssertFalse(recorder.logs.joined().contains("example.invalid"))
    }

    func test_theDefaultLoggerWritesTheFailureAtWarnWithoutTheURL() throws {
        let saved = NottiLogger.level
        let sink = InAppLevelLogSink()
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in sink.append(level, message) }
        defer {
            NottiLogger.sink = nil
            NottiLogger.level = saved
        }
        let url = try XCTUnwrap(NottiInAppURLOpener.openableURL(from: "https://sentinel.example.invalid/x"))
        NottiInAppURLOpener(platform: NottiInAppURLOpener.Platform(open: { $1(false) })).open(url)

        XCTAssertEqual(sink.warnings, [failedLog])
        XCTAssertFalse(sink.messages.contains { $0.contains("sentinel") })
    }

    func test_theFixedLogTextsCarryNoPlaceholder() {
        XCTAssertEqual(NottiInAppURLOpener.failedLog, failedLog)
        XCTAssertEqual(
            NottiInAppURLOpener.refusedLog,
            "Notti.inapp: url action not opened: only http and https links with a host are opened"
        )
    }

    // MARK: - The allowlisted file (AD-020)

    func test_theAllowlistedFileOpensOnlyTheValidatedURL() throws {
        let file = InAppViewFixtures.repoRoot
            .appendingPathComponent("Sources/NottiSDK/InApp/Platform/NottiInAppURLOpener.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        XCTAssertEqual(occurrences(of: "UIApplication.shared.open(", in: text), 1, "exactly one open call")
        XCTAssertEqual(
            lines.filter { $0.contains("UIApplication.shared.open(") },
            ["UIApplication.shared.open(url, options: [:], completionHandler: completion)"],
            "the call takes the `url` parameter of openInSystemBrowser"
        )
        XCTAssertEqual(occurrences(of: "platform.open(", in: text), 1, "one path to the platform")
        XCTAssertEqual(lines.filter { $0.hasPrefix("platform.open(") }, ["platform.open(url) { [logger] opened in"])
        XCTAssertEqual(occurrences(of: "URL(string", in: text), 0, "no URL is built from another string")
        XCTAssertEqual(occurrences(of: "return components.url", in: text), 1, "the validator is the only URL source")
        XCTAssertFalse(text.contains("\\("), "no string interpolation, so no URL in a log line")
        for banned in ["openURL", ".open(_:options", "payload", "userInfo", "absoluteString", "NottiInAppEngine"] {
            XCTAssertFalse(text.contains(banned), "the file must not reference \(banned)")
        }
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}

/// IOU-01, IOU-04: the runtime gives the engine an opener port only when built with a platform, and
/// `setOpensInAppURLs` reaches the engine.
final class NottiInAppURLOpenerWiringTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var engine: NottiInAppEngine!

    override func setUp() {
        super.setUp()
        suiteName = "NottiInAppURLOpenerWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        engine = NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults),
            identity: { nil },
            presenter: InAppFakePresenter(),
            scheduler: scheduler,
            mainDispatcher: { $0() },
            clientFactory: { _ in nil }
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        super.tearDown()
    }

    private func makeRuntime(platform: NottiInAppURLOpener.Platform?) -> NottiRuntime {
        NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            sdkVersion: "",
            startObservers: false,
            inAppEngine: engine,
            notificationCenter: NotificationCenter(),
            urlOpenPlatform: platform
        )
    }

    func test_aRuntimeWithAPlatformWiresAPortThatReachesIt() throws {
        var opened: [URL] = []
        let runtime = makeRuntime(platform: NottiInAppURLOpener.Platform(open: { url, completion in
            opened.append(url)
            completion(true)
        }))
        scheduler.drain()

        let port = try XCTUnwrap(engine.urlOpenPort)
        let url = try XCTUnwrap(URL(string: "https://example.invalid/fixture"))
        port(url)
        XCTAssertEqual(opened, [url])
        withExtendedLifetime(runtime) {}
    }

    func test_aRuntimeWithNoPlatformSetsNoPort() {
        let runtime = makeRuntime(platform: nil)
        scheduler.drain()

        XCTAssertNil(engine.urlOpenPort)
        withExtendedLifetime(runtime) {}
    }

    func test_setOpensInAppURLsReachesTheEngine() {
        let runtime = makeRuntime(platform: nil)
        runtime.setOpensInAppURLs(false)
        scheduler.drain()
        XCTAssertFalse(engine.opensURLs)

        runtime.setOpensInAppURLs(true)
        scheduler.drain()
        XCTAssertTrue(engine.opensURLs)
    }
}

/// IOU-01, IOU-04, IOU-05: `Notti.initialize` options through the facade to a real tap. The engine and the
/// facade keep the production main-queue dispatchers, so the order "listener, then open" is the real one.
final class NottiInAppOpenURLPublicApiTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://notti.example.invalid"
    private let messageId = "fixture-msg"
    private let linkValue = "https://example.invalid/sentinel?a=1"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var engine: NottiInAppEngine!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var sessions: [URLSession] = []
    private var logs: InAppLevelLogSink!
    private var savedLevel = NottiLogLevel.error
    private var events: [String] = []
    private var opened: [URL] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        savedLevel = NottiLogger.level
        suiteName = "NottiInAppOpenURLPublicApiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
        events = []
        opened = []
        let relay = NottiInAppClickRelay()
        let clock = scheduler!
        let network = self.network!
        engine = NottiInAppEngine(
            store: NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) }),
            identity: { NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token") },
            presenter: presenter,
            scheduler: scheduler,
            now: { clock.now },
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
            inAppClicks: relay,
            notificationCenter: NotificationCenter(),
            urlOpenPlatform: NottiInAppURLOpener.Platform(open: { [unowned self] url, completion in
                XCTAssertTrue(Thread.isMainThread)
                self.events.append("open")
                self.opened.append(url)
                completion(true)
            })
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

    private func drainMain() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func initialize(_ options: Notti.Options) {
        Notti.initialize(appId: appId, clientKey: clientKey, options: options)
        if let core = runtime.core { XCTAssertTrue(core.waitForPendingWork(timeout: 25)) }
        scheduler.drain()
    }

    private func showAndTapLink() {
        network.enqueue(.messages(InAppFixtureJSON.sessionStart(
            messageId,
            extra: #","buttons":[{"id":"fixture-btn","label":"fixture","action":{"type":"url","value":"\#(linkValue)"}}]"#
        )))
        engine.sessionStarted()
        engine.deviceRegistered()
        scheduler.drain()
        network.holding = true
        drainMain()
        guard let display = presenter.presented.last else { return XCTFail("nothing presented") }
        engine.displayAttached(displayId: display.id, attached: true)
        engine.becameVisible(displayId: display.id)
        scheduler.drain()
        engine.userTapped(displayId: display.id, buttonId: "fixture-btn",
                          action: .link(NottiInAppLinkAction(type: .url, value: linkValue)))
        scheduler.drain()
        drainMain()
    }

    func test_byDefaultTheListenerRunsFirstThenTheSDKOpensTheLink() {
        let subscription = Notti.InAppMessages.addClickListener { [unowned self] click in
            XCTAssertEqual(click.action?.value, self.linkValue, "untouched")
            self.events.append("listener")
        }
        defer { subscription.remove() }
        initialize(Notti.Options(baseUrl: baseUrl))
        showAndTapLink()

        XCTAssertEqual(events, ["listener", "open"])
        XCTAssertEqual(opened.map(\.absoluteString), [linkValue])
        XCTAssertFalse(logs.messages.contains { $0.contains("sentinel") || $0.contains("example.invalid") })
    }

    func test_optionsDefaultOpensInAppURLsToTrue() {
        XCTAssertTrue(Notti.Options().opensInAppURLs)
        XCTAssertTrue(Notti.Options(baseUrl: baseUrl).opensInAppURLs)
        XCTAssertFalse(Notti.Options(opensInAppURLs: false).opensInAppURLs)
    }

    func test_opensInAppURLsFalseOpensNothingAndTheListenerStillGetsTheLink() {
        var values: [String] = []
        let subscription = Notti.InAppMessages.addClickListener { values.append($0.action?.value ?? "") }
        defer { subscription.remove() }
        initialize(Notti.Options(baseUrl: baseUrl, opensInAppURLs: false))
        showAndTapLink()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(values, [linkValue])
        XCTAssertTrue(logs.debugs.isEmpty, "no refusal line when the option is off")
    }

    func test_reinitializingWithOnlyTheOptionChangedAppliesItWithoutARestart() {
        initialize(Notti.Options(baseUrl: baseUrl))
        let core = runtime.core
        XCTAssertNotNil(core)
        XCTAssertTrue(engine.opensURLs)

        initialize(Notti.Options(baseUrl: baseUrl, opensInAppURLs: false))
        XCTAssertTrue(runtime.core === core, "no restart")
        XCTAssertFalse(engine.opensURLs)

        initialize(Notti.Options(baseUrl: baseUrl))
        XCTAssertTrue(runtime.core === core)
        XCTAssertTrue(engine.opensURLs)
    }

    func test_anInvalidInitializeIgnoresTheOptionToo() {
        Notti.initialize(appId: "", clientKey: clientKey, options: Notti.Options(opensInAppURLs: false))
        scheduler.drain()
        XCTAssertTrue(engine.opensURLs)
    }
}
