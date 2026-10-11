import UIKit
import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiFacadeInitializeTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var sessions: [URLSession] = []
    private let logs = LogSink()
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiFacadeInitializeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        NottiLogger.sink = { [logs] level, message in logs.append("\(level):\(message)") }
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
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
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

    private func enqueueRegistrations(_ count: Int) {
        for _ in 0..<count { StubURLProtocol.enqueue(.echoDevice()) }
    }

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    private var registrations: [URLRequest] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "POST" }
    }

    private var errorLogs: [String] {
        logs.messages.filter { $0.hasPrefix("error:") }
    }

    private func assertIgnored(
        appId: String,
        clientKey: String,
        baseUrl: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = registrations.count
        let configBefore = facade.activeConfig
        let errorsBefore = errorLogs.count

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain(file: file, line: line)

        XCTAssertEqual(registrations.count, before, "no registration", file: file, line: line)
        XCTAssertEqual(facade.activeConfig, configBefore, "config unchanged", file: file, line: line)
        let newErrors = Array(errorLogs.dropFirst(errorsBefore))
        XCTAssertEqual(newErrors.count, 1, "exactly one .error line", file: file, line: line)
        for message in newErrors {
            for secret in [appId, clientKey, baseUrl ?? ""] where !secret.isEmpty {
                XCTAssertFalse(message.contains(secret), "the log never carries an argument value", file: file, line: line)
            }
        }
    }

    // MARK: - API-01 / API-02

    func test_firstInitializeRegistersOnce_theSameValuesAgainDoNot_aDifferentAppIdDoes() {
        enqueueRegistrations(3)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, 1)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, 1, "identical initialize is a no-op (N1)")

        facade.initialize(appId: "other-app-fixture", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, 2, "a different appId rebuilds the core")
    }

    func test_aDifferentClientKeyOrBaseUrlAlsoRebuildsTheCore() {
        enqueueRegistrations(3)
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()

        facade.initialize(appId: appId, clientKey: "other-key-fixture", baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, 2)

        facade.initialize(appId: appId, clientKey: "other-key-fixture", baseUrl: "https://other.example.invalid")
        drain()
        XCTAssertEqual(registrations.count, 3)
    }

    func test_valuesThatAreEqualAfterNormalizationCountAsTheSame() {
        enqueueRegistrations(2)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: "https://x.example.invalid/")
        drain()
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: "https://x.example.invalid")
        drain()
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: "  https://x.example.invalid//  ")
        drain()

        XCTAssertEqual(registrations.count, 1)
        XCTAssertEqual(facade.activeConfig?.baseUrl, "https://x.example.invalid")
    }

    func test_invalidArgumentsAreLoggedWithoutValuesAndLeaveTheRunningCoreInPlace() {
        enqueueRegistrations(1)
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
        let running = runtime.core
        let expected = NottiFacade.Config(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        XCTAssertEqual(facade.activeConfig, expected)

        assertIgnored(appId: "", clientKey: clientKey, baseUrl: baseUrl)
        assertIgnored(appId: appId, clientKey: "", baseUrl: baseUrl)
        assertIgnored(appId: appId, clientKey: clientKey, baseUrl: "push.secret-host.example.invalid")
        assertIgnored(appId: appId, clientKey: clientKey, baseUrl: "")
        XCTAssertTrue(runtime.core === running, "the running core was never replaced")
        XCTAssertEqual(facade.activeConfig, expected)
    }

    func test_invalidArgumentsOnAnUninitializedSdkLeaveItUninitialized() {
        assertIgnored(appId: "", clientKey: clientKey, baseUrl: baseUrl)

        XCTAssertNil(facade.activeConfig)
        XCTAssertNil(runtime.core)
    }

    func test_plainHttpFollowsTheBuildRule() {
        let httpUrl = "http://insecure.example.invalid"
        #if DEBUG
            // Debug builds accept `http` for local servers (NottiApiClient A5).
            enqueueRegistrations(1)
            facade.initialize(appId: appId, clientKey: clientKey, baseUrl: httpUrl)
            drain()
            XCTAssertEqual(registrations.count, 1)
        #else
            assertIgnored(appId: appId, clientKey: clientKey, baseUrl: httpUrl)
        #endif
    }

    func test_aNilBaseUrlSendsTheRequestToTheDefaultHost() {
        enqueueRegistrations(1)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: nil)
        drain()

        let url = registrations.first?.url
        XCTAssertEqual(url?.host, "app.zeepnotti.app")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(NottiFacade.defaultBaseUrl, "https://app.zeepnotti.app")
        XCTAssertEqual(facade.activeConfig?.baseUrl, "https://app.zeepnotti.app")
    }

    func test_twoRacingDifferentInitializesEndWithOneConsistentCore() {
        enqueueRegistrations(8)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "init-race", attributes: .concurrent)
        for name in ["race-a-fixture", "race-b-fixture"] {
            group.enter()
            queue.async { [facade = self.facade!, clientKey, baseUrl] in
                facade.initialize(appId: name, clientKey: clientKey, baseUrl: baseUrl)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
        drain()

        let winner = facade.activeConfig
        XCTAssertTrue(["race-a-fixture", "race-b-fixture"].contains(winner?.appId ?? ""))
        XCTAssertNotNil(runtime.core)
        // Consistent state: repeating the winner is a no-op, switching is one start.
        let before = registrations.count
        facade.initialize(appId: winner?.appId ?? "", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, before)
        facade.initialize(appId: "race-c-fixture", clientKey: clientKey, baseUrl: baseUrl)
        drain()
        XCTAssertEqual(registrations.count, before + 1)
    }

    func test_initializeNeverLogsTheConfigurationValues() {
        enqueueRegistrations(1)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()

        for message in logs.messages {
            for secret in [appId, clientKey, "notti.example.invalid"] {
                XCTAssertFalse(message.contains(secret), message)
            }
        }
    }
}
