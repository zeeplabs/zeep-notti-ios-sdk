import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-01, 03, 04, 06..08, 10, 11, 30, 31, 33, 51, 52. Port of the session, fetch and flush cases of RN
/// `NottiInAppCoordinatorTests` (0.8.0) over the real store, selector and flusher, a fake network that maps
/// literal HTTP statuses through the real client tables, a fake presenter and a fake scheduler (virtual
/// time, no sleeps). Statuses, `Retry-After` values, delays and log lines are literals. Synthetic values
/// only; the `sentinel` values must never reach a log line.
final class NottiInAppEngineFetchTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://api.example.invalid"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: NottiInAppEventStore!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var engine: NottiInAppEngine!
    private var identity: NottiInAppIdentity?
    private var logs: InAppLevelLogSink!
    private var mainCalls = 0
    private var savedLevel = NottiLogLevel.error

    override func setUp() {
        super.setUp()
        savedLevel = NottiLogger.level
        makeFixture()
    }

    override func tearDown() {
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        super.tearDown()
    }

    private func makeFixture() {
        if defaults != nil { defaults.removePersistentDomain(forName: suiteName) }
        suiteName = "NottiInAppEngineFetchTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        let clock = scheduler!
        store = NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) })
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
        identity = NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token")
        mainCalls = 0
        engine = makeEngine()
        let sink = InAppLevelLogSink()
        logs = sink
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in sink.append(level, message) }
    }

    private func makeEngine() -> NottiInAppEngine {
        let network = self.network!
        let clock = scheduler!
        return NottiInAppEngine(
            store: store,
            identity: { [unowned self] in self.identity },
            presenter: presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { [unowned self] work in
                self.mainCalls += 1
                work()
            },
            clientFactory: { network.transport(appId: $0.appId) }
        )
    }

    // MARK: - Helpers

    private func configure(_ app: String? = nil, key: String? = nil, url: String? = nil) {
        engine.configure(appId: app ?? appId, clientKey: key ?? clientKey, baseUrl: url ?? baseUrl)
        scheduler.drain()
    }

    private func sessionStarted() { engine.sessionStarted(); scheduler.drain() }
    private func registered() { engine.deviceRegistered(); scheduler.drain() }
    private func sessionEnded() { engine.sessionEnded(); scheduler.drain() }
    private func backgrounded() { engine.appBackgrounded(); scheduler.drain() }
    private func foregrounded() { engine.appForegrounded(); scheduler.drain() }
    private func networkAvailable() { engine.networkAvailable(); scheduler.drain() }
    private func track(_ name: String) { engine.trackEvent(name); scheduler.drain() }

    /// Leaves the app in the background with no session open, as `didEnterBackground` does.
    private func goToBackground() {
        sessionEnded()
        backgrounded()
    }

    private func startAndRegister() {
        configure()
        sessionStarted()
        registered()
    }

    @discardableResult
    private func queued(_ messageId: String = "fixture-old", app: String? = nil) -> NottiInAppEventRecord {
        store.enqueue(appId: app ?? appId, messageId: messageId, type: "impression")
    }

    private func enqueue(_ replies: InAppFakeNetwork.Reply...) {
        for reply in replies { network.enqueue(reply) }
    }

    private var requestCount: Int { network.requests.count }
    private var eligibleCount: Int { network.routes.filter { $0 == "eligible" }.count }

    private func assertNoSentinelInLogs(file: StaticString = #filePath, line: UInt = #line) {
        let sentinels = ["sentinel", "fixture-old", "fixture-app", "example.invalid", "buy", "checkout"]
        for message in logs.messages {
            for value in sentinels {
                XCTAssertFalse(message.contains(value), "\(message) leaks \(value)", file: file, line: line)
            }
        }
    }

    // MARK: - Once per session (IAM-01)

    func test_sessionThenRegistrationSendsOneEligible() {
        enqueue(.messages())
        configure()
        sessionStarted()
        XCTAssertEqual(requestCount, 0)
        registered()
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_registrationThenSessionSendsOneEligible() {
        enqueue(.messages())
        configure()
        registered()
        XCTAssertEqual(requestCount, 0)
        sessionStarted()
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_aSecondRegistrationARepeatedSessionStartASameConfigAndTrackEventAddNoEligible() {
        enqueue(.messages())
        startAndRegister()
        registered()
        sessionStarted()
        configure()
        track("fixture_event")
        scheduler.advance(600)
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_sessionEndedThenAppForegroundedSendsASecondEligible() {
        enqueue(.messages(), .messages())
        startAndRegister()
        goToBackground()
        foregrounded()
        XCTAssertTrue(engine.sessionOpen)
        XCTAssertEqual(network.routes, ["eligible", "eligible"])
    }

    func test_noEligibleWhileThisProcessHasNotRegistered() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1")))
        configure()
        sessionStarted()
        networkAvailable()
        foregrounded()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(engine.registeredInProcess)
        registered()
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertEqual(presenter.presentedIds, ["s1"])
    }

    func test_theRegistrationSurvivesSessionEndedSoTheNextSessionFetchesWithoutANewOne() {
        enqueue(.messages(), .messages())
        startAndRegister()
        goToBackground()
        XCTAssertTrue(engine.registeredInProcess)
        foregrounded()
        XCTAssertEqual(network.routes, ["eligible", "eligible"])
    }

    func test_aNilIdentityDefersTheFetchToTheNextTrigger() {
        identity = nil
        startAndRegister()
        XCTAssertEqual(requestCount, 0)
        identity = NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token")
        enqueue(.messages())
        registered()
        XCTAssertEqual(network.routes, ["eligible"])
    }

    // MARK: - Sessions (IAM-51, D14)

    func test_sessionStartedWhileASessionIsOpenIsIgnored() {
        enqueue(.messages(InAppFixtureJSON.event("e1", "buy")))
        startAndRegister()
        let generation = engine.fetchGeneration
        sessionStarted()
        XCTAssertEqual(engine.fetchGeneration, generation)
        XCTAssertEqual(engine.fetchState, .done)
        track("buy")
        XCTAssertEqual(presenter.presentedIds, ["e1"])
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_aFirstSessionReportedInBackgroundOpensOnTheNextForeground() {
        enqueue(.messages())
        configure()
        registered()
        backgrounded()
        sessionStarted()
        XCTAssertFalse(engine.sessionOpen)
        XCTAssertTrue(engine.sessionReportDeferred)
        XCTAssertEqual(requestCount, 0)
        foregrounded()
        XCTAssertTrue(engine.sessionOpen)
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_aLateCoreReportAfterTheAppLeftOpensNothingUntilTheNextForeground() {
        enqueue(.messages(), .messages())
        startAndRegister()
        goToBackground()
        sessionStarted()
        XCTAssertFalse(engine.sessionOpen)
        XCTAssertEqual(network.routes, ["eligible"])
        foregrounded()
        sessionStarted()
        XCTAssertEqual(network.routes, ["eligible", "eligible"])
    }

    func test_appForegroundedBeforeAnySessionOpensNothing() {
        configure()
        registered()
        foregrounded()
        XCTAssertFalse(engine.sessionOpen)
        XCTAssertFalse(engine.hasOpenedSession)
        XCTAssertEqual(requestCount, 0)
    }

    // MARK: - Selection (IAM-07, IAM-08)

    func test_theFirstSessionStartMessageIsHandedToThePresenterOnTheMainDispatcher() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1"), InAppFixtureJSON.sessionStart("s2")))
        startAndRegister()
        XCTAssertEqual(presenter.presentedIds, ["s1"])
        XCTAssertEqual(mainCalls, 1)
        XCTAssertNotEqual(presenter.presented.first?.id, "s1")
        XCTAssertEqual(presenter.presented.first?.state, .preparing)
    }

    func test_anEventMessageIsHeldAndHandedOnlyOnAMatchingTrackEventWithNothingSent() {
        enqueue(.messages(InAppFixtureJSON.event("e1", "buy"), InAppFixtureJSON.event("e2", "buy")))
        startAndRegister()
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertEqual(engine.selector.held.map(\.id), ["e1", "e2"])
        track("other")
        track("Buy")
        XCTAssertTrue(presenter.presented.isEmpty)
        track("buy")
        XCTAssertEqual(presenter.presentedIds, ["e1"])
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertTrue(store.all().isEmpty)
        assertNoSentinelInLogs()
    }

    // MARK: - Pre-fetch flush (IAM-03)

    func test_aQueuedEventIsFlushedBeforeEligible() {
        let event = queued()
        enqueue(.status(201), .messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        XCTAssertEqual(network.routes, ["events:fixture-old", "eligible"])
        XCTAssertEqual(network.requests.first?.eventId, event.eventId)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(presenter.presentedIds, ["s1"])
    }

    func test_aFailingPreFetchFlushDoesNotPreventEligible() {
        let failures: [InAppFakeNetwork.Reply] = [.status(503), .status(429, retryAfter: "30"), .status(403), .transport]
        for failure in failures {
            makeFixture()
            configure()
            registered()
            queued()
            queued("fixture-second")
            enqueue(failure, .messages())
            sessionStarted()
            XCTAssertEqual(network.routes, ["events:fixture-old", "eligible"], "status \(failure.status)")
            XCTAssertEqual(store.all().count, 2, "status \(failure.status)")
        }
    }

    func test_aRegistrationFlushAndThePreFetchPassNeverSendTheSameHeadTwice() {
        queued()
        enqueue(.messages())
        configure()
        sessionStarted()
        network.holding = true
        registered()
        XCTAssertEqual(network.routes, ["events:fixture-old"])
        network.holding = false
        network.release(.status(201))
        scheduler.drain()
        XCTAssertEqual(network.routes, ["events:fixture-old", "eligible"])
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_thePreFetchFlushIsSkippedWhileAnEvents429PauseIsActive() {
        queued()
        enqueue(.status(429, retryAfter: "30"), .messages())
        configure()
        registered()
        XCTAssertNotNil(engine.eventsPauseUntil)
        sessionStarted()
        XCTAssertEqual(network.routes, ["events:fixture-old", "eligible"])
        XCTAssertEqual(store.all().count, 1)
    }

    func test_aPreFetchPassDuringARunningFullFlushLeavesThatFlushsFlag() {
        queued()
        enqueue(.status(503), .status(201), .messages())
        configure()
        registered()
        XCTAssertTrue(engine.flushRunning)
        XCTAssertEqual(scheduler.delays, [2])
        sessionStarted()
        XCTAssertEqual(network.routes, ["events:fixture-old", "events:fixture-old", "eligible"])
        XCTAssertTrue(engine.flushRunning)
        XCTAssertTrue(store.all().isEmpty)
        networkAvailable()
        XCTAssertTrue(engine.flushAgain)
        XCTAssertEqual(requestCount, 3)
        scheduler.advance(60)
        XCTAssertFalse(engine.flushRunning)
        XCTAssertEqual(requestCount, 3)
    }

    func test_401InThePreFetchFlushSkipsEligibleAndEveryFlushUntilTheNextSession() {
        configure()
        registered()
        queued()
        enqueue(.status(401))
        sessionStarted()
        XCTAssertEqual(network.routes, ["events:fixture-old"])
        XCTAssertTrue(engine.keyRejected)
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: false))
        networkAvailable()
        foregrounded()
        registered()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(logs.messages, ["Notti.inapp: events failed (HTTP 401)"])
        XCTAssertFalse(logs.messages.contains { $0.contains("registration") })
        assertNoSentinelInLogs()

        enqueue(.status(201), .messages())
        goToBackground()
        foregrounded()
        XCTAssertEqual(network.routes, ["events:fixture-old", "events:fixture-old", "eligible"])
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - eligible 4xx (IAM-04)

    func test_eligible403LogsOneFixedWarnAndStopsForTheSession() {
        enqueue(.status(403, body: #"{"sentinel":"body"}"#))
        startAndRegister()
        networkAvailable()
        scheduler.advance(600)
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: false))
        XCTAssertEqual(logs.warnings, ["Notti: in-app messages are inactive on this device until the next registration (HTTP 403)"])
        XCTAssertEqual(logs.messages.count, 1)
        assertNoSentinelInLogs()
    }

    func test_eligible401StopsWithNoRetryAndNoRegistrationText() {
        enqueue(.status(401))
        startAndRegister()
        queued()
        networkAvailable()
        foregrounded()
        scheduler.advance(600)
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertTrue(engine.keyRejected)
        XCTAssertEqual(logs.messages, ["Notti.inapp: eligible failed (HTTP 401)"])
        XCTAssertFalse(logs.messages.contains { $0.contains("registration") })
        XCTAssertEqual(store.all().count, 1)
    }

    func test_eligible422StopsWithNoRetry() {
        enqueue(.status(422))
        startAndRegister()
        networkAvailable()
        scheduler.advance(600)
        XCTAssertEqual(network.routes, ["eligible"])
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: false))
        XCTAssertEqual(logs.messages, ["Notti.inapp: eligible failed (HTTP 422)"])
    }

    /// PRF-07: a registration tagged with a config the engine left behind is ignored; the current one counts.
    func test_aRegistrationForAPreviousConfigIsIgnored() {
        configure()
        let previous = NottiInAppConfig(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        configure("fixture-app-2")
        sessionStarted()

        engine.deviceRegistered(for: previous)
        scheduler.drain()
        XCTAssertFalse(engine.registeredInProcess)
        XCTAssertTrue(network.routes.isEmpty, "no eligible for the new app with the old registration")

        network.enqueue(.messages())
        engine.deviceRegistered(for: NottiInAppConfig(appId: "fixture-app-2", clientKey: clientKey, baseUrl: baseUrl))
        scheduler.drain()
        XCTAssertTrue(engine.registeredInProcess)
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_the403WarningIsLoggedOncePerSessionPerRoute() {
        configure()
        registered()
        queued()
        enqueue(.status(403), .status(403), .status(403))
        sessionStarted()
        foregrounded()
        XCTAssertEqual(network.routes, ["events:fixture-old", "eligible", "events:fixture-old"])
        let warning = "Notti: in-app messages are inactive on this device until the next registration (HTTP 403)"
        XCTAssertEqual(logs.warnings, [warning, warning])
    }

    // MARK: - eligible 429 (IAM-04)

    func test_eligible429WithRetryAfter120GivesUpWithNoWait() {
        enqueue(.status(429, retryAfter: "120"))
        startAndRegister()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(scheduler.delays, [])
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: false))
    }

    func test_eligible429WithRetryAfter2RetriesAt2Seconds() {
        enqueue(.status(429, retryAfter: "2"), .messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        scheduler.advance(1.999)
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(0.001)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(scheduler.delays, [2])
        XCTAssertEqual(presenter.presentedIds, ["s1"])
    }

    func test_eligible429WithRetryAfter0Waits1Second() {
        enqueue(.status(429, retryAfter: "0"), .messages())
        startAndRegister()
        scheduler.advance(0.999)
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(0.001)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(scheduler.delays, [1])
    }

    func test_eligible429WithoutAValidRetryAfterWaits60Seconds() {
        for header in [nil, "soon", "-5"] as [String?] {
            makeFixture()
            enqueue(.status(429, retryAfter: header), .messages())
            startAndRegister()
            scheduler.advance(59.999)
            XCTAssertEqual(requestCount, 1, "Retry-After \(String(describing: header))")
            scheduler.advance(0.001)
            XCTAssertEqual(requestCount, 2, "Retry-After \(String(describing: header))")
            XCTAssertEqual(scheduler.delays, [60], "Retry-After \(String(describing: header))")
        }
    }

    func test_eligible429WithRetryAfter61GivesUpAnd60Waits60Seconds() {
        enqueue(.status(429, retryAfter: "61"))
        startAndRegister()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(scheduler.delays, [])

        makeFixture()
        enqueue(.status(429, retryAfter: "60"), .messages())
        startAndRegister()
        scheduler.advance(59.999)
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(0.001)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(scheduler.delays, [60])
    }

    func test_eligible429GivesUpAfter3Waits() {
        for _ in 0..<4 { enqueue(.status(429, retryAfter: "1")) }
        enqueue(.messages())
        startAndRegister()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 4)
        XCTAssertEqual(scheduler.delays, [1, 1, 1])
        XCTAssertEqual(engine.fetchState, .gaveUp(transient: false))
        networkAvailable()
        XCTAssertEqual(requestCount, 4)
    }

    func test_anEligible429PauseOutlivesItsSession() {
        enqueue(.status(429, retryAfter: "30"), .messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(10)
        goToBackground()
        scheduler.advance(5)
        foregrounded()
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(14.999)
        XCTAssertEqual(requestCount, 1)
        scheduler.advance(0.001)
        XCTAssertEqual(requestCount, 2)
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(presenter.presentedIds, ["s1"])
    }

    func test_aConfigChangeClearsTheEligiblePause() {
        enqueue(.status(429, retryAfter: "30"), .messages())
        startAndRegister()
        XCTAssertNotNil(engine.eligiblePauseUntil)
        configure("fixture-app-2")
        XCTAssertNil(engine.eligiblePauseUntil)
        registered()
        XCTAssertEqual(network.requests.map(\.appId), ["fixture-app", "fixture-app-2"])
    }

    // MARK: - eligible transient (IAM-04, IAM-52)

    func test_transientEligibleFailuresBackOff2_4_8_16ThenGiveUp() {
        let failures: [InAppFakeNetwork.Reply] = [.status(503), .status(408), .transport, .status(200, body: "[]")]
        for failure in failures {
            makeFixture()
            for _ in 0..<5 { enqueue(failure) }
            startAndRegister()
            scheduler.advance(600)
            XCTAssertEqual(requestCount, 5, "status \(failure.status)")
            XCTAssertEqual(scheduler.delays, [2, 4, 8, 16], "status \(failure.status)")
            XCTAssertEqual(engine.fetchState, .gaveUp(transient: true), "status \(failure.status)")
        }
    }

    func test_networkAvailableResumesATransientGiveUpOnce() {
        for _ in 0..<5 { enqueue(.status(503)) }
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        scheduler.advance(60)
        XCTAssertEqual(requestCount, 5)
        networkAvailable()
        XCTAssertEqual(requestCount, 6)
        XCTAssertEqual(presenter.presentedIds, ["s1"])
        networkAvailable()
        scheduler.advance(600)
        XCTAssertEqual(requestCount, 6)
    }

    func test_networkAvailableDoesNotResumeA403_422Or401GiveUp() {
        for status in [403, 422, 401] {
            makeFixture()
            enqueue(.status(status), .messages())
            startAndRegister()
            networkAvailable()
            networkAvailable()
            XCTAssertEqual(network.routes, ["eligible"], "status \(status)")
        }
    }

    // MARK: - Events outcomes (IAM-31, IAM-33)

    func test_anEvents429PausesEveryTriggerUntilTheClampedDeadlineThenFlushesOnce() {
        let cases: [(String?, TimeInterval)] = [("0", 1), ("9999", 300), (nil, 60)]
        for (header, seconds) in cases {
            makeFixture()
            configure()
            queued()
            enqueue(.status(429, retryAfter: header), .status(201), .status(201))
            registered()
            XCTAssertEqual(requestCount, 1)
            queued("fixture-new")
            networkAvailable()
            foregrounded()
            registered()
            XCTAssertEqual(requestCount, 1, "Retry-After \(String(describing: header))")
            scheduler.advance(seconds - 0.001)
            XCTAssertEqual(requestCount, 1, "Retry-After \(String(describing: header))")
            scheduler.advance(0.001)
            XCTAssertEqual(
                network.routes, ["events:fixture-old", "events:fixture-old", "events:fixture-new"],
                "Retry-After \(String(describing: header))"
            )
            XCTAssertTrue(store.all().isEmpty)
            XCTAssertEqual(scheduler.delays, [seconds], "Retry-After \(String(describing: header))")
        }
    }

    func test_tenTriggersDuringOneRunProduceAtMostOneExtraPass() {
        queued()
        configure()
        network.holding = true
        registered()
        XCTAssertEqual(requestCount, 1)
        for _ in 0..<10 { engine.networkAvailable() }
        scheduler.drain()
        XCTAssertEqual(requestCount, 1)
        network.holding = false
        enqueue(.status(403))
        network.release(.status(403))
        scheduler.drain()
        scheduler.advance(600)
        XCTAssertEqual(network.routes, ["events:fixture-old", "events:fixture-old"])
        XCTAssertFalse(engine.flushRunning)
        XCTAssertFalse(engine.flushAgain)
    }

    func test_aFullModeTransientHeadIsRetriedAfter2_4_8_16WithTheSameEventId() {
        let event = queued()
        for _ in 0..<5 { enqueue(.status(503)) }
        configure()
        registered()
        scheduler.advance(600)
        XCTAssertEqual(network.requests.map(\.eventId), Array(repeating: event.eventId, count: 5))
        XCTAssertEqual(scheduler.delays, [2, 4, 8, 16])
        XCTAssertEqual(store.all(), [event])
        XCTAssertFalse(engine.flushRunning)
        XCTAssertEqual(logs.messages, ["Notti.inapp: events failed (network or server error)"])
    }

    func test_eventsAreFlushedOnlyForTheConfiguredApp() {
        queued("fixture-other", app: "fixture-app-9")
        queued("fixture-mine")
        enqueue(.status(201))
        configure()
        registered()
        XCTAssertEqual(network.routes, ["events:fixture-mine"])
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - Late responses (IAM-06)

    func test_aResponseArrivingAfterSessionEndedIsIgnored() {
        configure()
        registered()
        network.holding = true
        sessionStarted()
        goToBackground()
        network.release(.messages(InAppFixtureJSON.sessionStart("s1"), InAppFixtureJSON.event("e1", "buy")))
        scheduler.drain()
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(engine.selector.held.isEmpty)
        track("buy")
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func test_aResponseOfSession1ArrivingAfterSession2OpenedIsIgnored() {
        configure()
        registered()
        network.holding = true
        sessionStarted()
        goToBackground()
        foregrounded()
        XCTAssertEqual(network.heldCount, 2)
        network.release(.messages(InAppFixtureJSON.sessionStart("s1"), InAppFixtureJSON.event("e1", "buy")))
        scheduler.drain()
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(engine.selector.held.isEmpty)
        XCTAssertEqual(engine.fetchState, .inFlight)
        track("buy")
        XCTAssertTrue(presenter.presented.isEmpty)
        network.release(.messages(InAppFixtureJSON.event("e2", "buy")))
        scheduler.drain()
        track("buy")
        XCTAssertEqual(presenter.presentedIds, ["e2"])
    }

    func test_heldEventMessagesAreGoneAfterSessionEnded() {
        enqueue(.messages(InAppFixtureJSON.event("e1", "buy")), .messages())
        startAndRegister()
        XCTAssertEqual(engine.selector.held.count, 1)
        goToBackground()
        XCTAssertTrue(engine.selector.held.isEmpty)
        foregrounded()
        track("buy")
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func test_aPreparingDisplayIsTornDownSilentlyWhenTheSessionEnds() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        let display = presenter.presented.first
        goToBackground()
        XCTAssertNil(engine.display)
        XCTAssertTrue(presenter.tornDown.first === display)
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - No persisted shown state (IAM-10)

    func test_aNewEngineOverTheSameSuiteShowsTheSameMessageAgain() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1")), .messages(InAppFixtureJSON.sessionStart("s1")))
        startAndRegister()
        engine = makeEngine()
        startAndRegister()
        XCTAssertEqual(presenter.presentedIds, ["s1", "s1"])
        XCTAssertNil(defaults.dictionaryRepresentation().keys.first { $0 != "notti_pending_inapp_events" && $0.contains("notti") })
    }

    // MARK: - Config change (IAM-06, IAM-30, D13)

    func test_aConfigChangeResetsTheSessionStateIgnoresAnInFlightResponseAndPurgesOtherApps() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1"), InAppFixtureJSON.event("e1", "buy")), .status(429, retryAfter: "30"))
        startAndRegister()
        let display = presenter.presented.first
        queued("fixture-stale")
        registered()
        XCTAssertNotNil(engine.eventsPauseUntil)
        track("buy")
        XCTAssertEqual(engine.selector.held.count, 1)

        configure("fixture-app-2")
        XCTAssertTrue(engine.selector.held.isEmpty)
        XCTAssertTrue(engine.selector.earlyNames.isEmpty)
        XCTAssertEqual(engine.fetchState, .idle)
        XCTAssertFalse(engine.registeredInProcess)
        XCTAssertFalse(engine.keyRejected)
        XCTAssertNil(engine.eligiblePauseUntil)
        XCTAssertNil(engine.eventsPauseUntil)
        XCTAssertNil(engine.display)
        XCTAssertTrue(presenter.tornDown.first === display)
        XCTAssertTrue(presenter.closed.isEmpty)
        XCTAssertTrue(store.all().isEmpty)

        network.holding = true
        registered()
        configure("fixture-app-3")
        network.release(.messages(InAppFixtureJSON.sessionStart("s2")))
        scheduler.drain()
        XCTAssertEqual(presenter.presentedIds, ["s1"])
        XCTAssertEqual(network.requests.last?.appId, "fixture-app-2")
    }

    func test_aConfigChangeClearsTheKeyRejectedFlag() {
        enqueue(.status(401), .messages())
        startAndRegister()
        XCTAssertTrue(engine.keyRejected)
        configure(key: "sentinel-key-2")
        XCTAssertFalse(engine.keyRejected)
        registered()
        XCTAssertEqual(network.routes, ["eligible", "eligible"])
    }

    func test_eachOfAppIdClientKeyAndBaseUrlCountsAsAConfigChange() {
        for change in ["app", "key", "url"] {
            makeFixture()
            enqueue(.messages())
            startAndRegister()
            switch change {
            case "app": configure("fixture-app-2")
            case "key": configure(key: "sentinel-key-2")
            default: configure(url: "https://api2.example.invalid")
            }
            XCTAssertFalse(engine.registeredInProcess, change)
            XCTAssertEqual(engine.fetchState, .idle, change)
        }
    }

    func test_aSameConfigConfigureChangesNothing() {
        enqueue(.messages(InAppFixtureJSON.sessionStart("s1"), InAppFixtureJSON.event("e1", "buy")), .status(429, retryAfter: "30"))
        queued("fixture-other", app: "fixture-app-9")
        startAndRegister()
        queued()
        registered()
        let display = engine.display
        let pause = engine.eventsPauseUntil
        configure()
        XCTAssertTrue(engine.display === display)
        XCTAssertTrue(presenter.tornDown.isEmpty)
        XCTAssertEqual(engine.fetchState, .done)
        XCTAssertTrue(engine.registeredInProcess)
        XCTAssertEqual(engine.eventsPauseUntil, pause)
        XCTAssertEqual(engine.selector.held.count, 1)
        XCTAssertEqual(store.all().count, 1)
    }

    // MARK: - Cold-start window (IAM-11, D12)

    func test_configureThenTrackEventThenSessionAndRegistrationPresentsOnce() {
        enqueue(.messages(InAppFixtureJSON.event("e1", "fixture_event"), InAppFixtureJSON.event("e2", "fixture_event")))
        configure()
        XCTAssertTrue(engine.awaitingFirstSession)
        track("fixture_event")
        sessionStarted()
        XCTAssertFalse(engine.awaitingFirstSession)
        registered()
        XCTAssertEqual(presenter.presentedIds, ["e1"])
        XCTAssertEqual(network.routes, ["eligible"])
    }

    func test_namesBeforeConfigureAfterASessionEndedAndBlankAreIgnoredAndNeverLogged() {
        track("fixture_early")
        enqueue(.messages(InAppFixtureJSON.event("e1", "fixture_early")), .messages(InAppFixtureJSON.event("e2", "fixture_late")))
        configure()
        track(" ")
        track("")
        sessionStarted()
        registered()
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(engine.selector.earlyNames.isEmpty)
        goToBackground()
        track("fixture_late")
        foregrounded()
        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(logs.messages.isEmpty)
    }

    func test_33DistinctEarlyNamesKeepTheFirst32() {
        let names = (0..<33).map { "fixture_\($0)" }
        enqueue(.messages(InAppFixtureJSON.event("e32", "fixture_32")))
        configure()
        for name in names { engine.trackEvent(name) }
        scheduler.drain()
        XCTAssertEqual(engine.selector.earlyNames, Array(names.prefix(32)))
        sessionStarted()
        registered()
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func test_aNameTrackedWhileTheFetchIsInFlightMatchesWhenItArrives() {
        configure()
        registered()
        network.holding = true
        sessionStarted()
        track("fixture_event")
        network.release(.messages(InAppFixtureJSON.event("e1", "fixture_event")))
        scheduler.drain()
        XCTAssertEqual(presenter.presentedIds, ["e1"])
    }

    func test_aReinitializeAfterTheFirstSessionDoesNotRearmTheFlag() {
        enqueue(.messages(InAppFixtureJSON.event("e1", "fixture_event")), .messages(InAppFixtureJSON.event("e1", "fixture_event")))
        startAndRegister()
        goToBackground()
        configure()
        XCTAssertFalse(engine.awaitingFirstSession)
        track("fixture_event")
        configure("fixture-app-2")
        XCTAssertFalse(engine.awaitingFirstSession)
        track("fixture_event")
        XCTAssertTrue(engine.selector.earlyNames.isEmpty)
        foregrounded()
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func test_theConfigDescriptionPrintsNoValue() {
        let config = NottiInAppConfig(appId: "sentinel-app", clientKey: "sentinel-key", baseUrl: "https://sentinel.example.invalid")
        for text in [String(describing: config), String(reflecting: config), "\(config)"] {
            XCTAssertFalse(text.contains("sentinel"), text)
        }
    }
}

/// The production bindings: the `app.notti.sdk.inapp` queue, a real `configure` then `trackEvent` order
/// from one thread, the threads network and queue work run on, and the production client factory over
/// `StubURLProtocol`. Real queues; every wait is an expectation, never a sleep.
final class NottiInAppEngineQueueTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: NottiInAppEventStore!
    private var scheduler: NottiInAppQueueScheduler!
    private var presenter: InAppFakePresenter!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiInAppEngineQueueTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = NottiInAppEventStore(defaults: defaults)
        scheduler = NottiInAppQueueScheduler()
        presenter = InAppFakePresenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeEngine(_ factory: @escaping (NottiInAppConfig) -> NottiInAppTransport?) -> NottiInAppEngine {
        NottiInAppEngine(
            store: store,
            identity: { NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token") },
            presenter: presenter,
            scheduler: scheduler,
            clientFactory: factory
        )
    }

    /// Waits until both the engine queue and the main queue ran everything enqueued before this call.
    private func settle() {
        let done = expectation(description: "settled")
        scheduler.execute { DispatchQueue.main.async { done.fulfill() } }
        wait(for: [done], timeout: 10)
    }

    private func waitForPresent() {
        let shown = expectation(description: "presented")
        presenter.onPresent = { _ in shown.fulfill() }
        wait(for: [shown], timeout: 10)
    }

    func test_theProductionSchedulerRunsTasksInOrderOnTheInAppQueueAndDelaysWithoutBlocking() {
        let lock = NSLock()
        var labels: [String] = []
        var order: [Int] = []
        let ran = expectation(description: "ran")
        ran.expectedFulfillmentCount = 3
        let record: (Int) -> Void = { step in
            lock.withLock {
                labels.append(String(cString: __dispatch_queue_get_label(nil)))
                order.append(step)
            }
            ran.fulfill()
        }
        scheduler.schedule(after: 0.05) { record(3) }
        scheduler.execute { record(1) }
        scheduler.execute { record(2) }
        wait(for: [ran], timeout: 10)
        XCTAssertEqual(order, [1, 2, 3])
        XCTAssertEqual(labels, Array(repeating: "app.notti.sdk.inapp", count: 3))
    }

    func test_configureThenTrackEventOnTheSameThreadMatchesOnceInEitherOrder() {
        for registrationFirst in [false, true] {
            presenter = InAppFakePresenter()
            let network = InAppFakeNetwork()
            network.enqueue(.messages(InAppFixtureJSON.event("e1", "fixture_event")))
            let engine = makeEngine { network.transport(appId: $0.appId) }
            let shown = expectation(description: "presented")
            presenter.onPresent = { _ in shown.fulfill() }

            engine.configure(appId: "fixture-app", clientKey: "sentinel-key", baseUrl: "https://api.example.invalid")
            engine.trackEvent("fixture_event")
            if registrationFirst {
                engine.deviceRegistered()
                engine.sessionStarted()
            } else {
                engine.sessionStarted()
                engine.deviceRegistered()
            }
            wait(for: [shown], timeout: 10)
            settle()
            XCTAssertEqual(presenter.presentedIds, ["e1"], "registration first: \(registrationFirst)")
            XCTAssertEqual(network.routes, ["eligible"], "registration first: \(registrationFirst)")
        }
    }

    func test_networkAndStorageWorkNeverRunOnTheMainThread() {
        let network = InAppFakeNetwork()
        store.enqueue(appId: "fixture-app", messageId: "fixture-old", type: "impression")
        network.enqueue(.status(201), .messages(InAppFixtureJSON.sessionStart("s1")))
        let engine = makeEngine { network.transport(appId: $0.appId) }
        engine.configure(appId: "fixture-app", clientKey: "sentinel-key", baseUrl: "https://api.example.invalid")
        engine.sessionStarted()
        engine.deviceRegistered()
        waitForPresent()
        settle()
        XCTAssertEqual(network.routes, ["events:fixture-old", "eligible"])
        XCTAssertTrue(network.requests.allSatisfy { !$0.onMainThread })
        XCTAssertEqual(network.requests.map(\.queueLabel), ["app.notti.sdk.inapp", "app.notti.sdk.inapp"])
        XCTAssertEqual(presenter.callsOffMainThread, 0)
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_theProductionClientFactorySendsTheDocumentedRequests() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        store.enqueue(appId: "fixture-app", messageId: "fixture-old", type: "impression")
        StubURLProtocol.enqueue(.status(201))
        StubURLProtocol.enqueue(.status(200, body: #"{"messages":[\#(InAppFixtureJSON.sessionStart("s1"))]}"#))
        let engine = makeEngine(NottiInAppEngine.clientFactory(session: session))
        engine.configure(appId: "fixture-app", clientKey: "sentinel-key", baseUrl: "https://api.example.invalid")
        engine.sessionStarted()
        engine.deviceRegistered()
        waitForPresent()
        settle()
        let requests = StubURLProtocol.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://api.example.invalid/v1/apps/fixture-app/in-app-messages/fixture-old/events",
            "https://api.example.invalid/v1/apps/fixture-app/in-app-messages/eligible"
        ])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer sentinel-key", "Bearer sentinel-key"])
        let body = try XCTUnwrap(requests.last?.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(body, ["device_id": "sentinel-device", "token": "sentinel-token"])
        XCTAssertEqual(presenter.presentedIds, ["s1"])
    }

    func test_anUnusableBaseUrlBuildsNoClientAndSendsNothing() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        store.enqueue(appId: "fixture-app", messageId: "fixture-old", type: "impression")
        let engine = makeEngine(NottiInAppEngine.clientFactory(session: session))
        engine.configure(appId: "fixture-app", clientKey: "sentinel-key", baseUrl: "not a url")
        engine.sessionStarted()
        engine.deviceRegistered()
        engine.networkAvailable()
        settle()
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
        XCTAssertTrue(presenter.presented.isEmpty)
    }
}
