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

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiPublicApiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        permissionAnswer = true
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
        facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
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

    func test_receivedAndClickedListenersReachTheFacade() {
        let received = Log()
        let clicked = Log()
        let receivedSub = Notti.Notifications.addReceivedListener { received.append($0.title ?? "") }
        let clickedSub = Notti.Notifications.addClickedListener { clicked.append($0.body ?? "") }

        let payload = ParsedNotification(title: "Title fixture", body: "Body fixture", data: ["id": "n-1"]).toEventPayload()
        runtime.eventBuffer.emit(.received, identifier: "n-1", payload: payload)
        runtime.eventBuffer.emit(.clicked, identifier: "n-1", payload: payload)
        XCTAssertEqual(received.values, ["Title fixture"])
        XCTAssertEqual(clicked.values, ["Body fixture"])

        receivedSub.remove()
        clickedSub.remove()
    }

    func test_takeInitialClickReachesTheFacade() {
        let payload = ParsedNotification(title: "Title fixture", body: "Body fixture", data: ["id": "n-2"]).toEventPayload()
        runtime.eventBuffer.emit(.clicked, identifier: "n-2", payload: payload)

        XCTAssertEqual(Notti.Notifications.takeInitialClick()?.data, ["id": "n-2"])
        XCTAssertNil(Notti.Notifications.takeInitialClick())
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
