import XCTest
import UIKit
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-23, IAM-24, IAM-43, IAM-45, IAM-46. The In-App privacy sweep: every path runs with sentinel values in the
/// token, device id, app id, client key, message id, button ids, title, body, button labels, image and action URLs
/// and event name, and no captured `NottiLogger` line (every level, `.verbose` on) may contain any of them. The
/// engine is real (fake scheduler, network and clock), the presenter is real (fake scenes and window hosts), and
/// the image loader is real over `RoutedStubURLProtocol`. The source guards of rule 3 run over the source tree. No sleeps,
/// no network, no `NottiRuntime.shared`.
final class NottiInAppPrivacyTests: XCTestCase {

    // MARK: Sentinels

    private let appId = "sentinel-app-3d10"
    private let clientKey = "sentinel-key-c9e2"
    private let deviceId = "sentinel-device-91c2"
    private let token = "sentinel-token-7f3a"
    private let messageId = "sentinel-msg-44d1"
    private let title = "sentinel-title-0b7e"
    private let body = "sentinel-body-55aa"
    private let linkButtonId = "sentinel-btn-a6"
    private let permissionButtonId = "sentinel-btn-b8"
    private let linkLabel = "sentinel-label-a6"
    private let permissionLabel = "sentinel-label-b8"
    private let imageUrl = "https://sentinel-image.example.invalid/x.png"
    private let actionUrl = "https://sentinel-action.example.invalid/y"
    private let deeplink = "sentinel-deep://z"
    private let eventName = "sentinel_event_e2"

    private var sentinels: [String] {
        [appId, clientKey, deviceId, token, messageId, title, body, linkButtonId, permissionButtonId, linkLabel,
         permissionLabel, imageUrl, actionUrl, deeplink, eventName, "sentinel"]
    }

    /// The registration text of the `403` warning (IAM-04).
    private let registrationText = "until the next registration"

    // MARK: Fixture

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var store: NottiInAppEventStore!
    private var harness: InAppPresenterHarness!
    private var engine: NottiInAppEngine!
    private var listenerRegistered = true
    private var logs: InAppLevelLogSink!
    private var savedLevel = NottiLogLevel.error
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        RoutedStubURLProtocol.reset()
        savedLevel = NottiLogger.level
        let sink = InAppLevelLogSink()
        logs = sink
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in sink.append(level, message) }
        suiteName = "NottiInAppPrivacyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        harness = InAppPresenterHarness()
        listenerRegistered = true
        let clock = scheduler!
        let network = self.network!
        let identity = NottiInAppIdentity(deviceId: deviceId, token: token)
        store = NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) })
        engine = NottiInAppEngine(
            store: store,
            identity: { identity },
            presenter: harness.presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { $0() },
            clientFactory: { network.transport(appId: $0.appId) },
            emitClick: { [unowned self] _ in self.listenerRegistered }
        )
        harness.presenter.events = engine
    }

    override func tearDown() {
        assertNoSentinel()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        harness = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func assertNoSentinel(file: StaticString = #filePath, line: UInt = #line) {
        for message in logs.messages {
            for sentinel in sentinels where message.contains(sentinel) {
                XCTFail("log line contains \(sentinel.prefix(12)): \(message)", file: file, line: line)
            }
        }
    }

    private func message(format: String = "center", dismissAfter: Int? = nil, trigger: String? = nil) -> String {
        let dismiss = dismissAfter.map { #","dismiss_after_seconds":\#($0)"# } ?? ""
        let triggerJSON = trigger.map { #"{"type":"event","name":"\#($0)"}"# } ?? #"{"type":"session_start"}"#
        return #"""
        {"id":"\#(messageId)","format":"\#(format)","title":"\#(title)","body":"\#(body)",\#
        "image_url":"\#(imageUrl)","image_action":{"type":"deeplink","value":"\#(deeplink)"},\#
        "buttons":[{"id":"\#(linkButtonId)","label":"\#(linkLabel)","action":{"type":"url","value":"\#(actionUrl)"}},\#
        {"id":"\#(permissionButtonId)","label":"\#(permissionLabel)","action":{"type":"push_permission"}}],\#
        "trigger":\#(triggerJSON)\#(dismiss)}
        """#
    }

    private func configure() {
        engine.configure(appId: appId, clientKey: clientKey, baseUrl: "https://api.example.invalid")
        scheduler.drain()
    }

    /// Configures, opens a session and answers `eligible` with `reply`.
    private func fetch(_ reply: InAppFakeNetwork.Reply) {
        network.enqueue(reply)
        configure()
        engine.sessionStarted()
        scheduler.drain()
        engine.deviceRegistered()
        scheduler.drain()
    }

    /// Fetches the sentinel message (with `extra` replies queued for the event sends), lays it out and makes it
    /// visible: the impression is recorded and flushed against the first queued events reply.
    @discardableResult
    private func showVisible(
        format: String = "center",
        dismissAfter: Int? = nil,
        events: [InAppFakeNetwork.Reply] = [.status(202)]
    ) -> InAppFakeHost? {
        fetch(.messages(message(format: format, dismissAfter: dismissAfter)))
        events.forEach { network.enqueue($0) }
        harness.host?.layout()
        scheduler.drain()
        XCTAssertNotNil(harness.host, "presented")
        return harness.host
    }

    private var lines: [String] { logs.messages }

    private func sources(under relative: String) throws -> [(path: String, text: String)] {
        let root = InAppViewFixtures.repoRoot
        let base = root.appendingPathComponent(relative)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            XCTFail("missing \(relative)")
            return []
        }
        var found: [(String, String)] = []
        for case let url as URL in walker where ["swift", "m", "h"].contains(url.pathExtension) {
            let path = String(url.path.dropFirst(root.path.count + 1))
            found.append((path, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertFalse(found.isEmpty, relative)
        return found
    }

    // MARK: Fetch paths

    func test_aFetchedMessageShownAndFlushedLogsNoSentinel() {
        let host = showVisible()
        XCTAssertNotNil(host)
        XCTAssertTrue(network.routes.contains("events:\(messageId)"))
        XCTAssertTrue(store.all().isEmpty, "the impression was sent")
    }

    func test_eligible401LogsNoSentinelAndNoRegistrationText() {
        fetch(.status(401))
        XCTAssertFalse(lines.contains { $0.contains(registrationText) })
        XCTAssertFalse(lines.isEmpty, "the generic 401 line is logged")
    }

    func test_eligible403LogsNoSentinel() {
        fetch(.status(403))
        XCTAssertTrue(lines.contains { $0.contains(registrationText) })
    }

    func test_eligible404LogsNoSentinel() {
        fetch(.status(404))
    }

    func test_eligible408RetriesLogNoSentinel() {
        fetch(.status(408))
        scheduler.advance(60)
        XCTAssertGreaterThan(network.routes.filter { $0 == "eligible" }.count, 1)
    }

    func test_eligible429LogsNoSentinel() {
        fetch(.status(429, retryAfter: "2"))
        network.enqueue(.status(429, retryAfter: "120"))
        scheduler.advance(5)
    }

    func test_eligibleServerAndTransportErrorsLogNoSentinel() {
        fetch(.status(500))
        network.enqueue(.transport, .transport, .transport, .transport)
        scheduler.advance(120)
    }

    // MARK: Event queue paths

    func test_events401LogsNoSentinelAndNoRegistrationText() {
        showVisible(events: [.status(401)])
        XCTAssertFalse(lines.contains { $0.contains(registrationText) })
        XCTAssertTrue(lines.contains("Notti.inapp: events failed (HTTP 401)"))
    }

    func test_events403LogsNoSentinel() {
        showVisible(events: [.status(403)])
        XCTAssertTrue(lines.contains { $0.contains(registrationText) })
    }

    func test_eventsRejectedAndDroppedLogNoSentinel() {
        showVisible(events: [.status(400)])
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_events408And500BackoffLogNoSentinel() {
        showVisible(events: [.status(408), .status(500), .transport])
        scheduler.advance(60)
    }

    func test_events429LogsNoSentinel() {
        showVisible(events: [.status(429, retryAfter: "3")])
        scheduler.advance(10)
    }

    func test_expiredEventsAreDroppedWithoutSentinel() {
        showVisible(events: [.transport, .transport, .transport, .transport, .transport])
        scheduler.advance(8 * 24 * 3600)
        engine.networkAvailable()
        scheduler.drain()
        XCTAssertTrue(lines.contains("Notti.inapp: expired events dropped"))
    }

    func test_aCorruptQueueSelfHealsWithoutSentinel() {
        defaults.set(Data("{\"\(messageId)\":".utf8), forKey: "notti_pending_inapp_events")
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: Taps and dismisses

    func test_aLinkButtonTapLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible())
        host.messageView?.buttons.first?.sendActions(for: .touchUpInside)
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_aTapWithNoListenerLogsTheFixedWarningOnly() throws {
        listenerRegistered = false
        let host = try XCTUnwrap(showVisible())
        host.messageView?.buttons.first?.sendActions(for: .touchUpInside)
        scheduler.drain()
        XCTAssertTrue(lines.contains("Notti.inapp: click reported but no click listener is registered"))
    }

    func test_anImageTapLogsNoSentinel() throws {
        harness.imageAnswer = .some(InAppViewFixtures.picture())
        let host = try XCTUnwrap(showVisible())
        try XCTUnwrap(host.messageView).handleImageTap()
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_aCloseButtonDismissLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible())
        host.messageView?.closeButton.sendActions(for: .touchUpInside)
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_anOutsideTapDismissLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible())
        try XCTUnwrap(host.content?.overlay as? NottiInAppCardLayout).handleBackdropTap()
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_aSwipeDismissLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible(format: "top"))
        XCTAssertEqual(host.controller?.accessibilityPerformEscape(), false)
        try XCTUnwrap(host.content?.overlay as? NottiInAppBarLayout).interaction.panEnded(-200)
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_anEscapeGestureDismissLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible(format: "full"))
        XCTAssertEqual(host.controller?.accessibilityPerformEscape(), true)
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
    }

    func test_anAutoDismissLogsNoSentinel() throws {
        let host = try XCTUnwrap(showVisible(dismissAfter: 5, events: [.status(202), .status(202)]))
        scheduler.advance(6)
        XCTAssertEqual(host.hideCount, 1)
    }

    // MARK: push_permission in every state

    func test_aPushPermissionTapWhenNotDeterminedLogsNoSentinel() throws {
        try tapPushPermission(.notDetermined)
    }

    func test_aPushPermissionTapWhenDeniedLogsNoSentinel() throws {
        try tapPushPermission(.denied)
    }

    func test_aPushPermissionTapWhenGrantedLogsNoSentinel() throws {
        try tapPushPermission(.granted)
    }

    func test_aPushPermissionTapInAnUnknownStateLogsOnlyTheFixedLine() throws {
        try tapPushPermission(.unknown)
        XCTAssertTrue(lines.contains("Notti.inapp: push permission state unavailable"))
    }

    private func tapPushPermission(_ state: NottiPushPermissionAction.State) throws {
        var effects: [String] = []
        let action = NottiPushPermissionAction(
            readState: { $0(state) },
            requestPermission: { effects.append("request") },
            openNotificationSettings: { effects.append("settings") }
        )
        engine.setPushPermissionPort { action.run() }
        listenerRegistered = false
        let host = try XCTUnwrap(showVisible())
        host.messageView?.buttons.last?.sendActions(for: .touchUpInside)
        scheduler.drain()
        XCTAssertEqual(host.hideCount, 1)
        let expected: [NottiPushPermissionAction.State: [String]] = [.notDetermined: ["request"], .denied: ["settings"]]
        XCTAssertEqual(effects, expected[state] ?? [])
        XCTAssertFalse(lines.contains { $0.contains("no click listener") }, "no warning for push_permission")
    }

    // MARK: Image

    func test_imageFailuresLogNoSentinel() throws {
        let loader = NottiInAppImageLoader(makeSession: { [unowned self] configuration, delegate, queue in
            configuration.protocolClasses = [RoutedStubURLProtocol.self]
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
            self.sessions.append(session)
            return session
        }, center: NotificationCenter())
        let url = try XCTUnwrap(URL(string: imageUrl))
        let behaviors: [RoutedStubURLProtocol.Behavior] = [
            .body(Data(body.utf8), status: 404),
            .body(Data(title.utf8)),
            .failure(URLError(.notConnectedToInternet))
        ]
        for behavior in behaviors {
            RoutedStubURLProtocol.reset()
            RoutedStubURLProtocol.register(behavior, for: url)
            let done = expectation(description: "image ended")
            loader.load(url: url, maxSidePx: 100) { image in
                XCTAssertNil(image)
                done.fulfill()
            }
            wait(for: [done], timeout: 15)
        }
        RoutedStubURLProtocol.reset()
        let insecure = expectation(description: "http refused")
        loader.load(url: try XCTUnwrap(URL(string: "http://sentinel-image.example.invalid/x.png")), maxSidePx: 100) {
            XCTAssertNil($0)
            insecure.fulfill()
        }
        wait(for: [insecure], timeout: 15)
    }

    func test_anImageThatNeverArrivesLogsNoSentinel() {
        harness.imageAnswer = nil
        fetch(.messages(message()))
        harness.fireWait()
        harness.host?.layout()
        scheduler.drain()
        XCTAssertNil(harness.host?.messageView?.imageView)
    }

    // MARK: trackEvent

    func test_trackEventBeforeInitializeLogsNothingWithTheName() {
        engine.trackEvent(eventName)
        scheduler.drain()
    }

    func test_aBlankTrackEventLogsNothingAtAll() {
        configure()
        engine.trackEvent("   ")
        engine.trackEvent("")
        scheduler.drain()
        XCTAssertTrue(lines.isEmpty)
    }

    func test_trackEventInASessionMatchedOrIgnoredLogsNoName() {
        fetch(.messages(message(trigger: eventName)))
        network.enqueue(.status(202))
        engine.trackEvent(eventName)
        scheduler.drain()
        harness.host?.layout()
        scheduler.drain()
        XCTAssertNotNil(harness.host, "the event matched")
        engine.trackEvent("fixture_unmatched")
        engine.sessionEnded()
        engine.appBackgrounded()
        engine.trackEvent(eventName)
        scheduler.drain()
    }

    func test_aConfigChangeTearingDownADisplayLogsNoSentinel() {
        showVisible()
        engine.configure(appId: "fixture-other-app", clientKey: clientKey, baseUrl: "https://api.example.invalid")
        scheduler.drain()
        XCTAssertEqual(harness.host?.hideCount, 1)
    }

    // MARK: Source guards (rule 3)

    func test_noSourceOpensAURLOutsideTheAllowlistedFile() throws {
        var files = try sources(under: "Sources/NottiSDK")
        files += try sources(under: "Sources/NottiSDKBootstrap")
        XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits(files), [])
        XCTAssertTrue(files.contains { $0.path == NottiInAppSourceGuard.allowlistedFile })
    }

    func test_theInAppUIHasNoRichTextOrWebView() throws {
        XCTAssertEqual(NottiInAppSourceGuard.richTextHits(try sources(under: "Sources/NottiSDK/InApp/UI")), [])
    }

    func test_noSourceUsesAnUndeclaredRequiredReasonAPI() throws {
        var files: [(path: String, text: String)] = []
        for target in ["Sources/NottiSDK", "Sources/NottiShared", "Sources/NottiSDKExtension", "Sources/NottiSDKBootstrap"] {
            files += try sources(under: target)
        }
        XCTAssertEqual(NottiInAppSourceGuard.requiredReasonHits(files), [])
    }

    /// The guards fail on a mutant: each banned string in a non-allowlisted file, and the URL-open tokens other than
    /// the allowlisted call inside the allowlisted file.
    func test_theSourceGuardsCatchEveryBannedStringInAMutant() {
        let engineFile = "Sources/NottiSDK/InApp/Engine/NottiInAppEngine.swift"
        for token in ["UIApplication.shared.open(url)", "app.open(_:options: [:])", "openURL(url)"] {
            XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits([(engineFile, "// \(token)")]).count, 1, token)
        }
        let allowlisted = NottiInAppSourceGuard.allowlistedFile
        XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits([(allowlisted, "UIApplication.shared.open(url)")]), [])
        XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits([(allowlisted, "openURL(url)")]).count, 1)
        XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits([(allowlisted, "x.open(_:options: [:])")]).count, 1)
        let moved = "Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction2.swift"
        XCTAssertEqual(NottiInAppSourceGuard.urlOpenHits([(moved, "UIApplication.shared.open(url)")]).count, 1)
        let uiFile = "Sources/NottiSDK/InApp/UI/NottiInAppMessageView.swift"
        for token in ["label.attributedText = x", "AttributedString(x)", "WKWebView()", "LocalizedStringKey(x)"] {
            XCTAssertEqual(NottiInAppSourceGuard.richTextHits([(uiFile, token)]).count, 1, token)
        }
        for token in ["ProcessInfo.processInfo.systemUptime", "mach_absolute_time()",
                      "values.contentModificationDate", "attributes.fileModificationDate()"] {
            XCTAssertEqual(NottiInAppSourceGuard.requiredReasonHits([(engineFile, token)]).count, 1, token)
        }
    }
}

/// The textual guards of tasks rule 3 (the same tokens as `scripts/check-no-url-open.sh`, comments included).
enum NottiInAppSourceGuard {
    static let allowlistedFile = "Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift"
    static let urlOpenTokens = ["UIApplication.shared.open", ".open(_:options", "openURL"]
    static let richTextTokens = ["attributedText", "AttributedString", "WKWebView", "LocalizedStringKey"]
    static let requiredReasonTokens = ["systemUptime", "mach_absolute_time", "contentModificationDate", "fileModificationDate"]

    /// `path:line: token` for every hit; the allowlisted file may contain only `UIApplication.shared.open(` lines.
    static func urlOpenHits(_ files: [(path: String, text: String)]) -> [String] {
        hits(files, urlOpenTokens) { path, line in
            path == allowlistedFile && line.contains("UIApplication.shared.open(")
                && !line.contains("openURL") && !line.contains(".open(_:options")
        }
    }

    static func richTextHits(_ files: [(path: String, text: String)]) -> [String] {
        hits(files, richTextTokens) { _, _ in false }
    }

    static func requiredReasonHits(_ files: [(path: String, text: String)]) -> [String] {
        hits(files, requiredReasonTokens) { _, _ in false }
    }

    private static func hits(
        _ files: [(path: String, text: String)],
        _ tokens: [String],
        allowed: (String, String) -> Bool
    ) -> [String] {
        var found: [String] = []
        for file in files {
            for (index, line) in file.text.components(separatedBy: "\n").enumerated() {
                for token in tokens where line.contains(token) && !allowed(file.path, line) {
                    found.append("\(file.path):\(index + 1): \(token)")
                }
            }
        }
        return found
    }
}
