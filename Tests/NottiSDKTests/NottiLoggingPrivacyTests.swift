import ObjectiveC
import UIKit
import UserNotifications
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

    /// CORE-12 at the registration-failure site (`NottiCore.registerDevice`, where
    /// the raw push token is in scope): a terminal 4xx on the device POST.
    func test_registrationTerminal4xxLogsNoSentinelValueAndFailsAtError() {
        runFlowWithFailedRegistration(responses: [.status(400)])

        let requests = StubURLProtocol.recordedRequests()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/devices") == true }.count, 1)
        assertRegistrationFailureLogged("Notti.initialize: device registration failed: HTTP 400")
        assertNoSentinelInLogs()
    }

    /// Same site, after the retry cap is exhausted on 5xx (non-terminal failure).
    func test_registrationExhausted5xxLogsNoSentinelValueAndFailsAtError() {
        runFlowWithFailedRegistration(responses: Array(repeating: .status(503), count: 5))

        let requests = StubURLProtocol.recordedRequests()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/devices") == true }.count, 5)
        assertRegistrationFailureLogged("Notti.initialize: device registration failed: HTTP 503")
        assertNoSentinelInLogs()
    }

    /// initialize -> login / setEmail / setPhone / addTags / country (all queued
    /// before registration) -> APNs token -> the device POST answers `responses`.
    /// Captured at `.verbose`.
    private func runFlowWithFailedRegistration(responses: [StubURLProtocol.StubResponse]) {
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

        runtime.start(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        let core = runtime.core
        core?.login(sentinelExternalId)
        core?.setEmail(sentinelEmail)
        core?.setPhone(sentinelPhone)
        core?.mutateTags(add: NottiRuntime.sanitizeTags(["segment": sentinelTagValue]), remove: nil)
        drain(core)

        for response in responses { StubURLProtocol.enqueue(response) }
        runtime.onApnsToken(tokenBytes)
        drain(core)
    }

    private func assertRegistrationFailureLogged(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let failures = captured.filter { $0.message.hasPrefix("Notti.initialize: device registration failed") }
        XCTAssertEqual(failures.map(\.message), [expected], file: file, line: line)
        XCTAssertEqual(failures.map(\.level), [.error], file: file, line: line)
    }

    private func assertNoSentinelInLogs(file: StaticString = #filePath, line: UInt = #line) {
        let sentinels = [
            sentinelEmail, sentinelPhone, sentinelExternalId, sentinelTagValue,
            tokenHex, tokenHex.uppercased(), sentinelCountry
        ]
        let lines = captured
        XCTAssertFalse(lines.isEmpty, "the sink captured nothing", file: file, line: line)
        for logLine in lines {
            for sentinel in sentinels {
                XCTAssertFalse(
                    logLine.message.contains(sentinel),
                    "PII sentinel '\(sentinel)' leaked in: \(logLine.message)",
                    file: file,
                    line: line
                )
            }
        }
    }

    // MARK: - Through the public facade (API-14, API-15)

    /// Every value the host passes to the SDK, plus the configuration fixtures,
    /// must stay out of the log (CORE-12 extended to the facade layer).
    private var facadeSentinels: [String] {
        [
            sentinelEmail, sentinelPhone, sentinelExternalId, sentinelTagValue,
            tokenHex, tokenHex.uppercased(), sentinelCountry,
            "app-fixture", "key-fixture", "notti.example.invalid",
            "sentinel-invalid-app", "sentinel-invalid-key", "sentinel-invalid-host"
        ]
    }

    private func assertNoFacadeSentinelInLogs(file: StaticString = #filePath, line: UInt = #line) {
        let lines = captured
        XCTAssertFalse(lines.isEmpty, "the sink captured nothing", file: file, line: line)
        for logLine in lines {
            for sentinel in facadeSentinels {
                XCTAssertFalse(
                    logLine.message.contains(sentinel),
                    "PII sentinel '\(sentinel)' leaked in: \(logLine.message)",
                    file: file,
                    line: line
                )
            }
        }
    }

    /// Drives only `NottiFacade` (what `Notti` forwards to): pre-initialize
    /// email/phone, invalid then valid initialize, login, tags, location, a
    /// notification event with live listeners, the APNs token and a permission
    /// request. Registration succeeds, every later request fails. At `.verbose`.
    func test_facadeFlowWithFailuresAtVerboseLogsNoSentinelValue() {
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
        let facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
        let handler = NottiNotificationHandler(runtime: runtime)
        let received = facade.addReceivedListener { _ in }
        let clicked = facade.addClickedListener { _ in }

        facade.setEmail(sentinelEmail)
        facade.setPhone(sentinelPhone)
        facade.login(sentinelExternalId) // dropped before initialize (warn)
        facade.initialize(appId: "sentinel-invalid-app", clientKey: "sentinel-invalid-key", baseUrl: "ftp://sentinel-invalid-host")
        facade.initialize(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        let core = runtime.core
        facade.login(sentinelExternalId)
        facade.addTags(["segment": sentinelTagValue])
        facade.setLocationSharingEnabled(true)
        handler.handleWillPresent(
            userInfo: ["aps": ["alert": "fixture"], "notification_id": "n-fixture", "delivery_id": "d-fixture"],
            identifier: "req-fixture"
        )
        drain(core)

        StubURLProtocol.enqueue(.status(200, body: #"{"id":"device-fixture","tags":{}}"#)) // registration only
        runtime.onApnsToken(tokenBytes)
        facade.requestPermission { _ in }
        drain(core)
        received.remove()
        clicked.remove()

        let requests = StubURLProtocol.recordedRequests()
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/devices") == true }.count, 1)
        XCTAssertGreaterThan(requests.filter { $0.httpMethod == "PATCH" }.count, 0)
        // The facade's own invalid-initialize line is part of what is swept.
        XCTAssertEqual(captured.filter { $0.message.hasPrefix("Notti.initialize ignored") }.map(\.level), [.error])
        assertNoFacadeSentinelInLogs()
    }

    /// Same facade-only flow when the registration itself fails (terminal 4xx).
    func test_facadeFlowWithFailedRegistrationAtVerboseLogsNoSentinelValue() {
        NottiLogger.level = .verbose
        let runtime = makeRuntime(providers: NottiPlatformProviders(
            tokenProvider: { _ in },
            permissionRequester: { $0(true) }
        ))
        let facade = NottiFacade(runtime: runtime, dispatcher: { $0() })

        facade.initialize(appId: "app-fixture", clientKey: "key-fixture", baseUrl: "https://notti.example.invalid")
        let core = runtime.core
        facade.login(sentinelExternalId)
        facade.setEmail(sentinelEmail)
        facade.setPhone(sentinelPhone)
        facade.addTags(["segment": sentinelTagValue])
        drain(core)
        StubURLProtocol.enqueue(.status(400))
        runtime.onApnsToken(tokenBytes)
        drain(core)

        assertRegistrationFailureLogged("Notti.initialize: device registration failed: HTTP 400")
        assertNoFacadeSentinelInLogs()
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

    // MARK: - Delegate integration (DEL-13)

    private final class FakeCenterHost: NottiNotificationCenterHost {
        weak var delegate: UNUserNotificationCenterDelegate?
    }

    private final class FakeHostDelegate: NSObject, UNUserNotificationCenterDelegate {}

    private let delegateUserInfo: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "sentinel-title", "body": "sentinel-body"]],
        "notification_id": "sentinel-notification-id",
        "delivery_id": "sentinel-delivery-id",
        "link": "https://sentinel-link.example.invalid/sentinel-data-value"
    ]
    private let delegateSilent: [AnyHashable: Any] = ["aps": ["content-available": 1], "delivery_id": "sentinel-delivery-id"]

    /// The installer with a non-Boolean key value: it warns, and the value itself must stay out of the line.
    /// The launch notification then makes it assign the fallback delegate to the fake center.
    private func exerciseInstaller(adapter: NottiPushAdapter) -> (NottiDelegateInstaller, FakeCenterHost) {
        let center = FakeCenterHost()
        let notifications = NotificationCenter()
        let installer = NottiDelegateInstaller(environment: NottiDelegateInstaller.Environment(
            configuration: {
                NottiSwizzlingConfiguration(infoDictionary: [NottiSwizzlingConfiguration.infoPlistKey: "sentinel-bad-value"])
            },
            applicationClass: DelegateFixtures.makeEmptyDelegateClass(),
            centerClass: DelegateFixtures.makeEmptyDelegateClass(),
            existingApplicationDelegate: { nil },
            center: center,
            notificationCenter: notifications,
            isLaunchFinished: { false },
            adapter: adapter,
            state: NottiSwizzlingState()
        ))
        installer.performInstall(fromLaunchHook: true)
        notifications.post(name: UIApplication.didFinishLaunchingNotification, object: nil)
        return (installer, center)
    }

    /// Swizzled UN delegate and app delegate callbacks, then the SwiftUI warning.
    private func exerciseSwizzledDelegates(adapter: NottiPushAdapter, method: NottiMethodSwizzler) {
        typealias Fixtures = DelegateFixtures
        let centerSwizzler = NottiNotificationCenterSwizzler(swizzler: method, adapter: adapter)
        let appSwizzler = NottiAppDelegateSwizzler(swizzler: method, adapter: adapter, isSwiftUIInternalDelegate: { _ in false })
        let unClass = Fixtures.makeEmptyDelegateClass()
        XCTAssertTrue(centerSwizzler.swizzle(delegateClass: unClass))
        let unDelegate = Fixtures.makeInstance(unClass)
        Fixtures.sendWillPresent(unDelegate, delegateUserInfo)
        Fixtures.sendDidReceive(unDelegate, delegateUserInfo)
        let appClass = Fixtures.makeEmptyDelegateClass()
        XCTAssertTrue(appSwizzler.swizzle(delegateClass: appClass))
        let appDelegate = Fixtures.makeInstance(appClass)
        Fixtures.sendToken(appDelegate, tokenBytes)
        Fixtures.sendFailure(
            appDelegate,
            NSError(domain: "fixture.apns", code: 3000, userInfo: [NSLocalizedDescriptionKey: "sentinel-error-description"])
        )
        Fixtures.sendFetch(appDelegate, delegateSilent)

        let swiftUISwizzler = NottiAppDelegateSwizzler(
            swizzler: NottiMethodSwizzler(),
            adapter: adapter,
            isSwiftUIInternalDelegate: { _ in true }
        )
        XCTAssertTrue(swiftUISwizzler.swizzle(delegateClass: Fixtures.makeEmptyDelegateClass()))
    }

    /// The fallback delegate, called directly.
    private func exerciseFallback(adapter: NottiPushAdapter) {
        let fallback = NottiNotificationCenterDelegate(adapter: adapter)
        let unusedCenter = unsafeDowncast(
            class_createInstance(UNUserNotificationCenter.self, 0) as AnyObject,
            to: UNUserNotificationCenter.self
        )
        fallback.userNotificationCenter(unusedCenter, willPresent: DelegateFixtures.notification(userInfo: delegateUserInfo)) { _ in }
        fallback.userNotificationCenter(unusedCenter, didReceive: DelegateFixtures.response(userInfo: delegateUserInfo)) {}
    }

    /// Every delegate path at `.verbose` with values that must never be logged: the token, title, body, a `data`
    /// value, both ids and an error description. Covers the installer (invalid key value), the swizzlers, the
    /// fallback delegate, the silent path, the SwiftUI warning, the install-failure line and the manual guard.
    func test_delegatePathsAtVerboseLogNoSentinelValue() {
        NottiLogger.level = .verbose
        let runtime = makeRuntime(
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) })
        )
        var swizzlingActive = false
        let adapter = NottiPushAdapter(runtime: runtime, isSwizzlingActive: { swizzlingActive })
        let method = NottiMethodSwizzler()

        let (installer, _) = exerciseInstaller(adapter: adapter)
        exerciseSwizzledDelegates(adapter: adapter, method: method)
        exerciseFallback(adapter: adapter)
        // The install-failure line: an absent selector with no type encoding cannot be added.
        let absent = NSSelectorFromString("absent:")
        XCTAssertFalse(method.swizzle(DelegateFixtures.makeEmptyDelegateClass(), absent, typeEncoding: "") { _ in 0 })

        // Manual guard while swizzling is active: one warning per call.
        swizzlingActive = true
        adapter.manualDidRegister(deviceToken: tokenBytes)
        adapter.manualDidFail(
            error: NSError(domain: "fixture.apns", code: 1, userInfo: [NSLocalizedDescriptionKey: "sentinel-error-description"])
        )
        _ = adapter.manualWillPresent(userInfo: delegateUserInfo, identifier: "sentinel-request-id")
        adapter.manualDidReceive(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: delegateUserInfo,
            identifier: "sentinel-request-id"
        )
        _ = adapter.manualDidReceiveRemoteNotification(userInfo: delegateSilent)

        let lines = captured
        XCTAssertGreaterThanOrEqual(lines.filter { $0.level == .warn }.count, 7, "installer, SwiftUI and five manual-guard warnings")
        XCTAssertTrue(lines.contains { $0.level == .error && $0.message.contains("fixture.apns#3000") })
        XCTAssertTrue(lines.contains { $0.level == .error && $0.message.contains("could not install delegate hook") })
        let sentinels = ["sentinel", tokenHex, tokenHex.uppercased(), "Hello", "Title", "Body", "n-1", "d-1", "example.invalid"]
        for logLine in lines {
            for sentinel in sentinels {
                XCTAssertFalse(logLine.message.contains(sentinel), "sentinel '\(sentinel)' leaked in: \(logLine.message)")
            }
        }
        withExtendedLifetime(installer) {}
    }
}
