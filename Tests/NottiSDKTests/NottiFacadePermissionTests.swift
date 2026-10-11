import XCTest
@testable import NottiSDK
@testable import NottiShared

final class NottiFacadePermissionTests: XCTestCase {

    private let appId = "app-fixture"
    private let clientKey = "key-fixture"
    private let baseUrl = "https://notti.example.invalid"

    /// Queues blocks instead of running them, so a test controls when "main" runs.
    private final class RecordingDispatcher {
        private let lock = NSLock()
        private var queue: [() -> Void] = []
        var pending: Int { lock.withLock { queue.count } }
        func dispatch(_ block: @escaping () -> Void) { lock.withLock { queue.append(block) } }
        func drain() {
            while true {
                let next: (() -> Void)? = lock.withLock { queue.isEmpty ? nil : queue.removeFirst() }
                guard let block = next else { return }
                block()
            }
        }
    }

    private final class Results {
        private let lock = NSLock()
        private var items: [Bool] = []
        func append(_ value: Bool) { lock.withLock { items.append(value) } }
        var values: [Bool] { lock.withLock { items } }
    }

    private final class RequesterProbe {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.withLock { _calls } }
        func record() { lock.withLock { _calls += 1 } }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var facade: NottiFacade!
    private var dispatcher: RecordingDispatcher!
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiFacadePermissionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        dispatcher = RecordingDispatcher()
    }

    override func tearDown() {
        let core = runtime?.core
        runtime?.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        facade = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    /// - Parameter inlineDispatch: run main-thread hops inline (for `async` tests).
    private func makeFacade(
        inlineDispatch: Bool = false,
        requester: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { $0("apns-token-fixture") }, permissionRequester: requester),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        let recording = dispatcher!
        facade = NottiFacade(
            runtime: runtime,
            dispatcher: inlineDispatch ? { $0() } : { recording.dispatch($0) }
        )
    }

    private func initializeFacade() {
        for _ in 0..<4 { StubURLProtocol.enqueue(.echoDevice()) }
        facade.initialize(appId: appId, clientKey: clientKey, baseUrl: baseUrl)
        drain()
    }

    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        guard let core = runtime.core else { return }
        XCTAssertTrue(core.waitForPendingWork(timeout: 25), "core work queue did not drain", file: file, line: line)
    }

    // MARK: - Tests

    func test_grantedAndDeniedOsResultsComeBackThroughTheDispatcher() {
        for answer in [true, false] {
            let results = Results()
            makeFacade { $0(answer) }
            initializeFacade()

            facade.requestPermission { results.append($0) }
            drain()

            XCTAssertEqual(results.values, [], "not delivered until the dispatcher runs")
            XCTAssertEqual(dispatcher.pending, 1)
            dispatcher.drain()
            XCTAssertEqual(results.values, [answer])

            let core = runtime.core
            runtime.stop()
            core?.waitForPendingWork(timeout: 20)
            StubURLProtocol.reset()
        }
    }

    func test_beforeInitializeTheResultIsFalseAndTheRequesterIsNeverCalled() {
        let probe = RequesterProbe()
        let results = Results()
        makeFacade {
            probe.record()
            $0(true)
        }

        facade.requestPermission { results.append($0) }
        drain()
        dispatcher.drain()

        XCTAssertEqual(results.values, [false])
        XCTAssertEqual(probe.calls, 0)
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }

    func test_aCallbackInvokedTwiceDeliversTheCompletionOnce() {
        let results = Results()
        makeFacade {
            $0(true)
            $0(false)
        }
        initializeFacade()

        facade.requestPermission { results.append($0) }
        drain()
        dispatcher.drain()

        XCTAssertEqual(results.values, [true])
    }

    func test_theAsyncVariantSurvivesACallbackInvokedTwice() async {
        makeFacade(inlineDispatch: true) {
            $0(true)
            $0(false)
        }
        initializeFacade()

        let granted = await facade.requestPermission()

        XCTAssertTrue(granted)
        drain()
    }

    func test_theAsyncVariantReturnsTheOsResultAndFalseBeforeInitialize() async {
        let probe = RequesterProbe()
        makeFacade(inlineDispatch: true) {
            probe.record()
            $0(true)
        }

        let before = await facade.requestPermission()
        XCTAssertFalse(before)
        XCTAssertEqual(probe.calls, 0)

        initializeFacade()
        let after = await facade.requestPermission()
        XCTAssertTrue(after)
        XCTAssertEqual(probe.calls, 1)
        drain()
    }

    func test_twoConcurrentRequestsBothComplete() async {
        makeFacade(inlineDispatch: true) { callback in
            DispatchQueue.global().async { callback(true) }
        }
        initializeFacade()

        async let first = facade.requestPermission()
        async let second = facade.requestPermission()
        let both = await [first, second]

        XCTAssertEqual(both, [true, true])
        drain()
    }
}
