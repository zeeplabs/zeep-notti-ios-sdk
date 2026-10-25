import XCTest
import UIKit
@testable import NottiSDK
#if canImport(NottiShared)
import NottiShared
#endif

/// IAM-18, IAM-36, IAM-37, IAM-38, IAM-40 (`maxSidePx`). The presenter, its window and root view controller, a port
/// of the cases of RN `NottiInAppPresenterTests` (0.8.0). Scenes, hosts, the image loader, the 3 s wait, the main
/// dispatcher, the screen, Reduce Motion, the animator and the accessibility poster are injected; no test reads
/// `UIApplication.shared` windows or scenes, no sleeps, no network. Synthetic values only.
final class NottiInAppPresenterTests: XCTestCase {

    private var harness: InAppPresenterHarness!
    private var displayCount = 0

    override func setUp() {
        super.setUp()
        harness = InAppPresenterHarness()
        displayCount = 0
    }

    override func tearDown() {
        harness = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func display(
        _ format: NottiInAppFormat,
        title: String = "fixture title",
        buttons: [NottiInAppButton] = []
    ) -> NottiInAppDisplay {
        displayCount += 1
        return NottiInAppDisplay(
            id: "fixture-display-\(displayCount)",
            message: InAppViewFixtures.message(format, title: title, buttons: buttons)
        )
    }

    /// Presents, lays out once and returns the display.
    @discardableResult
    private func show(_ format: NottiInAppFormat, title: String = "fixture title") -> NottiInAppDisplay {
        let shown = display(format, title: title)
        harness.presenter.present(shown)
        harness.host?.layout()
        return shown
    }

    private var calls: [String] { harness.events.calls }

    // MARK: Window

    func test_windowIsNeverKeyAndSitsAtTheAlertLevel() throws {
        let host = NottiInAppWindowHost(
            target: .screen(CGRect(x: 0, y: 0, width: 390, height: 844)), hostController: { _ in nil }
        )
        let overlay = NottiInAppBarLayout(messageView: NottiInAppMessageView(message: InAppViewFixtures.message(.top)))
        host.show(NottiInAppWindowContent(overlay: overlay, onLayout: {}, onEscape: { false }))
        let window = try XCTUnwrap(host.window)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertEqual(window.windowLevel, .alert)
        XCTAssertFalse(window.isHidden)
        XCTAssertTrue(window.rootViewController is NottiInAppViewController)
        host.hide()
        XCTAssertNil(host.window)
        XCTAssertTrue(window.isHidden)
    }

    func test_aBarWindowLetsTouchesOutsideTheBarReachTheApp() throws {
        let messageView = NottiInAppMessageView(message: InAppViewFixtures.message(.top))
        let window = try shownWindow(NottiInAppBarLayout(messageView: messageView))
        XCTAssertNil(window.hitTest(CGPoint(x: 195, y: 700), with: nil), "outside the bar")
        let inside = messageView.convert(CGPoint(x: messageView.bounds.midX, y: messageView.bounds.midY), to: window)
        let hit = try XCTUnwrap(window.hitTest(inside, with: nil))
        XCTAssertTrue(hit.isDescendant(of: messageView), "inside the bar")
    }

    func test_centerAndFullWindowsBlockTouchesOnTheBackdrop() throws {
        for format in [NottiInAppFormat.center, .full] {
            let overlay = NottiInAppCardLayout(messageView: NottiInAppMessageView(message: InAppViewFixtures.message(format)))
            let window = try shownWindow(overlay)
            let hit = window.hitTest(CGPoint(x: 4, y: 4), with: nil)
            XCTAssertNotNil(hit, "\(format)")
            XCTAssertTrue(hit === overlay, "\(format)")
        }
    }

    func test_theRootControllerFollowsTheHostOrientationAndStatusBar() {
        let host = InAppPortraitHostController()
        let content = NottiInAppWindowContent(overlay: UIView(), onLayout: {}, onEscape: { false })
        let controller = NottiInAppViewController(content: content, host: host)
        XCTAssertEqual(controller.supportedInterfaceOrientations, .portrait)
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertTrue(controller.prefersStatusBarHidden)
        let windowHost = NottiInAppWindowHost(target: .screen(CGRect(x: 0, y: 0, width: 390, height: 844))) { _ in host }
        windowHost.show(content)
        XCTAssertEqual(windowHost.window?.rootViewController?.supportedInterfaceOrientations, .portrait)
        windowHost.hide()
    }

    func test_theSceneProviderUsesTheScreenOnlyForAnActiveSceneLessApp() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        guard case .screen(let rect)? = NottiInAppSceneProvider.target(
            activeScene: nil, sceneCount: 0, appActive: true, screenBounds: bounds
        ) else { return XCTFail("expected the screen fallback") }
        XCTAssertEqual(rect, bounds)
        XCTAssertNil(NottiInAppSceneProvider.target(activeScene: nil, sceneCount: 0, appActive: false, screenBounds: bounds))
        XCTAssertNil(NottiInAppSceneProvider.target(activeScene: nil, sceneCount: 1, appActive: true, screenBounds: bounds))
    }

    func test_aScreenTargetFromTheProviderBuildsTheFallbackWindowHost() {
        show(.top)
        guard case .screen(let rect)? = harness.host?.target else { return XCTFail("expected a screen target") }
        XCTAssertEqual(rect.size, CGSize(width: 390, height: 844))
    }

    // MARK: Accessibility

    func test_centerAndFullAreModalAndBarsAreNot() {
        for format in [NottiInAppFormat.top, .bottom, .center, .full] {
            harness = InAppPresenterHarness()
            show(format)
            let modal = harness.host?.content?.overlay.accessibilityViewIsModal
            XCTAssertEqual(modal, format == .center || format == .full, "\(format)")
        }
    }

    func test_centerAndFullMoveTheFocusToTheTitleOncePerDisplay() throws {
        for format in [NottiInAppFormat.center, .full] {
            harness = InAppPresenterHarness()
            show(format)
            harness.host?.layout(CGSize(width: 844, height: 390))
            harness.presenter.onActive()
            XCTAssertEqual(harness.posts.count, 1, "\(format)")
            let post = try XCTUnwrap(harness.posts.first)
            XCTAssertEqual(post.0, .screenChanged)
            XCTAssertTrue(post.1 as AnyObject? === harness.host?.messageView?.titleLabel, "\(format)")
        }
    }

    func test_aHiddenTitleMovesTheFocusToTheCard() throws {
        show(.center, title: "  ")
        let post = try XCTUnwrap(harness.posts.first)
        XCTAssertEqual(post.0, .screenChanged)
        XCTAssertTrue(post.1 as AnyObject? === harness.host?.messageView)
    }

    func test_barsAnnounceTitleAndBodyOncePerDisplay() throws {
        for format in [NottiInAppFormat.top, .bottom] {
            harness = InAppPresenterHarness()
            show(format)
            harness.host?.layout()
            XCTAssertEqual(harness.posts.count, 1, "\(format)")
            let post = try XCTUnwrap(harness.posts.first)
            XCTAssertEqual(post.0, .announcement)
            XCTAssertEqual(post.1 as? String, "fixture title. fixture body")
        }
    }

    func test_theEscapeGestureClosesCenterAndFullWithCloseButtonOnce() throws {
        for format in [NottiInAppFormat.center, .full] {
            harness = InAppPresenterHarness()
            let shown = show(format)
            let controller = try XCTUnwrap(harness.host?.controller)
            XCTAssertTrue(controller.accessibilityPerformEscape(), "\(format)")
            XCTAssertEqual(harness.events.count("dismiss"), 1)
            XCTAssertEqual(calls.last, "dismiss(\(shown.id),close_button)")
            // The engine answers with close; a later escape on the fading window reports nothing.
            harness.presenter.close(displayId: shown.id)
            XCTAssertTrue(controller.accessibilityPerformEscape(), "\(format)")
            XCTAssertEqual(harness.events.count("dismiss"), 1, "\(format)")
        }
    }

    func test_theEscapeGestureIsNotHandledOnBars() throws {
        for format in [NottiInAppFormat.top, .bottom] {
            harness = InAppPresenterHarness()
            show(format)
            let controller = try XCTUnwrap(harness.host?.controller)
            XCTAssertFalse(controller.accessibilityPerformEscape(), "\(format)")
            XCTAssertEqual(harness.events.count("dismiss"), 0, "\(format)")
        }
    }

    // MARK: Motion

    func test_reduceMotionCrossFadesInAndOutAndTheDismissalCompletes() throws {
        for format in [NottiInAppFormat.top, .center, .full] {
            harness = InAppPresenterHarness()
            harness.reduceMotion = true
            let shown = show(format)
            XCTAssertEqual(harness.animations, [0.15], "\(format)")
            XCTAssertEqual(harness.startTransforms, [.identity], "no movement: \(format)")
            XCTAssertEqual(harness.host?.content?.overlay.alpha, 1)
            harness.presenter.close(displayId: shown.id)
            XCTAssertEqual(harness.animations, [0.15, 0.15], "\(format)")
            XCTAssertEqual(harness.host?.hideCount, 1, "\(format)")
            XCTAssertEqual(harness.host?.content?.overlay.alpha, 0)
        }
    }

    func test_withoutReduceMotionABarSlidesFromItsEdge() {
        let shown = show(.top)
        XCTAssertEqual(harness.animations, [0.25])
        XCTAssertEqual(harness.startTransforms.first?.ty, -24)
        XCTAssertEqual(harness.host?.messageView?.transform, .identity)
        harness.presenter.close(displayId: shown.id)
        XCTAssertEqual(harness.animations, [0.25, 0.2])
        XCTAssertEqual(harness.host?.hideCount, 1)
        XCTAssertEqual(harness.host?.content?.overlay.isUserInteractionEnabled, false, "touches pass through while fading")
    }

    func test_reduceMotionSnapsTheBarBackWithoutAnimation() throws {
        harness.reduceMotion = true
        show(.bottom)
        let overlay = try XCTUnwrap(harness.host?.content?.overlay as? NottiInAppBarLayout)
        overlay.interaction.panChanged(20)
        overlay.interaction.settle()
        XCTAssertEqual(harness.animations, [0.15], "only the entrance cross-fade")
        XCTAssertEqual(overlay.messageView.transform, .identity)
        harness.reduceMotion = false
        overlay.interaction.panChanged(20)
        overlay.interaction.settle()
        XCTAssertEqual(harness.animations, [0.15, 0.2])
    }

    // MARK: Image

    func test_theImageIsRequestedAtTheScreenLongSideTimesItsScale() throws {
        harness.imageAnswer = .some(InAppViewFixtures.picture())
        show(.center)
        let request = try XCTUnwrap(harness.imageRequests.first)
        XCTAssertEqual(request.maxSidePx, 2532)
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/fixture.png")
        XCTAssertNotNil(harness.host?.messageView?.imageView)
        XCTAssertEqual(harness.waits.first?.delay, 3)
        XCTAssertEqual(harness.waits.first?.cancelled, true)
    }

    func test_noImageWithinThreeSecondsPresentsWithoutItAndALateImageIsIgnored() throws {
        harness.imageAnswer = nil
        harness.screen = (CGRect(x: 0, y: 0, width: 1024, height: 768), 2)
        harness.presenter.present(display(.center))
        XCTAssertTrue(harness.hosts.isEmpty, "waits for the image")
        XCTAssertEqual(harness.imageRequests.first?.maxSidePx, 2048)
        harness.fireWait()
        XCTAssertEqual(harness.hosts.count, 1)
        XCTAssertNil(harness.host?.messageView?.imageView)
        try XCTUnwrap(harness.imageRequests.first).done(InAppViewFixtures.picture())
        XCTAssertEqual(harness.hosts.count, 1)
        XCTAssertEqual(harness.host?.showCount, 1)
        XCTAssertNil(harness.host?.messageView?.imageView)
    }

    // MARK: Scenes

    func test_losingAndRegainingASceneKeepsTheDisplayWithNoNewImpressionOrDismiss() throws {
        let shown = show(.center)
        let first = try XCTUnwrap(harness.host)
        let oldScene = harness.scenes.key
        harness.scenes.key = NSObject()
        harness.center.post(name: UIScene.didDisconnectNotification, object: oldScene)
        XCTAssertEqual(first.hideCount, 1)
        XCTAssertEqual(harness.hosts.count, 2)
        harness.host?.layout()
        XCTAssertEqual(calls, [
            "attached(\(shown.id),true)",
            "visible(\(shown.id))",
            "attached(\(shown.id),false)",
            "attached(\(shown.id),true)"
        ])
        XCTAssertEqual(harness.posts.count, 1, "announced once per display")
    }

    func test_anotherScenesDisconnectIsIgnored() {
        show(.top)
        harness.center.post(name: UIScene.didDisconnectNotification, object: NSObject())
        XCTAssertEqual(harness.hosts.count, 1)
        XCTAssertEqual(harness.host?.hideCount, 0)
    }

    func test_withNoOtherSceneTheDisplayWaitsForTheNextActivation() {
        let shown = show(.bottom)
        let oldScene = harness.scenes.key
        harness.scenes.target = nil
        harness.center.post(name: UIScene.didDisconnectNotification, object: oldScene)
        XCTAssertEqual(harness.hosts.count, 1)
        harness.scenes.target = .screen(CGRect(x: 0, y: 0, width: 390, height: 844))
        harness.scenes.key = NSObject()
        harness.center.post(name: UIScene.didActivateNotification, object: harness.scenes.key)
        XCTAssertEqual(harness.hosts.count, 2)
        XCTAssertEqual(calls.filter { $0.hasPrefix("attached") }, [
            "attached(\(shown.id),true)", "attached(\(shown.id),false)", "attached(\(shown.id),true)"
        ])
    }

    func test_withNothingActiveTheDisplayWaitsForDidBecomeActive() {
        harness.scenes.target = nil
        let shown = display(.center)
        harness.presenter.present(shown)
        XCTAssertTrue(harness.hosts.isEmpty)
        XCTAssertTrue(calls.isEmpty)
        harness.scenes.target = .screen(CGRect(x: 0, y: 0, width: 390, height: 844))
        harness.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(harness.hosts.count, 1)
        XCTAssertEqual(calls, ["attached(\(shown.id),true)"])
    }

    func test_becameVisibleIsReportedOnceAndOnlyAfterALayoutPassWhileActive() {
        harness.scenes.isAppActive = false
        let shown = display(.top)
        harness.presenter.present(shown)
        XCTAssertEqual(calls, ["attached(\(shown.id),true)"], "no layout yet")
        harness.host?.layout()
        XCTAssertEqual(harness.events.count("visible"), 0, "laid out while inactive")
        harness.scenes.isAppActive = true
        harness.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(harness.events.count("visible"), 1)
        harness.host?.layout(CGSize(width: 844, height: 390))
        harness.host?.layout()
        harness.presenter.onActive()
        XCTAssertEqual(harness.events.count("visible"), 1)
    }

    func test_anActiveAppAttachedBeforeLayoutReportsNothingUntilTheFirstLayout() {
        let shown = display(.full)
        harness.presenter.present(shown)
        harness.presenter.onActive()
        XCTAssertEqual(harness.events.count("visible"), 0)
        harness.host?.layout()
        XCTAssertEqual(calls, ["attached(\(shown.id),true)", "visible(\(shown.id))"])
    }

    // MARK: Outcomes and removal

    func test_tapsAndClosesOfTheViewsAreForwardedWithTheDisplayId() throws {
        let shown = display(.center, buttons: [InAppViewFixtures.button("fixture-btn", "fixture")])
        harness.presenter.present(shown)
        harness.host?.layout()
        let messageView = try XCTUnwrap(harness.host?.messageView)
        messageView.buttons.first?.sendActions(for: .touchUpInside)
        XCTAssertEqual(calls.last, "tap(\(shown.id),fixture-btn)")
        let bar = show(.top)
        harness.host?.messageView?.closeButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(calls.last, "dismiss(\(bar.id),close_button)")
    }

    func test_teardownHidesAtOnceAndReportsNothing() {
        let shown = show(.center)
        let before = calls
        harness.presenter.teardown(shown)
        XCTAssertEqual(harness.host?.hideCount, 1)
        XCTAssertEqual(harness.animations.count, 1, "no exit animation")
        XCTAssertEqual(calls, before)
        harness.presenter.teardown(shown)
        harness.presenter.close(displayId: shown.id)
        XCTAssertEqual(harness.host?.hideCount, 1, "idempotent")
    }

    func test_closeOfAnotherDisplayIdIsIgnored() {
        show(.center)
        harness.presenter.close(displayId: "fixture-other")
        XCTAssertEqual(harness.host?.hideCount, 0)
        XCTAssertNotNil(harness.presenter.attachment)
    }

    func test_aNewDisplayReplacesAPendingOneSilently() {
        harness.imageAnswer = nil
        let first = display(.center)
        harness.presenter.present(first)
        let second = display(.top)
        harness.presenter.present(second)
        harness.fireWait(0)
        XCTAssertTrue(harness.hosts.isEmpty, "the first wait no longer counts")
        harness.fireWait(1)
        XCTAssertEqual(calls, ["attached(\(second.id),true)"])
    }

    // MARK: Production wiring

    func test_theLiveEngineUsesTheRealPresenter() throws {
        let suite = "NottiInAppPresenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let presenter = NottiInAppPresenter(scenes: InAppFakeScenes(), center: NotificationCenter())
        let engine = NottiInAppEngine.live(defaults: defaults, clicks: NottiInAppClickRelay(), presenter: presenter)
        XCTAssertTrue(engine.presenter === presenter)
        XCTAssertTrue(presenter.events === engine)
        let runtime = try String(
            contentsOf: InAppViewFixtures.repoRoot.appendingPathComponent("Sources/NottiSDK/Runtime/NottiRuntime.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("inAppEngine: .live(defaults: defaults, clicks: clicks, presenter: NottiInAppPresenter()),"))
    }

    func test_withTheEngineASceneMoveRecordsOneImpressionAndEscapeOneDismiss() throws {
        let fixture = InAppPresenterEngineFixture(harness: harness)
        defer { fixture.cleanUp() }
        fixture.showMessage(#","format":"center""#)
        harness.host?.layout()
        fixture.scheduler.drain()
        XCTAssertEqual(fixture.types, ["impression"])
        let oldScene = harness.scenes.key
        harness.scenes.key = NSObject()
        harness.center.post(name: UIScene.didDisconnectNotification, object: oldScene)
        harness.host?.layout()
        fixture.scheduler.drain()
        XCTAssertEqual(fixture.types, ["impression"])
        XCTAssertTrue(try XCTUnwrap(harness.host?.controller).accessibilityPerformEscape())
        fixture.scheduler.drain()
        XCTAssertEqual(fixture.types, ["impression", "dismiss"])
        XCTAssertEqual(fixture.store.all().last?.reason, "close_button")
        XCTAssertEqual(harness.host?.hideCount, 1)
    }

    func test_withTheEngineATapBeforeVisibleIsIgnored() throws {
        let fixture = InAppPresenterEngineFixture(harness: harness)
        defer { fixture.cleanUp() }
        harness.scenes.isAppActive = false
        fixture.showMessage(#","format":"center""#)
        harness.host?.layout()
        harness.host?.messageView?.closeButton.sendActions(for: .touchUpInside)
        fixture.scheduler.drain()
        XCTAssertEqual(fixture.types, [])
    }

    // MARK: Window helper

    private func shownWindow(_ overlay: UIView) throws -> NottiInAppWindow {
        let host = NottiInAppWindowHost(target: .screen(CGRect(x: 0, y: 0, width: 390, height: 844))) { _ in nil }
        host.show(NottiInAppWindowContent(overlay: overlay, onLayout: {}, onEscape: { false }))
        addTeardownBlock { host.hide() }
        let window = try XCTUnwrap(host.window)
        window.layoutIfNeeded()
        return window
    }
}

/// A real engine on the fake scheduler and network, presenting through the harness presenter.
final class InAppPresenterEngineFixture {
    let scheduler = InAppFakeScheduler()
    let network = InAppFakeNetwork()
    let store: NottiInAppEventStore
    let engine: NottiInAppEngine
    private let suiteName = "InAppPresenterEngineFixture.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init(harness: InAppPresenterHarness) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let clock = scheduler
        store = NottiInAppEventStore(defaults: defaults, clock: { Int64(clock.now.timeIntervalSince1970 * 1000) })
        let network = self.network
        engine = NottiInAppEngine(
            store: store,
            identity: { NottiInAppIdentity(deviceId: "fixture-device", token: "fixture-token") },
            presenter: harness.presenter,
            scheduler: scheduler,
            now: { clock.now },
            mainDispatcher: { $0() },
            clientFactory: { network.transport(appId: $0.appId) }
        )
        harness.presenter.events = engine
    }

    var types: [String] { store.all().map(\.type) }

    /// Fetches one `session_start` message with `extra` JSON and holds later sends.
    func showMessage(_ extra: String) {
        network.enqueue(.messages(InAppFixtureJSON.sessionStart("fixture-msg", extra: extra)))
        engine.configure(appId: "fixture-app", clientKey: "fixture-key", baseUrl: "https://api.example.invalid")
        scheduler.drain()
        engine.sessionStarted()
        scheduler.drain()
        engine.deviceRegistered()
        scheduler.drain()
        network.holding = true
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
