import XCTest
@testable import NottiSDK
@testable import NottiShared

/// CORE-12 / CORE-13: no PII value ever reaches a log line, and the default
/// level emits errors only.
final class NottiLoggingPrivacyTests: XCTestCase {

    private let sentinelEmail = "sentinel-email@example.invalid"
    private let sentinelPhone = "+1555sentinel0199"
    private let sentinelExternalId = "sentinel-external-user-id"
    private let sentinelTagValue = "sentinel-tag-value"
    private let sentinelCountry = "XQ"
    /// APNs token bytes; their hex form is the token sentinel.
    private let tokenBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x5E, 0x47, 0x1E, 0x10])
    private let tokenHex = "deadbeef5e471e10"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtimes: [NottiRuntime] = []
    private var sessions: [URLSession] = []
    private let logLock = NSLock()
    private var logs: [(level: NottiLogLevel, message: String)] = []
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiLoggingPrivacyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        logs = []
        NottiLogger.sink = { [weak self] level, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append((level, message)) }
        }
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
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var captured: [(level: NottiLogLevel, message: String)] {
        logLock.withLock { logs }
    }

    private func makeRuntime(providers: NottiPlatformProviders) -> NottiRuntime {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let runtime = NottiRuntime(
            defaults: defaults,
            providers: providers,
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            startObservers: false
        )
        runtimes.append(runtime)
        return runtime
    }

    private func drain(_ core: NottiCore?, file: StaticString = #filePath, line: UInt = #line) {
        guard let core else {
            XCTFail("no core", file: file, line: line)
            return
        }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    /// initialize -> login / setEmail / setPhone / addTags (queued before
    /// registration) -> notification event -> APNs token -> registration ->
    /// every later request fails (no stub queued: network error, retried, then
    /// given up). Location sharing is on, so the country is read and its PATCH
    /// fails too. Captured at `.verbose`.
    func test_fullFlowWithFailuresAtVerboseLogsNoSentinelValue() {
        NottiLogger.level = .verbose
        NottiDeviceStore(defaults: defaults).setLocationSharingEnabled(true)
        let country = sentinelCountry
        let runtime = makeRuntime(providers: NottiPlatformProviders(
            tokenProvider: { _ in },
            permissionRequester: { $0(true) },
            hasLocationPermission: { true },
            countryProvider: { $0(country) },
            appStateProvider: { $0(true) }
        ))
        let handler = NottiNotificationHandler(runtime: runtime)

        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        let core = runtime.core
        core?.login(sentinelExternalId)
        core?.setEmail(sentinelEmail)
        core?.setPhone(sentinelPhone)
        core?.mutateTags(add: NottiRuntime.sanitizeTags(["segment": sentinelTagValue]), remove: nil)
        handler.handleWillPresent(
            userInfo: ["aps": ["alert": "fixture"], "notification_id": "n-fixture", "delivery_id": "d-fixture"],
            identifier: "req-fixture"
        )
        drain(core)

        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture","tags":{}}"#)) // registration only
        runtime.onApnsToken(tokenBytes)
        drain(core)

        // The flow really ran: registration plus failed PATCH / event attempts.
        let requests = StubURLProtocol.recordedRequests()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/devices") == true }.count, 1)
        XCTAssertGreaterThan(requests.filter { $0.httpMethod == "PATCH" }.count, 0)
        XCTAssertGreaterThan(requests.filter { $0.url?.path.hasSuffix("/events") == true }.count, 0)

        let lines = captured
        // The sink is wired: each level the core uses shows up at least once.
        XCTAssertTrue(lines.contains { $0.level == .error })
        XCTAssertTrue(lines.contains { $0.level == .warn })
        XCTAssertTrue(lines.contains { $0.level == .debug })
        // One call site per level keeps its assigned level (core-port T7 levels).
        XCTAssertEqual(lines.first { $0.message.hasPrefix("Notti.login: PATCH failed") }?.level, .error)
        XCTAssertEqual(lines.first { $0.message.contains("event stays queued") }?.level, .warn)
        XCTAssertEqual(lines.first { $0.message.contains("queued login until registration completes") }?.level, .debug)

        let sentinels = [
            sentinelEmail, sentinelPhone, sentinelExternalId, sentinelTagValue,
            tokenHex, tokenHex.uppercased(), sentinelCountry
        ]
        for line in lines {
            for sentinel in sentinels {
                XCTAssertFalse(line.message.contains(sentinel), "PII sentinel '\(sentinel)' leaked in: \(line.message)")
            }
        }
    }

    /// CORE-13: at the default level only errors reach the sink, even when the
    /// flow produces warnings and debug lines.
    func test_defaultLevelIsErrorAndNothingBelowItIsEmitted() {
        XCTAssertEqual(NottiLogger.defaultLevel, .error)
        NottiLogger.level = NottiLogger.defaultLevel
        let runtime = makeRuntime(providers: NottiPlatformProviders(
            tokenProvider: { $0(nil) },
            permissionRequester: { $0(true) }
        ))

        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid") // .warn: no token
        runtime.core?.login(sentinelExternalId) // .debug: queued until registration
        drain(runtime.core)
        runtime.onApnsRegistrationFailed(NSError(domain: "fixture.apns", code: 3000)) // .error

        XCTAssertEqual(captured.map(\.level), [.error])
        XCTAssertEqual(captured.map(\.message), ["Notti: failed to register for remote notifications - fixture.apns#3000"])
    }
}
