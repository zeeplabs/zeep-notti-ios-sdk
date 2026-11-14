#if os(macOS)
import AppKit
import XCTest
@testable import NottiSDK

/// AD-025, macOS lifecycle: the `NottiCore` observers (posted with the AppKit names, not the test shim), the
/// session end on terminate with its bounded wait (design D7, unconfirmed), the background activity wrapper and the
/// device info reads. A test fails when `observeAppForeground` or `observeAppBackground` register nothing (design C2).
final class NottiCoreTerminateTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: NottiDeviceStore!
    private var sessions: [URLSession] = []
    private var cores: [NottiCore] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiCoreTerminateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = NottiDeviceStore(defaults: defaults)
    }

    override func tearDown() {
        for core in cores { core.waitForPendingWork(timeout: 20) }
        cores.removeAll()
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func newCore(
        appStateProvider: @escaping (@escaping (Bool) -> Void) -> Void = { $0(false) },
        beginBackgroundTask: @escaping () -> (() -> Void) = { {} },
        apiClient: NottiApiClient? = nil,
        gate: NottiCore.SessionGate = NottiCore.SessionGate()
    ) -> NottiCore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        let core = NottiCore(
            deviceStore: store,
            eventStore: NottiEventStore(defaults: defaults),
            apiClientFactory: { appId, clientKey, baseUrl in
                apiClient ?? NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            tokenProvider: { $0("apns-token") },
            permissionRequester: { $0(true) },
            appStateProvider: appStateProvider,
            beginBackgroundTask: beginBackgroundTask,
            sessionGate: gate
        )
        cores.append(core)
        return core
    }

    private func drain(_ core: NottiCore) {
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain")
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    // MARK: - Observers (the AppKit names reach the same core paths)

    func test_becomingActiveStartsASession() {
        let core = newCore()
        drain(core)
        XCTAssertNil(store.getSessionStartedAtMs())

        post(NSApplication.didBecomeActiveNotification)
        drain(core)

        XCTAssertNotNil(store.getSessionStartedAtMs(), "an observer on didBecomeActive is registered")
    }

    func test_resigningActiveEndsTheSession() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)
        XCTAssertNotNil(store.getSessionStartedAtMs())

        post(NSApplication.didResignActiveNotification)
        drain(core)

        XCTAssertNil(store.getSessionStartedAtMs(), "an observer on the macOS didEnterBackground name is registered")
        XCTAssertEqual(store.getSessionCount(), 1)
    }

    func test_aLaterActivationOpensANewSessionAfterResigning() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)

        post(NSApplication.didResignActiveNotification)
        drain(core)
        post(NSApplication.didBecomeActiveNotification)
        drain(core)

        XCTAssertNotNil(store.getSessionStartedAtMs())
        XCTAssertEqual(store.getSessionCount(), 1)
    }

    // MARK: - Terminate (D7)

    func test_theBackgroundNameOfThisPlatformIsResignActiveAndTerminateIsDistinct() {
        XCTAssertEqual(NottiLifecycle.didEnterBackground, NSApplication.didResignActiveNotification)
        XCTAssertNotEqual(NottiLifecycle.willTerminate, NottiLifecycle.didEnterBackground)
    }

    func test_terminateEndsAnOpenSessionOnce() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)
        XCTAssertNotNil(store.getSessionStartedAtMs())

        post(NSApplication.willTerminateNotification)
        drain(core)

        XCTAssertNil(store.getSessionStartedAtMs())
        XCTAssertEqual(store.getSessionCount(), 1, "the quit while active ended the session once")
    }

    func test_resignThenTerminateIsASingleSessionEnd() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)

        post(NSApplication.didResignActiveNotification)
        drain(core)
        post(NSApplication.willTerminateNotification)
        drain(core)

        XCTAssertEqual(store.getSessionCount(), 1, "the second end is a no-op: no stored session start")
    }

    func test_terminateWithNoOpenSessionChangesNothing() {
        let core = newCore()
        drain(core)

        post(NSApplication.willTerminateNotification)
        drain(core)

        XCTAssertEqual(store.getSessionCount(), 0)
        XCTAssertNil(store.getSessionStartedAtMs())
    }

    func test_anInvalidatedCoreIgnoresTerminate() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)
        let startedAt = store.getSessionStartedAtMs()

        core.invalidate()
        post(NSApplication.willTerminateNotification)
        drain(core)

        XCTAssertEqual(store.getSessionCount(), 0, "the terminate observer is removed with the others")
        XCTAssertEqual(store.getSessionStartedAtMs(), startedAt)
    }

    func test_theFlushWaitIsBoundedByTheInjectedTimeoutWhileTheQueueIsBlocked() {
        let probe = ThreadProbeApiClient(blockForSeconds: 1.5)
        let core = newCore(apiClient: probe)
        post(NSApplication.didBecomeActiveNotification)
        drain(core)
        core.initialize(appId: "app-1", clientKey: "key", baseUrl: "https://notti.example.invalid") // blocks the queue 1.5 s
        let deadline = Date().addingTimeInterval(10)
        while probe.callCount == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertGreaterThan(probe.callCount, 0, "the queue is busy")

        let started = Date()
        core.handleAppWillTerminate(atMs: core.nowMs(), flushTimeout: 0.2)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThanOrEqual(elapsed, 0.15, "it waited for the timeout, not zero")
        XCTAssertLessThan(elapsed, 1.0, "it returned on the timeout, not when the 1.5 s block ended")
        drain(core)
        XCTAssertEqual(store.getSessionCount(), 1, "the end still completes on the queue after the timeout")
    }

    func test_theFlushReturnsAtOnceWhenTheQueueIsFree() {
        let core = newCore(appStateProvider: { $0(true) })
        drain(core)

        let started = Date()
        core.handleAppWillTerminate(atMs: core.nowMs(), flushTimeout: 5)

        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "no fixed sleep: the wait ends when the work ran")
        XCTAssertEqual(store.getSessionCount(), 1)
    }

    func test_theTerminateFlushConstantIsOnePointFiveSeconds() {
        // Pins design D7 (UNCONFIRMED by the owner): change the constant and this test together.
        XCTAssertEqual(NottiCore.terminateFlushTimeout, 1.5)
    }

    func test_terminateRunsUnderTheBackgroundActivityAndEndsItOnce() {
        var begun = 0
        var ended = 0
        let core = newCore(appStateProvider: { $0(true) }, beginBackgroundTask: { begun += 1; return { ended += 1 } })
        drain(core)

        post(NSApplication.willTerminateNotification)
        drain(core)

        XCTAssertEqual(begun, 1)
        XCTAssertEqual(ended, 1)
    }

    // MARK: - Background activity (the macOS wrapper)

    private final class RecordingProcessInfo: ProcessInfo {
        private let lock = NSLock()
        private(set) var begun: [(ActivityOptions, String)] = []
        private(set) var ended = 0

        override func beginActivity(options: ProcessInfo.ActivityOptions = [], reason: String) -> NSObjectProtocol {
            lock.withLock { begun.append((options, reason)) }
            return NSObject()
        }

        override func endActivity(_ activity: NSObjectProtocol) {
            lock.withLock { ended += 1 }
        }
    }

    func test_theActivityIsBegunOnceWithTheTerminationOptionsAndEndedOnce() {
        let info = RecordingProcessInfo()

        let end = NottiBackgroundTask.begin(processInfo: info)
        XCTAssertEqual(info.begun.count, 1)
        XCTAssertTrue(info.begun[0].0.contains(.suddenTerminationDisabled))
        XCTAssertTrue(info.begun[0].0.contains(.automaticTerminationDisabled))
        XCTAssertEqual(info.begun[0].1, "app.notti.session-end")
        XCTAssertEqual(info.ended, 0)

        end()
        XCTAssertEqual(info.ended, 1)
    }

    func test_endingTheActivityIsIdempotent() {
        let info = RecordingProcessInfo()
        let end = NottiBackgroundTask.begin(processInfo: info)

        end()
        end()
        end()

        XCTAssertEqual(info.ended, 1)
    }

    func test_theProductionBeginAndEndDoNotCrash() {
        let end = NottiBackgroundTask.begin()
        end()
        end()
    }

    // MARK: - Device info (MAC-17)

    func test_theDeviceModelIsTheHardwareIdentifierNotTheArchitecture() throws {
        let model = try XCTUnwrap(NottiPlatformInfo.deviceModel(), "hw.model is readable on a Mac")
        XCTAssertNotEqual(model, "arm64")
        XCTAssertNotEqual(model, "x86_64")
        XCTAssertEqual(model, NottiPlatformInfo.sysctlString("hw.model"))
        XCTAssertNotNil(model.range(of: #"^[A-Za-z]+\d+,\d+$"#, options: .regularExpression), "shape of Mac14,9")
        XCTAssertEqual(model, model.trimmingCharacters(in: .controlCharacters))
    }

    func test_theDeviceOsIsTheProcessInfoVersionWithoutAZeroPatch() throws {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let expected = version.patchVersion == 0
            ? "\(version.majorVersion).\(version.minorVersion)"
            : "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        XCTAssertEqual(NottiPlatformInfo.deviceOS(), expected)
    }

    func test_aFailedModelReadIsNilThroughAnInjectedReader() {
        XCTAssertNil(NottiPlatformInfo.sysctlString("hw.model") { _, _, _ in -1 })
    }

    func test_theLiveProvidersReadTheMacValues() {
        let providers = NottiPlatformProviders.live()
        XCTAssertEqual(providers.deviceOsProvider(), NottiPlatformInfo.deviceOS())
        XCTAssertEqual(providers.deviceModelProvider(), NottiPlatformInfo.deviceModel())
        XCTAssertFalse(NottiPlatformInfo.supportsInApp)
    }
}
#endif
