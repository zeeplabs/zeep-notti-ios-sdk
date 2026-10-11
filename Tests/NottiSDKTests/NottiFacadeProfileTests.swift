import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiFacadeProfileTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiFacadeProfileTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        runtime = makeRuntime()
        facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
    }

    override func tearDown() {
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

    private func makeRuntime() -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        return NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(
                tokenProvider: { $0("apns-token-fixture") },
                permissionRequester: { $0(true) }
            ),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
    }

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

    /// Registers a device and returns once the registration response is applied.
    private func initializeFacade(registrationBody: String? = nil) {
        if let registrationBody {
            StubURLProtocol.enqueue(.status(200, body: registrationBody))
        } else {
            StubURLProtocol.enqueue(.echoDevice())
        }
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
    }

    /// Runs `call` on an initialized facade and returns the PATCH bodies it caused.
    private func patches(after call: () -> Void) -> [[String: Any]] {
        StubURLProtocol.enqueue(.echoDevice())
        let before = bodies("PATCH").count
        call()
        drain()
        return Array(bodies("PATCH").dropFirst(before))
    }

    // MARK: - On an initialized facade (API-04 ... API-08)

    func test_loginPatchesTheExternalUserId() {
        initializeFacade()

        let sent = patches { facade.login("user-fixture") }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["external_user_id"] as? String, "user-fixture")
    }

    func test_logoutClearsTheLocalUserAndSendsExplicitNullEmailAndPhone() {
        initializeFacade()
        _ = patches { facade.setEmail("user@example.invalid") }
        _ = patches { facade.setPhone("+10000000000") }
        _ = patches { facade.login("user-fixture") }
        XCTAssertEqual(store.getExternalUserId(), "user-fixture")
        StubURLProtocol.enqueue(.echoDevice())
        StubURLProtocol.enqueue(.echoDevice())
        let before = bodies("PATCH").count

        facade.logout()
        drain()

        XCTAssertNil(store.getExternalUserId())
        XCTAssertNil(store.getEmail())
        XCTAssertNil(store.getPhone())
        let sent = Array(bodies("PATCH").dropFirst(before))
        XCTAssertTrue(sent.contains { $0["email"] is NSNull })
        XCTAssertTrue(sent.contains { $0["phone"] is NSNull })
    }

    func test_addTagsPatchesTheMergedMap() {
        initializeFacade(registrationBody: #"{"id":"device-fixture","tags":{"lang":"pt"}}"#)

        let sent = patches { facade.addTags(["plan": "vip"]) }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["tags"] as? [String: String], ["lang": "pt", "plan": "vip"])
    }

    func test_removeTagsPatchesTheRemainingMap() {
        initializeFacade(registrationBody: #"{"id":"device-fixture","tags":{"lang":"pt","plan":"basic"}}"#)

        let sent = patches { facade.removeTags(["plan", "missing"]) }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["tags"] as? [String: String], ["lang": "pt"])
    }

    func test_setEmailAndSetPhonePatchTheirOwnFields() {
        initializeFacade()

        let email = patches { facade.setEmail("user@example.invalid") }
        let phone = patches { facade.setPhone("+10000000000") }

        XCTAssertEqual(email.count, 1)
        XCTAssertEqual(email.first?["email"] as? String, "user@example.invalid")
        XCTAssertNil(email.first?["tags"], "email never travels inside tags (DPF-21)")
        XCTAssertEqual(phone.count, 1)
        XCTAssertEqual(phone.first?["phone"] as? String, "+10000000000")
    }

    func test_clearEmailAndClearPhoneSendExplicitNull() {
        initializeFacade()
        _ = patches { facade.setEmail("user@example.invalid") }
        _ = patches { facade.setPhone("+10000000000") }

        let email = patches { facade.clearEmail() }
        let phone = patches { facade.clearPhone() }

        XCTAssertEqual(email.count, 1)
        XCTAssertTrue(email.first?["email"] is NSNull)
        XCTAssertEqual(phone.count, 1)
        XCTAssertTrue(phone.first?["phone"] is NSNull)
    }

    func test_unsubscribingSendsSubscribedFalseWithLastUnsubscribedAt() {
        initializeFacade()

        let sent = patches { facade.setSubscription(false) }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["subscribed"] as? Bool, false)
        XCTAssertNotNil(sent.first?["last_unsubscribed_at"])
    }

    func test_subscribingSendsSubscribedTrueWithoutLastUnsubscribedAt() {
        initializeFacade()

        let sent = patches { facade.setSubscription(true) }

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["subscribed"] as? Bool, true)
        XCTAssertNil(sent.first?["last_unsubscribed_at"])
    }

    // MARK: - Before initialize (API-05, API-07)

    func test_emailAndPhoneSetBeforeInitializeArePersistedAndSentAtRegistration() {
        facade.setEmail("user@example.invalid")
        facade.setPhone("+10000000000")
        // Not drained on purpose: `initialize` replaces the ensured core right away
        // and the values must still survive (the realistic host call order).
        StubURLProtocol.enqueue(.echoDevice()) // registration
        StubURLProtocol.enqueue(.echoDevice()) // email
        StubURLProtocol.enqueue(.echoDevice()) // phone
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()

        XCTAssertEqual(store.getEmail(), "user@example.invalid")
        XCTAssertEqual(store.getPhone(), "+10000000000")
        let sent = bodies("PATCH")
        XCTAssertTrue(sent.contains { $0["email"] as? String == "user@example.invalid" })
        XCTAssertTrue(sent.contains { $0["phone"] as? String == "+10000000000" })
    }

    func test_loginTagsAndSubscriptionBeforeInitializeSendNothingAndDoNotCrash() {
        facade.login("user-fixture")
        facade.addTags(["plan": "vip"])
        facade.removeTags(["plan"])
        facade.setSubscription(false)
        facade.logout()
        drain()

        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
        XCTAssertNil(store.getExternalUserId())
        XCTAssertEqual(store.getTags(), [:])
    }

    func test_deviceIdIsThePersistedIdBeforeInitialize() {
        store.setDeviceId("device-persisted-fixture")

        XCTAssertEqual(facade.deviceId, "device-persisted-fixture")
    }

    func test_deviceIdIsNilForADeviceThatNeverRegistered() {
        XCTAssertNil(facade.deviceId)
    }

    func test_deviceIdIsTheRegisteredIdAfterInitialize() {
        initializeFacade(registrationBody: #"{"id":"device-registered-fixture","tags":{}}"#)

        XCTAssertEqual(facade.deviceId, "device-registered-fixture")
    }

    // MARK: - Location sharing (LGPD B1)

    func test_locationSharingPreferenceIsWrittenBeforeTheCallReturns() {
        XCTAssertFalse(store.getLocationSharingEnabled(), "default is off")

        facade.setLocationSharingEnabled(true)
        XCTAssertTrue(store.getLocationSharingEnabled(), "read back synchronously, no drain")

        facade.setLocationSharingEnabled(false)
        XCTAssertFalse(store.getLocationSharingEnabled(), "an opt-out is durable immediately")
    }
}
