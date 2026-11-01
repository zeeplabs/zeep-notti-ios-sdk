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

    /// Empty defaults keep the profile PATCHes of the other tests out of the way;
    /// the wrapper tests pass native-like values.
    private func makeRuntime(sdkVersion: String = "", sdkName: String = "") -> NottiRuntime {
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
            sdkVersion: sdkVersion,
            sdkName: sdkName,
            startObservers: false
        )
    }

    /// Replaces the setUp runtime (never started) with one carrying native values.
    private func useNativeRuntime() {
        runtime = makeRuntime(sdkVersion: "0.2.0-native-fixture", sdkName: "ios")
        facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
    }

    private var patches: [[String: Any]] {
        StubURLProtocol.recordedRequests().filter { $0.httpMethod == "PATCH" }.map { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
        }
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

    // MARK: - Wrapper sdk_name / sdk_version (wrapper-support WRAP-01..03, 06, 16..18; AD-024)

    func test_wrapperSdkNameAndVersionReachTheProfileInsteadOfTheNativeOnes() {
        useNativeRuntime()
        enqueueRegistrations(3)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "react-native", sdkVersion: "0.9.0")
        drain()

        XCTAssertEqual(patches.compactMap { $0["sdk_version"] as? String }, ["0.9.0"])
        XCTAssertEqual(patches.compactMap { $0["sdk_name"] as? String }, ["react-native"])
    }

    func test_emptyWrapperValuesOmitTheFields() {
        useNativeRuntime()
        enqueueRegistrations(1)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "", sdkVersion: "")
        drain()

        XCTAssertEqual(registrations.count, 1)
        XCTAssertTrue(patches.allSatisfy { $0["sdk_version"] == nil && $0["sdk_name"] == nil })
    }

    func test_publicInitializeSendsTheNativeNameAndVersion() {
        useNativeRuntime()
        enqueueRegistrations(3)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()

        XCTAssertEqual(patches.compactMap { $0["sdk_version"] as? String }, ["0.2.0-native-fixture"])
        XCTAssertEqual(patches.compactMap { $0["sdk_name"] as? String }, ["ios"])
    }

    func test_aDifferentWrapperSdkVersionOrNameRestartsTheCore_theSameValuesDoNot() {
        // Three registrations plus the profile PATCHes each core sends (both
        // fields first, then only the one that changed): 7 echoes.
        enqueueRegistrations(7)

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "react-native", sdkVersion: "0.9.0")
        drain()
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "react-native", sdkVersion: "0.9.0")
        drain()
        XCTAssertEqual(registrations.count, 1, "same wrapper values are a no-op")

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "react-native", sdkVersion: "0.9.1")
        drain()
        XCTAssertEqual(registrations.count, 2, "a different sdkVersion restarts the core")
        XCTAssertEqual(facade.activeConfig?.sdkVersion, "0.9.1")

        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl, sdkName: "flutter", sdkVersion: "0.9.1")
        drain()
        XCTAssertEqual(registrations.count, 3, "a different sdkName restarts the core")
        XCTAssertEqual(facade.activeConfig?.sdkName, "flutter")
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
