import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// API-01, API-03, API-15: every public `Notti` entry point reaches the facade,
/// and the production facade is wired to the `notti_prefs` suite (F1).
///
/// Most tests route `Notti` to a facade on an isolated runtime through the
/// internal test seam; only the F1 test uses the real shared facade.
final class NottiPublicApiTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

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
    private var sessions: [URLSession] = []
    private var savedLevel: NottiLogLevel = .error
    private var permissionAnswer = true
    private var swizzlingActive = false

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiPublicApiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        permissionAnswer = true
        swizzlingActive = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("apns-token-fixture") },
                permissionRequester: { [weak self] in $0(self?.permissionAnswer ?? false) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        facade = NottiFacade(
            runtime: runtime,
            dispatcher: { $0() },
            isSwizzlingActive: { [weak self] in self?.swizzlingActive ?? false }
        )
        NottiFacade.setSharedForTesting(facade)
    }

    override func tearDown() {
        NottiFacade.setSharedForTesting(nil)
        NottiLogger.level = savedLevel
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

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func bodies(_ method: String) -> [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == method }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
    }

    private var store: NottiDeviceStore { NottiDeviceStore(defaults: defaults) }

    /// Registers through the public entry point and waits for the response.
    private func initializePublic(registrationBody: String? = nil) {
        if let registrationBody {
            StubURLProtocol.enqueue(.status(200, body: registrationBody))
        } else {
            StubURLProtocol.enqueue(.echoDevice())
        }
        Notti.initialize(appId: appId, clientKey: clientKey, options: Notti.Options(baseUrl: baseUrl))
        drain()
    }

    private func patches(after call: () -> Void) -> [[String: Any]] {
        StubURLProtocol.enqueue(.echoDevice())
        let before = bodies("PATCH").count
        call()
        drain()
        return Array(bodies("PATCH").dropFirst(before))
    }

    // MARK: - Initialize and identity

    func test_initializeReachesTheFacadeWithTheOptionsBaseUrl() {
        initializePublic()

        let posts = StubURLProtocol.recordedRequests().filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.url?.host, "notti.example.invalid")
        XCTAssertEqual(facade.activeConfig?.appId, appId)
    }

    func test_initializeWithoutOptionsUsesTheDefaultHost() {
        StubURLProtocol.enqueue(.echoDevice())
        Notti.initialize(appId: appId, clientKey: clientKey)
        drain()

        let posts = StubURLProtocol.recordedRequests().filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.first?.url?.absoluteString.hasPrefix(NottiFacade.defaultBaseUrl), true)
    }

    func test_loginAndLogoutReachTheFacade() {
        initializePublic()

        let login = patches { Notti.login("user-fixture") }
        XCTAssertEqual(login.first?["external_user_id"] as? String, "user-fixture")
        XCTAssertEqual(store.getExternalUserId(), "user-fixture")

        StubURLProtocol.enqueue(.echoDevice())
        Notti.logout()
        drain()
        XCTAssertNil(store.getExternalUserId())
    }

    func test_deviceIdReachesTheFacade() {
        store.setDeviceId("device-persisted-fixture")

        XCTAssertEqual(Notti.deviceId, "device-persisted-fixture")
    }

    func test_deviceIdChangedListenerReachesTheFacadeAndCanBeRemoved() {
        let log = Log()
        let subscription = Notti.addDeviceIdChangedListener { log.append($0) }

        initializePublic(registrationBody: #"{"id":"device-one-fixture","tags":{}}"#)
        XCTAssertEqual(log.values, ["device-one-fixture"])

        subscription.remove()
        Notti.initialize(appId: "other-app-fixture", clientKey: clientKey, options: Notti.Options(baseUrl: baseUrl))
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-two-fixture","tags":{}}"#))
        drain()
        XCTAssertEqual(log.values, ["device-one-fixture"])
    }

    func test_setLocationSharingEnabledReachesTheFacade() {
        Notti.setLocationSharingEnabled(true)
        XCTAssertTrue(store.getLocationSharingEnabled())

        Notti.setLocationSharingEnabled(false)
        XCTAssertFalse(store.getLocationSharingEnabled())
    }

    func test_logLevelGetAndSetReachTheLogger() {
        Notti.logLevel = .verbose
        XCTAssertEqual(NottiLogger.level, .verbose)
        XCTAssertEqual(Notti.logLevel, .verbose)

        let typed: Notti.LogLevel = .warn
        Notti.logLevel = typed
        XCTAssertEqual(NottiLogger.level, .warn)
    }

    // MARK: - User

    func test_userTagMethodsReachTheFacade() {
        initializePublic(registrationBody: #"{"id":"device-fixture","tags":{"lang":"pt"}}"#)

        let one = patches { Notti.User.addTag("plan", value: "vip") }
        XCTAssertEqual(one.first?["tags"] as? [String: String], ["lang": "pt", "plan": "vip"])

        let many = patches { Notti.User.addTags(["tier": "gold"]) }
        XCTAssertEqual(many.first?["tags"] as? [String: String], ["lang": "pt", "plan": "vip", "tier": "gold"])

        let removedOne = patches { Notti.User.removeTag("tier") }
        XCTAssertEqual(removedOne.first?["tags"] as? [String: String], ["lang": "pt", "plan": "vip"])

        let removedMany = patches { Notti.User.removeTags(["plan", "lang"]) }
        XCTAssertEqual(removedMany.first?["tags"] as? [String: String], [:])
    }

    func test_userEmailPhoneAndSubscriptionMethodsReachTheFacade() {
        initializePublic()

        XCTAssertEqual(patches { Notti.User.setEmail("user@example.invalid") }.first?["email"] as? String, "user@example.invalid")
        XCTAssertTrue(patches { Notti.User.clearEmail() }.first?["email"] is NSNull)
        XCTAssertEqual(patches { Notti.User.setPhone("+10000000000") }.first?["phone"] as? String, "+10000000000")
        XCTAssertTrue(patches { Notti.User.clearPhone() }.first?["phone"] is NSNull)
        XCTAssertEqual(patches { Notti.User.setSubscription(false) }.first?["subscribed"] as? Bool, false)
    }

    // MARK: - Notifications

    func test_requestPermissionCompletionReachesTheFacade() {
        initializePublic()
        let log = Log()

        permissionAnswer = true
        Notti.Notifications.requestPermission { log.append("granted=\($0)") }
        drain()
        permissionAnswer = false
        Notti.Notifications.requestPermission { log.append("granted=\($0)") }
        drain()

        XCTAssertEqual(log.values, ["granted=true", "granted=false"])
    }

    func test_requestPermissionAsyncReachesTheFacade() async {
        initializePublic()
        permissionAnswer = true

        let granted = await Notti.Notifications.requestPermission()

        XCTAssertTrue(granted)
    }

    /// Verifier r1 G2: one event type at a time, with a different payload per event,
    /// so a listener wired to the wrong event cannot pass.
    func test_receivedAndClickedListenersReachTheFacadeEachOnItsOwnEvent() {
        let received = Log()
        let clicked = Log()
        let receivedSub = Notti.Notifications.addReceivedListener { received.append($0.title ?? "") }
        let clickedSub = Notti.Notifications.addClickedListener { clicked.append($0.title ?? "") }

        let clickedPayload = ParsedNotification(
            title: "Clicked title fixture", body: "Clicked body fixture", data: ["id": "n-c"]
        ).toEventPayload()
        let receivedPayload = ParsedNotification(
            title: "Received title fixture", body: "Received body fixture", data: ["id": "n-r"]
        ).toEventPayload()

        runtime.eventBuffer.emit(.clicked, identifier: "n-c", payload: clickedPayload)
        XCTAssertEqual(clicked.values, ["Clicked title fixture"])
        XCTAssertEqual(received.values, [], "a clicked event must not reach the received listener")

        runtime.eventBuffer.emit(.received, identifier: "n-r", payload: receivedPayload)
        XCTAssertEqual(received.values, ["Received title fixture"])
        XCTAssertEqual(clicked.values, ["Clicked title fixture"], "a received event must not reach the clicked listener")

        receivedSub.remove()
        clickedSub.remove()
    }

    func test_takeInitialClickReachesTheFacade() {
        let payload = ParsedNotification(title: "Title fixture", body: "Body fixture", data: ["id": "n-2"]).toEventPayload()
        runtime.eventBuffer.emit(.clicked, identifier: "n-2", payload: payload)

        XCTAssertEqual(Notti.Notifications.takeInitialClick()?.data, ["id": "n-2"])
        XCTAssertNil(Notti.Notifications.takeInitialClick())
    }

    // MARK: - Manual forwarding (DEL-08, DEL-09)

    private func makeNotification(userInfo: [AnyHashable: Any], identifier: String = "req-1") -> UNNotification {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        guard let notification = (UNNotification.self as NSObject.Type).init() as? UNNotification else {
            fatalError("could not allocate UNNotification")
        }
        notification.setValue(request, forKey: "request")
        notification.setValue(Date(), forKey: "date")
        return notification
    }

    private func makeResponse(
        userInfo: [AnyHashable: Any],
        action: String = UNNotificationDefaultActionIdentifier
    ) -> UNNotificationResponse {
        guard let response = (UNNotificationResponse.self as NSObject.Type).init() as? UNNotificationResponse else {
            fatalError("could not allocate UNNotificationResponse")
        }
        response.setValue(makeNotification(userInfo: userInfo), forKey: "notification")
        response.setValue(action, forKey: "actionIdentifier")
        return response
    }

    private func nottiUserInfo(notificationId: String = "n-1", deliveryId: String = "d-1") -> [AnyHashable: Any] {
        ["aps": ["alert": ["title": "Title fixture", "body": "Body fixture"]], "notification_id": notificationId, "delivery_id": deliveryId]
    }

    private var silentUserInfo: [AnyHashable: Any] {
        ["aps": ["content-available": 1], "notification_id": "n-s", "delivery_id": "d-s"]
    }

    private var storedTypes: [String] { runtime.eventStore.all().map(\.type) }

    private func captureLogs(_ body: () -> Void) -> [(NottiLogLevel, String)] {
        let lock = NSLock()
        var captured: [(NottiLogLevel, String)] = []
        NottiLogger.level = .verbose
        NottiLogger.sink = { level, message in lock.withLock { captured.append((level, message)) } }
        defer { NottiLogger.sink = nil }
        body()
        return lock.withLock { captured }
    }

    func test_manualDidRegisterReachesTheAdapterAndRegistersTheHexToken() {
        initializePublic()
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(.echoDevice())

        Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: Data([0xAB, 0x01, 0xFF]))
        drain()

        XCTAssertEqual(bodies("POST").first?["token"] as? String, "ab01ff")
    }

    func test_manualDidFailLogsDomainAndCodeOnly() {
        let logs = captureLogs {
            Notti.Notifications.didFailToRegisterForRemoteNotifications(
                error: NSError(domain: "fixture.apns", code: 3000, userInfo: [NSLocalizedDescriptionKey: "https://notti.example.invalid/secret"])
            )
        }

        XCTAssertEqual(logs.filter { $0.0 == .error }.map(\.1), ["Notti: failed to register for remote notifications - fixture.apns#3000"])
        XCTAssertFalse(logs.contains { $0.1.contains("example.invalid") })
    }

    func test_manualDidReceiveRemoteNotificationReportsASilentPushAndReturnsNoData() {
        XCTAssertEqual(Notti.Notifications.didReceiveRemoteNotification(silentUserInfo), .noData)
        XCTAssertEqual(storedTypes, ["received"])
    }

    func test_manualWillPresentReportsANottiPushAndReturnsTheD2Options() {
        let options = Notti.Notifications.willPresent(makeNotification(userInfo: nottiUserInfo()))

        XCTAssertEqual(options, [.banner, .list, .sound, .badge])
        XCTAssertEqual(storedTypes, ["received"])
    }

    func test_manualWillPresentOfANonNottiNotificationReturnsNoOptionsAndReportsNothing() {
        let options = Notti.Notifications.willPresent(makeNotification(userInfo: ["custom": "fixture"]))

        XCTAssertEqual(options, [])
        XCTAssertTrue(storedTypes.isEmpty)
    }

    func test_manualDidReceiveOfABodyTapQueuesOneOpenedAndOneClicked() {
        Notti.Notifications.didReceive(makeResponse(userInfo: nottiUserInfo()))

        XCTAssertEqual(storedTypes, ["opened", "clicked"])
    }

    func test_manualDidReceiveBeforeInitializeIsBufferedLikeTheSwizzledPath() {
        XCTAssertNil(facade.activeConfig)

        Notti.Notifications.didReceive(makeResponse(userInfo: nottiUserInfo()))

        XCTAssertEqual(storedTypes, ["opened", "clicked"], "queued with no core")
        XCTAssertEqual(Notti.Notifications.takeInitialClick()?.title, "Title fixture")
        XCTAssertNil(Notti.Notifications.takeInitialClick(), "once")
    }

    func test_whileSwizzlingIsActiveEveryManualCallIsIgnoredWithOneWarnAndNoValues() {
        swizzlingActive = true
        let userInfo = nottiUserInfo(notificationId: "n-sentinel", deliveryId: "d-sentinel")
        let calls: [() -> Void] = [
            { Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: Data([0xDE, 0xAD])) },
            { Notti.Notifications.didFailToRegisterForRemoteNotifications(error: NSError(domain: "fixture.sentinel", code: 77)) },
            { _ = Notti.Notifications.didReceiveRemoteNotification(self.silentUserInfo) },
            { _ = Notti.Notifications.willPresent(self.makeNotification(userInfo: userInfo)) },
            { Notti.Notifications.didReceive(self.makeResponse(userInfo: userInfo)) }
        ]

        let logs = captureLogs {
            for call in calls {
                let before = StubURLProtocol.recordedRequests().count
                call()
                XCTAssertEqual(StubURLProtocol.recordedRequests().count, before)
            }
        }

        XCTAssertEqual(logs.filter { $0.0 == .warn }.count, 5, "one warn per ignored call")
        XCTAssertEqual(logs.count, 5, "nothing else is logged")
        XCTAssertTrue(storedTypes.isEmpty, "nothing reported")
        XCTAssertNil(runtime.eventBuffer.takeInitialClick())
        for (_, message) in logs {
            for sentinel in ["dead", "sentinel", "Title fixture", "Body fixture", "77", "d-s", "n-s"] {
                XCTAssertFalse(message.contains(sentinel), "log leaked \(sentinel)")
            }
        }
    }

    // MARK: - G2: the production facade is wired to the production swizzling state

    /// DEL-09 / DEL-07, Verifier r1 G2. Goes through `NottiFacade.shared` (production) with the
    /// production `NottiSwizzlingState.shared`: the override facade used elsewhere would hide a wrong
    /// `isSwizzlingActive` binding, and the manual API would then double-report.
    func test_productionFacadeIgnoresEveryManualCallWhileTheSharedSwizzlingStateIsActive() {
        NottiFacade.setSharedForTesting(nil)
        let state = NottiSwizzlingState.shared
        let wasActive = state.isActive
        defer { state.setActive(wasActive) }
        state.setActive(true)
        let storedBefore = NottiRuntime.shared.eventStore.all().count
        let userInfo = nottiUserInfo(notificationId: "n-g2", deliveryId: "d-g2")
        let calls: [() -> Void] = [
            { Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: Data([0x01])) },
            { Notti.Notifications.didFailToRegisterForRemoteNotifications(error: NSError(domain: "fixture.g2", code: 5)) },
            { _ = Notti.Notifications.didReceiveRemoteNotification(self.silentUserInfo) },
            { Notti.Notifications.didReceive(self.makeResponse(userInfo: userInfo)) }
        ]

        let logs = captureLogs { calls.forEach { $0() } }

        XCTAssertEqual(logs.filter { $0.0 == .warn }.count, calls.count, "one warn per ignored call")
        XCTAssertEqual(logs.count, calls.count, "nothing processed, so nothing else is logged (no `.error` for the failure)")
        XCTAssertEqual(NottiRuntime.shared.eventStore.all().count, storedBefore, "nothing reported")
    }

    func test_productionFacadeProcessesManualCallsWhileTheSharedSwizzlingStateIsInactive() {
        NottiFacade.setSharedForTesting(nil)
        let state = NottiSwizzlingState.shared
        let wasActive = state.isActive
        defer { state.setActive(wasActive) }
        state.setActive(false)

        let logs = captureLogs {
            Notti.Notifications.didRegisterForRemoteNotifications(deviceToken: Data([0x01]))
            Notti.Notifications.didFailToRegisterForRemoteNotifications(error: NSError(domain: "fixture.g2", code: 5))
        }

        XCTAssertTrue(logs.filter { $0.0 == .warn }.isEmpty, "no ignore warning")
        XCTAssertEqual(logs.filter { $0.0 == .error }.count, 1, "the failure reached the runtime")
        XCTAssertEqual(logs.first { $0.0 == .error }?.1.contains("fixture.g2#5"), true)
    }

    // MARK: - F1: the production facade reads the real `notti_prefs` suite

    /// core-port Verifier r2 F1 / API-03. Uses the literal suite name on purpose:
    /// the constant is covered by `NottiDeviceStoreKeysTests`, and a test that
    /// read the constant would follow a renamed suite instead of catching it.
    func test_productionFacadeReadsTheDeviceIdFromTheNottiPrefsSuite() throws {
        NottiFacade.setSharedForTesting(nil)
        let suite = try XCTUnwrap(UserDefaults(suiteName: "notti_prefs"))
        let realStore = NottiDeviceStore(defaults: suite)
        let previous = realStore.getDeviceId()
        defer { realStore.setDeviceId(previous) }
        realStore.setDeviceId("device-f1-fixture")

        XCTAssertEqual(Notti.deviceId, "device-f1-fixture")
    }
}
