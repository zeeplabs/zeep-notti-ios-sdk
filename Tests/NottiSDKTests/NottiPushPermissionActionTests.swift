import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-45, IAM-49 (wiring), IAM-50: the `push_permission` platform action (port of RN
/// `NottiPushPermissionActionTests`, 0.8.0), the source pin of the one allowlisted URL-opening file (AD-019),
/// and the runtime port. Every OS effect is injected: no `UNUserNotificationCenter.current()`, no
/// `UIApplication.shared`, no real network.
final class NottiPushPermissionActionTests: XCTestCase {

    private final class Probe {
        var effects: [String] = []
        var logs: [String] = []
        private(set) var action: NottiPushPermissionAction!

        init(state: NottiPushPermissionAction.State) {
            action = NottiPushPermissionAction(
                readState: { $0(state) },
                requestPermission: { [unowned self] in self.effects.append("request") },
                openNotificationSettings: { [unowned self] in self.effects.append("settings") },
                logger: { [unowned self] in self.logs.append($0) }
            )
        }
    }

    // MARK: - State table

    func test_notDeterminedRequestsThePermissionOnceAndNothingElse() {
        let probe = Probe(state: .notDetermined)
        probe.action.run()
        XCTAssertEqual(probe.effects, ["request"])
        XCTAssertEqual(probe.logs, [])
    }

    func test_deniedOpensTheNotificationSettingsOnceAndNeverRequests() {
        let probe = Probe(state: .denied)
        probe.action.run()
        XCTAssertEqual(probe.effects, ["settings"])
        XCTAssertEqual(probe.logs, [])
    }

    func test_authorizedProvisionalAndEphemeralDoNothing() {
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            let probe = Probe(state: NottiPushPermissionAction.State(status))
            probe.action.run()
            XCTAssertEqual(probe.effects, [], "\(status.rawValue)")
            XCTAssertEqual(probe.logs, [], "\(status.rawValue)")
        }
    }

    func test_unknownLogsExactlyOneFixedLineWithNoValues() {
        let probe = Probe(state: .unknown)
        probe.action.run()
        XCTAssertEqual(probe.effects, [])
        XCTAssertEqual(probe.logs, ["Notti.inapp: push permission state unavailable"])
    }

    func test_authorizationStatusesMapToTheState() {
        XCTAssertEqual(NottiPushPermissionAction.State(.notDetermined), .notDetermined)
        XCTAssertEqual(NottiPushPermissionAction.State(.denied), .denied)
        XCTAssertEqual(NottiPushPermissionAction.State(.authorized), .granted)
        XCTAssertEqual(NottiPushPermissionAction.State(.provisional), .granted)
        XCTAssertEqual(NottiPushPermissionAction.State(.ephemeral), .granted)
    }

    func test_aStateAnsweredOnABackgroundThreadStillRunsTheRowOnce() {
        let lock = NSLock()
        var effects: [String] = []
        let answered = expectation(description: "effect")
        let action = NottiPushPermissionAction(
            readState: { callback in DispatchQueue.global().async { callback(.denied) } },
            requestPermission: { lock.withLock { effects.append("request") } },
            openNotificationSettings: {
                lock.withLock { effects.append("settings") }
                answered.fulfill()
            },
            logger: { _ in }
        )
        action.run()
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(lock.withLock { effects }, ["settings"])
    }

    // MARK: - The allowlisted file (AD-019)

    func test_theAllowlistedFileOpensOnlyTheSystemSettingsConstants() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NottiSDK/InApp/Platform/NottiPushPermissionAction.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertEqual(occurrences(of: "UIApplication.shared.open(", in: text), 1, "exactly one open call")
        XCTAssertEqual(occurrences(of: "URL(", in: text), 1, "one URL is built")
        XCTAssertEqual(occurrences(of: "URL(string: raw)", in: text), 1, "and only from `raw`")
        let assignments = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("raw = ") }
        XCTAssertEqual(assignments, [
            "raw = UIApplication.openNotificationSettingsURLString",
            "raw = UIApplication.openSettingsURLString"
        ])
        for banned in ["NottiInApp", "payload", "userInfo", "openURL", ".open(_:options", "value"] {
            XCTAssertFalse(text.contains(banned), "the file must not reference \(banned)")
        }
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}

/// The runtime hands the engine a port built at `start` whose prompt goes through the current core.
final class NottiPushPermissionPortWiringTests: XCTestCase {

    private let appId = "fixture-app"
    private let clientKey = "sentinel-key"
    private let baseUrl = "https://notti.example.invalid"
    private static let registered = #"{"id":"fixture-device","tags":{}}"#
    private static let permissionButton =
        #","buttons":[{"id":"fixture-perm","label":"fixture","action":{"type":"push_permission"}}]"#

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var scheduler: InAppFakeScheduler!
    private var network: InAppFakeNetwork!
    private var presenter: InAppFakePresenter!
    private var engine: NottiInAppEngine!
    private var runtimes: [NottiRuntime] = []
    private var sessions: [URLSession] = []
    private let lock = NSLock()
    private var prompts = 0
    private var settingsOpened = 0

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiPushPermissionPortWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        scheduler = InAppFakeScheduler()
        network = InAppFakeNetwork()
        presenter = InAppFakePresenter()
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
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        super.tearDown()
    }

    private func makeRuntime(state: NottiPushPermissionAction.State?) -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let platform = state.map { state in
            NottiPushPermissionAction.Platform(
                readState: { $0(state) },
                openNotificationSettings: { [unowned self] in self.lock.withLock { self.settingsOpened += 1 } }
            )
        }
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("fixture-token") },
                permissionRequester: { [unowned self] callback in
                    self.lock.withLock { self.prompts += 1 }
                    callback(false)
                },
                appStateProvider: { $0(true) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            startObservers: false,
            inAppEngine: engine,
            notificationCenter: NotificationCenter(),
            pushPermissionPlatform: platform
        )
        runtimes.append(runtime)
        return runtime
    }

    private func settle(_ runtime: NottiRuntime) {
        XCTAssertTrue(runtime.core?.waitForPendingWork(timeout: 25) ?? false, "core did not drain")
        scheduler.drain()
    }

    /// Registers, fetches `messageId` with a `push_permission` button and taps it.
    private func startAndTap(_ runtime: NottiRuntime, app: String, messageId: String) {
        StubURLProtocol.enqueue(.status(200, body: Self.registered))
        StubURLProtocol.enqueue(.status(200, body: "{}"))
        network.enqueue(.messages(InAppFixtureJSON.sessionStart(messageId, extra: Self.permissionButton)))
        runtime.start(appId: app, clientKey: clientKey, baseUrl: baseUrl)
        settle(runtime)
        guard let display = presenter.presented.last, display.message.id == messageId else {
            return XCTFail("\(messageId) not presented")
        }
        engine.displayAttached(displayId: display.id, attached: true)
        engine.becameVisible(displayId: display.id)
        engine.userTapped(displayId: display.id, buttonId: "fixture-perm", action: .pushPermission)
        // The port runs on the engine's (here inline) main dispatcher and queues the prompt on the core.
        scheduler.drain()
        settle(runtime)
    }

    private var promptCount: Int { lock.withLock { prompts } }
    private var settingsCount: Int { lock.withLock { settingsOpened } }

    private func patches(toApp app: String) -> Int {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "PATCH" && ($0.url?.path ?? "").contains("/\(app)/") }.count
    }

    func test_afterStartTheEnginesPortReachesTheCurrentCore() {
        let runtime = makeRuntime(state: .notDetermined)
        scheduler.drain()
        XCTAssertNil(engine.pushPermissionPort, "no port before start")

        startAndTap(runtime, app: appId, messageId: "fixture-msg")
        XCTAssertNotNil(engine.pushPermissionPort)
        XCTAssertEqual(promptCount, 1, "the tap reached NottiCore.requestPermission")
        XCTAssertEqual(settingsCount, 0)
        let firstPatches = patches(toApp: appId)
        XCTAssertGreaterThanOrEqual(firstPatches, 1, "the core sent the subscribed update")

        let firstCore = runtime.core
        startAndTap(runtime, app: "fixture-app-2", messageId: "fixture-msg-2")
        XCTAssertFalse(runtime.core === firstCore, "the core was replaced")
        XCTAssertEqual(promptCount, 2)
        XCTAssertGreaterThanOrEqual(patches(toApp: "fixture-app-2"), 1, "the replacement core prompted")
        XCTAssertEqual(patches(toApp: appId), firstPatches, "the old core did not")
    }

    func test_aDeniedStateOpensTheSettingsThroughThePort() {
        let runtime = makeRuntime(state: .denied)
        startAndTap(runtime, app: appId, messageId: "fixture-msg")

        XCTAssertEqual(settingsCount, 1)
        XCTAssertEqual(promptCount, 0)
    }

    func test_aRuntimeWithNoPlatformSetsNoPort() {
        let runtime = makeRuntime(state: nil)
        startAndTap(runtime, app: appId, messageId: "fixture-msg")

        XCTAssertNil(engine.pushPermissionPort)
        XCTAssertEqual(promptCount, 0)
        XCTAssertEqual(presenter.closed.count, 1, "the tap still reports and closes")
    }
}
