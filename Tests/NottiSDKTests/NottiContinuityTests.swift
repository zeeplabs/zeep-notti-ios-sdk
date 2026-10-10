import XCTest
@testable import NottiSDK

/// CORE-09..11: a device that ran react-native-notti 0.6.0 keeps its state.
///
/// `Fixtures/rn-0.6.0-state.plist` is hand-authored from RN's key and value
/// encodings (`NottiDeviceStore.swift:88-117`, `NottiEventStore.swift:61`,
/// README:532-560) with synthetic values. Its `notti_pending_events` JSON was
/// written by hand from RN's `PendingEvent` field names, not by the ported encoder.
final class NottiContinuityTests: XCTestCase {

    private let fixtureDeviceId = "device-fixture-id"
    private let fixtureToken = "0f1e2d3c4b5a6978"
    private let fixtureTokenBytes = Data([0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78])

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime?
    private var session: URLSession?

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiContinuityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        let core = runtime?.core
        runtime?.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        session?.invalidateAndCancel()
        session = nil
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func loadFixture(file: StaticString = #filePath, line: UInt = #line) throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "rn-0.6.0-state", withExtension: "plist", subdirectory: "Fixtures"),
            file: file,
            line: line
        )
        let data = try Data(contentsOf: url)
        let state = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            file: file,
            line: line
        )
        for (key, value) in state {
            defaults.set(value, forKey: key)
        }
    }

    private func makeRuntime(providers: NottiPlatformProviders) -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        self.session = session
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: providers,
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        self.runtime = runtime
        return runtime
    }

    private func drain(_ core: NottiCore?, file: StaticString = #filePath, line: UInt = #line) {
        guard let core else {
            XCTFail("no core", file: file, line: line)
            return
        }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private func requests(pathSuffix: String) -> [URLRequest] {
        StubURLProtocol.recordedRequests().filter { $0.url?.path.hasSuffix(pathSuffix) == true }
    }

    private func jsonBody(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    /// Launch on migrated state before APNs hands over a token (RN `tokenProvider`
    /// never answers synchronously on iOS): RN 0.6.0 would not register here, so
    /// nothing is POSTed to `/devices`. The foreground flush uses the persisted
    /// token and drains the two RN pending events with their original ids.
    func test_rnStateIsAdoptedWithoutRegistrationAndItsPendingEventsFlush() throws {
        try loadFixture()
        let activated = expectation(description: "app state read on main")
        let runtime = makeRuntime(providers: NottiPlatformProviders(
            tokenProvider: { _ in },
            permissionRequester: { $0(true) },
            appStateProvider: { callback in
                DispatchQueue.main.async {
                    callback(true)
                    activated.fulfill()
                }
            }
        ))
        // The orphaned RN session is closed first: the device is already
        // registered (persisted id + token), so its session PATCH goes out now.
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture-id","tags":{"plan":"fixture","lang":"pt"}}"#))
        StubURLProtocol.enqueue(.status(204)) // event d-fixture-1
        StubURLProtocol.enqueue(.status(204)) // event d-fixture-2

        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        wait(for: [activated], timeout: 5)
        drain(runtime.core)

        XCTAssertTrue(requests(pathSuffix: "/devices").isEmpty, "no POST /devices: RN would not re-register without a token")
        XCTAssertEqual(runtime.core?.getDeviceId(), fixtureDeviceId)
        let patches = StubURLProtocol.recordedRequests().filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(patches.map { $0.url?.path }, ["/v1/apps/app-fixture/devices/device-fixture-id"], "addressed to the RN device id")
        XCTAssertEqual(patches.first.map(jsonBody)?["session_count"] as? Int, 8)
        XCTAssertEqual(patches.first.map(jsonBody)?["token"] as? String, fixtureToken)

        let events = requests(pathSuffix: "/events")
        XCTAssertEqual(events.map { $0.url?.path }, [
            "/v1/apps/app-fixture/notifications/n-fixture-1/events",
            "/v1/apps/app-fixture/notifications/n-fixture-2/events"
        ])
        XCTAssertEqual(events.compactMap { jsonBody($0)["delivery_id"] as? String }, ["d-fixture-1", "d-fixture-2"])
        XCTAssertEqual(events.compactMap { jsonBody($0)["type"] as? String }, ["received", "clicked"])
        XCTAssertEqual(events.compactMap { jsonBody($0)["token"] as? String }, [fixtureToken, fixtureToken])
        XCTAssertTrue(runtime.eventStore.all().isEmpty)

        // Session keys were read with RN's encodings: the open session left by
        // the killed RN process is closed at its last heartbeat (+30s, +1 count).
        let store = NottiDeviceStore(defaults: defaults)
        XCTAssertEqual(store.getSessionCount(), 8)
        XCTAssertEqual(store.getSessionTimeMs(), 3_630_000)
        XCTAssertEqual(store.getFirstSessionAtMs(), 1_700_000_000_000)
        XCTAssertEqual(store.getTags(), ["plan": "fixture", "lang": "pt"])
        XCTAssertEqual(store.getExternalUserId(), "external-fixture")
        XCTAssertEqual(store.getSubscribedIfKnown(), true)
    }

    /// When APNs then delivers the same token, RN re-POSTs (upsert); the backend
    /// answers with the same device id, so the id does not change and no
    /// device-id change is reported. The `notti_profile_field_ack_migrated`
    /// flag is honored: the ack migration does not run again, so no profile
    /// field is re-sent.
    func test_sameTokenReRegistrationKeepsTheRnDeviceIdAndSkipsTheAckMigration() throws {
        try loadFixture()
        let runtime = makeRuntime(providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }))
        var changedIds: [String] = []
        runtime.onDeviceIdChanged = { changedIds.append($0) }
        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture-id","tags":{"plan":"fixture","lang":"pt"}}"#))
        StubURLProtocol.enqueue(.echoDevice()) // held email re-sent on registration (RN DPF-19)
        StubURLProtocol.enqueue(.echoDevice()) // held phone re-sent on registration (RN DPF-19)
        StubURLProtocol.enqueue(.status(204)) // event d-fixture-1
        StubURLProtocol.enqueue(.status(204)) // event d-fixture-2

        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        runtime.onApnsToken(fixtureTokenBytes)
        drain(runtime.core)

        let registrations = requests(pathSuffix: "/devices")
        XCTAssertEqual(registrations.count, 1)
        XCTAssertEqual(registrations.first.map(jsonBody)?["token"] as? String, fixtureToken)
        XCTAssertEqual(runtime.core?.getDeviceId(), fixtureDeviceId)
        XCTAssertEqual(changedIds, [], "same id: no device-id change")
        let store = NottiDeviceStore(defaults: defaults)
        XCTAssertEqual(store.getAppVersion(), "1.0.0-fixture", "ack migration already done in RN 0.6.0: not cleared")
        XCTAssertEqual(store.getLastSyncedDeviceOs(), "17.0-fixture")
        // Only the RN held email/phone are re-sent (as RN does on every
        // registration), addressed to the RN device id. No profile-field PATCH.
        let patches = StubURLProtocol.recordedRequests().filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(Set(patches.compactMap { $0.url?.path }), ["/v1/apps/app-fixture/devices/device-fixture-id"])
        XCTAssertEqual(patches.map { jsonBody($0).keys.sorted() }, [["email", "token"], ["phone", "token"]])
        XCTAssertEqual(patches.first.map(jsonBody)?["email"] as? String, "user@example.invalid")
        XCTAssertEqual(patches.last.map(jsonBody)?["phone"] as? String, "fixture-phone")
        let deliveryIds = requests(pathSuffix: "/events").compactMap { jsonBody($0)["delivery_id"] as? String }
        XCTAssertEqual(deliveryIds, ["d-fixture-1", "d-fixture-2"])
    }
}
