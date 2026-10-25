import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-06, 09, 12, 19, 25..30, 34, 35, 49. Display lifecycle of the engine: impression once, taps and
/// dismisses ignored until visible, click ordering, the `push_permission` path, the auto-dismiss clock on
/// virtual wall-clock time, session end and config change teardown. Port of the display cases of RN
/// `NottiInAppCoordinatorTests` / `NottiInAppSessionTests` (0.8.0). Fake presenter, scheduler, network and
/// clock; no sleeps. Event types, reasons, button ids and the warning are literals. Synthetic values only;
/// the `sentinel` values must never reach a log line.
final class NottiInAppEngineDisplayTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://api.example.invalid"
    private let messageId = "fixture-msg"

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: NottiInAppEventStore!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var engine: NottiInAppEngine!
    private var logs: InAppLevelLogSink!
    private var savedLevel = NottiLogLevel.error

    private var clicks: [NottiInAppClick] = []
    private var listenerRegistered = true
    private var order: [String] = []
    private var insideMain = false
    private var mainCalls = 0

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
        suiteName = "NottiInAppEngineDisplayTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        let clock = scheduler!
        store = NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) })
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
        clicks = []
        listenerRegistered = true
        order = []
        mainCalls = 0
        let network = self.network!
        engine = NottiInAppEngine(
            store: store,
            identity: { NottiInAppIdentity(deviceId: "sentinel-device", token: "sentinel-token") },
            presenter: presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { [unowned self] work in
                self.mainCalls += 1
                self.insideMain = true
                work()
                self.insideMain = false
            },
            clientFactory: { network.transport(appId: $0.appId) },
            emitClick: { [unowned self] click in
                let queued = self.store.all().contains { $0.type == "click" }
                self.order.append("emit(clickQueued: \(queued))")
                self.clicks.append(click)
                return self.listenerRegistered
            }
        )
        presenter.onClose = { [unowned self] _ in self.order.append("close") }
        let sink = InAppLevelLogSink()
        logs = sink
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in sink.append(level, message) }
    }

    // MARK: - Helpers

    private static let linkButton =
        #"{"id":"fixture-btn","label":"fixture","action":{"type":"url","value":"https://example.invalid/sentinel"}}"#
    private static let permissionButton = #"{"id":"fixture-perm","label":"fixture","action":{"type":"push_permission"}}"#
    private static let image =
        #","image_url":"https://example.invalid/i.png","image_action":{"type":"deeplink","value":"fixture://sentinel"}"#

    private func extra(buttons: [String] = [], dismiss: String? = nil, image: Bool = false) -> String {
        var text = buttons.isEmpty ? "" : #","buttons":[\#(buttons.joined(separator: ","))]"#
        if let dismiss = dismiss { text += #","dismiss_after_seconds":\#(dismiss)"# }
        if image { text += Self.image }
        return text
    }

    private func configure(_ app: String? = nil) {
        engine.configure(appId: app ?? appId, clientKey: clientKey, baseUrl: baseUrl)
        scheduler.drain()
    }

    private func run(_ input: () -> Void) {
        input()
        scheduler.drain()
    }

    /// Fetches `entries` in a new session. Later event sends are held, so every recorded event stays in the
    /// store for inspection.
    private func fetch(_ entries: [String]) {
        network.enqueue(.messages(entries.joined(separator: ",")))
        configure()
        run { engine.sessionStarted() }
        run { engine.deviceRegistered() }
        network.holding = true
    }

    /// `fetch`, then the presented display.
    @discardableResult
    private func show(_ entries: String..., file: StaticString = #filePath, line: UInt = #line) -> NottiInAppDisplay {
        fetch(entries)
        if let shown = presenter.presented.last { return shown }
        XCTFail("nothing presented", file: file, line: line)
        return NottiInAppDisplay(id: "none", message: NottiInAppMessageParser.parse(Data(
            #"{"messages":[\#(InAppFixtureJSON.sessionStart("fixture-none"))]}"#.utf8
        ))![0])
    }

    private func makeVisible(_ display: NottiInAppDisplay) {
        run { engine.displayAttached(displayId: display.id, attached: true) }
        run { engine.becameVisible(displayId: display.id) }
    }

    private func tap(_ display: NottiInAppDisplay, _ buttonId: String, _ action: NottiInAppButtonAction?) {
        run { engine.userTapped(displayId: display.id, buttonId: buttonId, action: action) }
    }

    private var records: [NottiInAppEventRecord] { store.all() }
    private var types: [String] { records.map(\.type) }

    private static let linkAction = NottiInAppButtonAction.link(
        NottiInAppLinkAction(type: .url, value: "https://example.invalid/sentinel")
    )

    private func assertNoSentinelInLogs(file: StaticString = #filePath, line: UInt = #line) {
        let sentinels = ["sentinel", "fixture", "example.invalid"]
        for message in logs.messages {
            for value in sentinels {
                XCTAssertFalse(message.contains(value), "\(message) leaks \(value)", file: file, line: line)
            }
        }
    }

    // MARK: - Impression (IAM-27)

    func test_becameVisibleThreeTimesRecordsOneImpression() {
        let display = show(InAppFixtureJSON.sessionStart(messageId))
        run { engine.displayAttached(displayId: display.id, attached: true) }
        for _ in 0..<3 { run { engine.becameVisible(displayId: display.id) } }

        XCTAssertEqual(types, ["impression"])
        XCTAssertEqual(records.first?.messageId, messageId)
        XCTAssertNil(records.first?.buttonId)
        XCTAssertNil(records.first?.reason)
        XCTAssertEqual(display.state, .visible)
    }

    func test_becameVisibleForAnotherDisplayIdIsIgnored() {
        show(InAppFixtureJSON.sessionStart(messageId))
        run { engine.becameVisible(displayId: "fixture-other") }

        XCTAssertTrue(records.isEmpty)
    }

    func test_tapOrDismissBeforeVisibleIsIgnoredAndQueuesNothing() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        tap(display, "fixture-btn", Self.linkAction)
        run { engine.userDismissed(displayId: display.id, reason: "close_button") }

        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(clicks.isEmpty)
        XCTAssertTrue(presenter.closed.isEmpty)
        XCTAssertEqual(display.state, .preparing)

        makeVisible(display)
        XCTAssertEqual(types, ["impression"], "the display still works once visible")
    }

    // MARK: - Click (IAM-25, IAM-26)

    func test_buttonTapRecordsClickEmitsTheLinkAndClosesWithoutDismiss() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        tap(display, "fixture-btn", Self.linkAction)

        XCTAssertEqual(types, ["impression", "click"])
        XCTAssertEqual(records.last?.buttonId, "fixture-btn")
        XCTAssertNil(records.last?.reason)
        XCTAssertEqual(clicks, [NottiInAppClick(
            messageId: messageId,
            buttonId: "fixture-btn",
            action: NottiInAppLinkAction(type: .url, value: "https://example.invalid/sentinel")
        )])
        XCTAssertEqual(order, ["emit(clickQueued: true)", "close"])
        XCTAssertEqual(presenter.closed, [display.id])
        XCTAssertNil(engine.display)
        XCTAssertTrue(logs.warnings.isEmpty)
    }

    func test_imageTapRecordsClickWithButtonIdImage() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(image: true)))
        makeVisible(display)
        let action = NottiInAppButtonAction.link(NottiInAppLinkAction(type: .deeplink, value: "fixture://sentinel"))
        tap(display, "image", action)

        XCTAssertEqual(types, ["impression", "click"])
        XCTAssertEqual(records.last?.buttonId, "image")
        XCTAssertEqual(clicks.first?.action, NottiInAppLinkAction(type: .deeplink, value: "fixture://sentinel"))
    }

    func test_aSecondTapInTheSameTurnIsIgnored() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        engine.userTapped(displayId: display.id, buttonId: "fixture-btn", action: Self.linkAction)
        engine.userTapped(displayId: display.id, buttonId: "fixture-btn", action: Self.linkAction)
        engine.userDismissed(displayId: display.id, reason: "close_button")
        scheduler.drain()

        XCTAssertEqual(types, ["impression", "click"], "at most one terminal event per display")
        XCTAssertEqual(clicks.count, 1)
        XCTAssertEqual(presenter.closed, [display.id])
    }

    func test_aTapWithAnUnknownActionEmitsANilAction() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        tap(display, "fixture-btn", nil)

        XCTAssertEqual(clicks, [NottiInAppClick(messageId: messageId, buttonId: "fixture-btn", action: nil)])
        XCTAssertEqual(types, ["impression", "click"])
    }

    func test_aLinkTapWithNoListenerLogsExactlyOneFixedWarning() {
        listenerRegistered = false
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        tap(display, "fixture-btn", Self.linkAction)

        XCTAssertEqual(logs.warnings, ["Notti.inapp: click reported but no click listener is registered"])
        XCTAssertEqual(types, ["impression", "click"], "the click is reported even with no listener")
        XCTAssertEqual(presenter.closed, [display.id])
        assertNoSentinelInLogs()
    }

    // MARK: - push_permission (IAM-49)

    func test_aPushPermissionTapWithNoListenerLogsNothing() {
        listenerRegistered = false
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.permissionButton])))
        makeVisible(display)
        tap(display, "fixture-perm", .pushPermission)

        XCTAssertTrue(logs.warnings.isEmpty)
        XCTAssertEqual(types, ["impression", "click"])
    }

    func test_aPushPermissionTapQueuesEmitsNilClosesThenRunsThePortOnMain() {
        var portCalls = 0
        var portOnMain = false
        run {
            engine.setPushPermissionPort { [unowned self] in
                portCalls += 1
                portOnMain = self.insideMain
                self.order.append("port")
            }
        }
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.permissionButton])))
        makeVisible(display)
        tap(display, "fixture-perm", .pushPermission)

        XCTAssertEqual(order, ["emit(clickQueued: true)", "close", "port"])
        XCTAssertEqual(portCalls, 1)
        XCTAssertTrue(portOnMain, "the port runs through the main dispatcher")
        XCTAssertEqual(clicks, [NottiInAppClick(messageId: messageId, buttonId: "fixture-perm", action: nil)])
        XCTAssertEqual(records.last?.type, "click")
        XCTAssertEqual(records.last?.buttonId, "fixture-perm")
        XCTAssertFalse(types.contains("dismiss"))
        XCTAssertTrue(logs.warnings.isEmpty)
    }

    func test_aPushPermissionTapWithNoPortOnlyRecordsEmitsAndCloses() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.permissionButton])))
        makeVisible(display)
        tap(display, "fixture-perm", .pushPermission)

        XCTAssertEqual(order, ["emit(clickQueued: true)", "close"])
        XCTAssertEqual(types, ["impression", "click"])
        XCTAssertEqual(clicks.first?.action, nil)
    }

    func test_thePortIsSetOnTheEngineQueue() {
        engine.setPushPermissionPort {}
        XCTAssertNil(engine.pushPermissionPort, "not set before the engine queue runs")

        scheduler.drain()
        XCTAssertNotNil(engine.pushPermissionPort)

        run { engine.setPushPermissionPort(nil) }
        XCTAssertNil(engine.pushPermissionPort)
    }

    func test_aLinkTapNeverRunsThePort() {
        var portCalls = 0
        run { engine.setPushPermissionPort { portCalls += 1 } }
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        tap(display, "fixture-btn", Self.linkAction)

        XCTAssertEqual(portCalls, 0)
    }

    // MARK: - Dismiss (IAM-28)

    func test_dismissReasonsAreRecordedAsGiven() {
        for reason in ["close_button", "swipe", "outside_tap"] {
            makeFixture()
            let display = show(InAppFixtureJSON.sessionStart(messageId))
            makeVisible(display)
            run { engine.userDismissed(displayId: display.id, reason: reason) }

            XCTAssertEqual(types, ["impression", "dismiss"], reason)
            XCTAssertEqual(records.last?.reason, reason)
            XCTAssertNil(records.last?.buttonId)
            XCTAssertEqual(presenter.closed, [display.id], reason)
            XCTAssertTrue(clicks.isEmpty)
        }
    }

    // MARK: - Auto dismiss (IAM-34, IAM-35)

    func test_dismissAfterEightSecondsFiresAtEightSecondsWithReasonAuto() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        makeVisible(display)

        scheduler.advance(7.999)
        XCTAssertEqual(types, ["impression"])

        scheduler.advance(0.001)
        XCTAssertEqual(types, ["impression", "dismiss"])
        XCTAssertEqual(records.last?.reason, "auto")
        XCTAssertEqual(presenter.closed, [display.id])
    }

    func test_aThreeSecondBackgroundPauseMovesTheTimerToElevenSeconds() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        makeVisible(display)
        scheduler.advance(2)
        run { engine.sessionEnded() }
        run { engine.appBackgrounded() }
        scheduler.advance(3)
        XCTAssertNotNil(engine.display, "a visible display survives the session end")
        run { engine.appForegrounded() }

        scheduler.advance(5.999)
        XCTAssertEqual(types, ["impression"], "nothing at 10.999 s")
        scheduler.advance(0.001)
        XCTAssertEqual(types, ["impression", "dismiss"])
        XCTAssertEqual(records.last?.reason, "auto")
        XCTAssertEqual(scheduler.elapsedMs, 11_000)
    }

    func test_detachingTheDisplayPausesTheTimer() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        makeVisible(display)
        scheduler.advance(1)
        run { engine.displayAttached(displayId: display.id, attached: false) }
        scheduler.advance(3)
        run { engine.displayAttached(displayId: display.id, attached: true) }

        scheduler.advance(6.999)
        XCTAssertEqual(types, ["impression"])
        scheduler.advance(0.001)
        XCTAssertEqual(records.last?.reason, "auto")
    }

    func test_theTimerDoesNotRunBeforeTheDisplayIsAttached() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        run { engine.becameVisible(displayId: display.id) }
        scheduler.advance(20)
        XCTAssertEqual(types, ["impression"])

        run { engine.displayAttached(displayId: display.id, attached: true) }
        scheduler.advance(8)
        XCTAssertEqual(records.last?.reason, "auto")
    }

    func test_aCloseAtTwoSecondsCancelsTheTimerAndRecordsCloseButton() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        makeVisible(display)
        scheduler.advance(2)
        run { engine.userDismissed(displayId: display.id, reason: "close_button") }
        scheduler.advance(20)

        XCTAssertEqual(types, ["impression", "dismiss"])
        XCTAssertEqual(records.last?.reason, "close_button")
        XCTAssertEqual(presenter.closed, [display.id])
    }

    func test_nullZeroAndThreeHundredOneGiveNoTimer() {
        for raw in ["null", "0", "301"] {
            makeFixture()
            let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: raw)))
            makeVisible(display)
            scheduler.advance(400)

            XCTAssertNil(display.clock, raw)
            XCTAssertEqual(types, ["impression"], raw)
        }
        for seconds in [nil, 0, 301, -1] {
            XCTAssertNil(NottiInAppDisplayClock.make(seconds: seconds) { 0 }, "\(String(describing: seconds))")
        }
        XCTAssertNotNil(NottiInAppDisplayClock.make(seconds: 1) { 0 })
        XCTAssertNotNil(NottiInAppDisplayClock.make(seconds: 300) { 0 })
    }

    func test_aWallClockMovingBackwardsCountsAsNoElapsedTime() {
        var nowMs: Int64 = 10_000
        guard let clock = NottiInAppDisplayClock.make(seconds: 8, nowMs: { nowMs }) else {
            return XCTFail("no clock")
        }
        clock.setAttached(true)
        clock.start()
        nowMs = 4_000
        XCTAssertEqual(clock.remainingMs(), 8_000)
        nowMs = 13_000
        XCTAssertEqual(clock.remainingMs(), 5_000)
        XCTAssertFalse(clock.isExpired)
        nowMs = 30_000
        XCTAssertEqual(clock.remainingMs(), 0, "never negative")
        XCTAssertTrue(clock.isExpired)
    }

    // MARK: - event_id (IAM-29)

    func test_everyEventHasALowercaseUuidGeneratedAtRecordTime() throws {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton])))
        makeVisible(display)
        scheduler.advance(2)
        tap(display, "fixture-btn", Self.linkAction)

        let pattern = try NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        for record in records {
            let range = NSRange(record.eventId.startIndex..., in: record.eventId)
            XCTAssertNotNil(pattern.firstMatch(in: record.eventId, range: range), record.eventId)
        }
        XCTAssertEqual(Set(records.map(\.eventId)).count, 2, "two events never share one id")
        XCTAssertEqual(records.map(\.occurredAtMs), [1_700_000_000_000, 1_700_000_002_000], "stamped when it occurred")
    }

    func test_theEventIdIsNotRegeneratedWhenTheSendIsRetried() {
        let display = show(InAppFixtureJSON.sessionStart(messageId))
        network.holding = false
        network.enqueue(.status(503), .status(201))
        makeVisible(display)
        let stored = records.first?.eventId
        scheduler.advance(2)

        let sent = network.requests.filter { $0.route == "events:\(messageId)" }.map(\.eventId)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent, [stored, stored])
        XCTAssertTrue(records.isEmpty, "sent with the 201")
    }

    // MARK: - One display (IAM-09, IAM-12)

    func test_atMostOneDisplayAndAnEventWhileVisibleIsIgnored() {
        let display = show(
            InAppFixtureJSON.sessionStart(messageId),
            InAppFixtureJSON.event("fixture-event-msg", "fixture_event")
        )
        makeVisible(display)
        run { engine.trackEvent("fixture_event") }

        XCTAssertEqual(presenter.presentedIds, [messageId])
        XCTAssertTrue(engine.display === display)
    }

    func test_aMessageIdIsPresentedOncePerSession() {
        fetch([InAppFixtureJSON.event("fixture-event-msg", "fixture_event")])
        XCTAssertTrue(presenter.presented.isEmpty)
        run { engine.trackEvent("fixture_event") }
        guard let shown = presenter.presented.last else { return XCTFail("not presented") }
        makeVisible(shown)
        run { engine.userDismissed(displayId: shown.id, reason: "close_button") }
        run { engine.trackEvent("fixture_event") }

        XCTAssertEqual(presenter.presentedIds, ["fixture-event-msg"])
    }

    // MARK: - Session end (OQ-9)

    func test_sessionEndedKeepsAVisibleDisplay() {
        let display = show(InAppFixtureJSON.sessionStart(messageId))
        makeVisible(display)
        run { engine.sessionEnded() }

        XCTAssertTrue(engine.display === display)
        XCTAssertTrue(presenter.tornDown.isEmpty)
        run { engine.userDismissed(displayId: display.id, reason: "close_button") }
        XCTAssertEqual(types, ["impression", "dismiss"], "still closable after the session end")
    }

    func test_sessionEndedDropsAPreparingDisplayWithNoEvent() {
        let display = show(InAppFixtureJSON.sessionStart(messageId))
        run { engine.sessionEnded() }

        XCTAssertNil(engine.display)
        XCTAssertEqual(presenter.tornDown.map(\.id), [display.id])
        run { engine.becameVisible(displayId: display.id) }
        XCTAssertTrue(records.isEmpty)
    }

    func test_displayFailedDropsAPreparingDisplayWithNoEvent() {
        let display = show(InAppFixtureJSON.sessionStart(messageId))
        run { engine.displayFailed(displayId: display.id) }
        run { engine.becameVisible(displayId: display.id) }

        XCTAssertNil(engine.display)
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Config change (IAM-06)

    func test_aConfigChangeWhileVisibleTearsDownSilentlyAndIgnoresTheOldDisplay() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(buttons: [Self.linkButton], dismiss: "8")))
        makeVisible(display)
        let before = records
        configure("fixture-app-2")

        XCTAssertNil(engine.display)
        XCTAssertEqual(presenter.tornDown.map(\.id), [display.id])
        scheduler.advance(20)
        run { engine.becameVisible(displayId: display.id) }
        tap(display, "fixture-btn", Self.linkAction)
        run { engine.userDismissed(displayId: display.id, reason: "close_button") }

        XCTAssertTrue(clicks.isEmpty)
        XCTAssertTrue(presenter.closed.isEmpty, "the timer never fired")
        XCTAssertEqual(before.map(\.type), ["impression"])
        XCTAssertTrue(records.isEmpty, "no event for the old display (its impression was purged with the old app)")
    }

    func test_aSameConfigConfigureLeavesTheDisplayUntouched() {
        let display = show(InAppFixtureJSON.sessionStart(messageId, extra: extra(dismiss: "8")))
        makeVisible(display)
        configure()

        XCTAssertTrue(engine.display === display)
        XCTAssertTrue(presenter.tornDown.isEmpty)
        scheduler.advance(8)
        XCTAssertEqual(records.last?.reason, "auto")
    }
}
