import UIKit
import UserNotifications
import XCTest
@testable import NottiSDK
@testable import NottiShared

/// DEL-10, DEL-18: a tapped push's `data` (including a link) reaches the host byte for byte, warm and cold,
/// is reported as one `opened` and one `clicked`, and the SDK opens no URL. Every test goes through the real
/// `NottiNotificationCenterSwizzler` / `NottiAppDelegateSwizzler` over fake classes. The opener spy is passed
/// as the `application` / `center` argument of the callbacks; `scripts/check-no-url-open.sh` covers the source.
final class NottiDeepLinkTests: XCTestCase {

    private typealias Fixtures = DelegateFixtures

    private let link = "https://example.invalid/fixture"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var runtime: NottiRuntime!
    private var adapter: NottiPushAdapter!
    private var facade: NottiFacade!
    private var swizzler: NottiMethodSwizzler!
    private var center: NottiNotificationCenterSwizzler!
    private var app: NottiAppDelegateSwizzler!
    private var sessions: [URLSession] = []
    private let spy = DelegateFixtures.OpenSpy()
    private let logLock = NSLock()
    private var logs: [String] = []
    private var savedLevel: NottiLogLevel = .error

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        suiteName = "NottiDeepLinkTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedLevel = NottiLogger.level
        NottiLogger.level = .verbose
        logs = []
        NottiLogger.sink = { [weak self] _, message in
            guard let self else { return }
            self.logLock.withLock { self.logs.append(message) }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        sessions.append(session)
        runtime = NottiRuntime(
            defaults: defaults,
            providers: NottiPlatformProviders(tokenProvider: { _ in }, permissionRequester: { $0(true) }),
            pathMonitor: FakePathMonitor(),
            apiClientFactory: { appId, clientKey, baseUrl in
                NottiApiClient(session: session, baseUrl: baseUrl, appId: appId, clientKey: clientKey, sleeper: { _ in })
            },
            sdkVersion: "",
            startObservers: false
        )
        adapter = NottiPushAdapter(runtime: runtime)
        facade = NottiFacade(runtime: runtime, dispatcher: { $0() })
        swizzler = NottiMethodSwizzler()
        center = NottiNotificationCenterSwizzler(swizzler: swizzler, adapter: adapter)
        app = NottiAppDelegateSwizzler(swizzler: swizzler, adapter: adapter, isSwiftUIInternalDelegate: { _ in false })
    }

    override func tearDown() {
        let core = runtime.core
        runtime.stop()
        core?.waitForPendingWork(timeout: 20)
        runtime = nil
        for session in sessions { session.invalidateAndCancel() }
        sessions.removeAll()
        NottiLogger.sink = nil
        NottiLogger.level = savedLevel
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func userInfo(linkKey: String = "link", linkValue: String? = nil) -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title": "Title fixture", "body": "Body fixture"]],
            "notification_id": "n-1",
            "delivery_id": "d-1",
            linkKey: linkValue ?? link
        ]
    }

    /// A swizzled UN delegate instance, as the host's delegate would be after `setDelegate:`.
    private func makeSwizzledDelegate() -> AnyObject {
        let cls = Fixtures.makeEmptyDelegateClass()
        XCTAssertTrue(center.swizzle(delegateClass: cls))
        return Fixtures.makeInstance(cls)
    }

    private var storedTypes: [String] { runtime.eventStore.all().map(\.type) }

    private var capturedLogs: [String] { logLock.withLock { logs } }

    // MARK: - Warm

    func test_aWarmTapReturnsTheLinkByteForByteThroughTheClickedListener() {
        var clicked: [NottiNotificationPayload] = []
        let subscription = facade.addClickedListener { clicked.append($0) }
        let delegate = makeSwizzledDelegate()

        let completions = Fixtures.sendDidReceive(delegate, userInfo(), center: spy)

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(clicked.count, 1)
        XCTAssertEqual(clicked.first?.data["link"], link)
        XCTAssertEqual(clicked.first?.data["link"]?.utf8.elementsEqual(link.utf8), true)
        XCTAssertNil(facade.takeInitialClick(), "a delivered click is not replayed as the launch click")
        subscription.remove()
    }

    func test_aWarmTapQueuesExactlyOneOpenedAndOneClickedAndOpensNoURL() {
        let delegate = makeSwizzledDelegate()

        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)

        XCTAssertEqual(storedTypes, ["opened", "clicked"])
        XCTAssertEqual(spy.calls, [], "the SDK never opens a URL")
    }

    func test_theLinkSurvivesAnyHostChosenKeyAndAnyCharacters() {
        let tricky = "myapp://path/é?q=a b&r=%E2%9C%93#frag"
        var clicked: [NottiNotificationPayload] = []
        let subscription = facade.addClickedListener { clicked.append($0) }
        let delegate = makeSwizzledDelegate()

        Fixtures.sendDidReceive(delegate, userInfo(linkKey: "deep_link", linkValue: tricky), center: spy)

        XCTAssertEqual(clicked.first?.data["deep_link"], tricky)
        XCTAssertEqual(spy.calls, [])
        subscription.remove()
    }

    // MARK: - Cold start

    func test_aColdStartTapWithNoCoreReturnsTheLinkOnceThroughTakeInitialClick() {
        XCTAssertNil(runtime.core)
        let delegate = makeSwizzledDelegate()

        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)

        let click = facade.takeInitialClick()
        XCTAssertEqual(click?.data["link"], link)
        XCTAssertEqual(click?.title, "Title fixture")
        XCTAssertNil(facade.takeInitialClick(), "once")
        XCTAssertNil(facade.takeInitialClick())
        XCTAssertEqual(spy.calls, [])
    }

    func test_aColdStartTapKeepsTheQueuedReportsInTheStoreWithNoCore() {
        XCTAssertNil(runtime.core)
        let delegate = makeSwizzledDelegate()

        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)
        _ = facade.takeInitialClick()

        XCTAssertNil(runtime.core, "no core was needed at tap time")
        XCTAssertEqual(storedTypes, ["opened", "clicked"], "still queued after the launch click is consumed")
        XCTAssertTrue(StubURLProtocol.recordedRequests().isEmpty)
    }

    func test_theLaunchTapIsNotReplayedToALateClickedListenerButTakeInitialClickStillHasIt() {
        let delegate = makeSwizzledDelegate()
        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)

        var clicked: [NottiNotificationPayload] = []
        let subscription = facade.addClickedListener { clicked.append($0) }

        XCTAssertTrue(clicked.isEmpty, "the launch tap is read with takeInitialClick(), as documented")
        XCTAssertEqual(facade.takeInitialClick()?.data["link"], link)
        subscription.remove()
    }

    // MARK: - No URL opening, no link in logs

    func test_noCallbackOfEitherSwizzlerOpensAURL() {
        let delegate = makeSwizzledDelegate()
        let appClass = Fixtures.makeEmptyDelegateClass()
        XCTAssertTrue(app.swizzle(delegateClass: appClass))
        let appDelegate = Fixtures.makeInstance(appClass)

        Fixtures.sendWillPresent(delegate, userInfo(), center: spy)
        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)
        Fixtures.sendFetch(appDelegate, ["aps": ["content-available": 1], "link": link], application: spy)
        Fixtures.sendToken(appDelegate, Data([0x01]), application: spy)
        Fixtures.sendFailure(appDelegate, NSError(domain: "fixture.apns", code: 1), application: spy)

        XCTAssertEqual(spy.calls, [])
    }

    func test_theLinkNeverAppearsInALogLineAtVerbose() {
        let delegate = makeSwizzledDelegate()
        let appClass = Fixtures.makeEmptyDelegateClass()
        XCTAssertTrue(app.swizzle(delegateClass: appClass))

        Fixtures.sendWillPresent(delegate, userInfo(), center: spy)
        Fixtures.sendDidReceive(delegate, userInfo(), center: spy)
        Fixtures.sendFetch(Fixtures.makeInstance(appClass), ["aps": ["content-available": 1], "link": link], application: spy)
        _ = facade.takeInitialClick()

        for line in capturedLogs {
            XCTAssertFalse(line.contains("example.invalid"), "link leaked: \(line)")
            XCTAssertFalse(line.contains("fixture"), "payload value leaked: \(line)")
        }
    }
}
