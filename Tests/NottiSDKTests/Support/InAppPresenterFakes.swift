import UIKit
@testable import NottiSDK

/// Scene provider fake: `target` is what `activeTarget()` returns; `key` names the current scene for the hosts it
/// feeds (a plain object: no `UIWindowScene` exists in a test).
final class InAppFakeScenes: NottiInAppSceneProviding {
    var target: NottiInAppWindowTarget? = .screen(CGRect(x: 0, y: 0, width: 390, height: 844))
    var isAppActive = true
    var key: AnyObject = NSObject()

    func activeTarget() -> NottiInAppWindowTarget? { target }
}

/// Window host fake: builds the real root view controller (no window) so tests can lay it out and send it the
/// escape gesture; records `show` and `hide`.
final class InAppFakeHost: NottiInAppWindowHosting {
    let sceneKey: AnyObject?
    let target: NottiInAppWindowTarget
    let hostController: UIViewController?
    private(set) var controller: NottiInAppViewController?
    private(set) var showCount = 0
    private(set) var hideCount = 0

    init(target: NottiInAppWindowTarget, sceneKey: AnyObject?, hostController: UIViewController? = nil) {
        self.target = target
        self.sceneKey = sceneKey
        self.hostController = hostController
    }

    var content: NottiInAppWindowContent? { controller?.content }
    var isHidden: Bool { hideCount > 0 }

    func show(_ content: NottiInAppWindowContent) {
        showCount += 1
        let controller = NottiInAppViewController(content: content, host: hostController)
        controller.loadViewIfNeeded()
        self.controller = controller
    }

    func hide() {
        hideCount += 1
    }

    /// One layout pass of the root view at `size` (`viewDidLayoutSubviews` reports it to the presenter).
    func layout(_ size: CGSize = CGSize(width: 390, height: 844)) {
        guard let view = controller?.view else { return }
        view.frame = CGRect(origin: .zero, size: size)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    var messageView: NottiInAppMessageView? {
        (content?.overlay as? NottiInAppBarLayout)?.messageView ?? (content?.overlay as? NottiInAppCardLayout)?.messageView
    }
}

/// Records what the presenter reports, in order.
final class InAppRecordingEvents: NottiInAppDisplayEvents {
    private(set) var calls: [String] = []

    func displayAttached(displayId: String, attached: Bool) { calls.append("attached(\(displayId),\(attached))") }
    func becameVisible(displayId: String) { calls.append("visible(\(displayId))") }
    func userTapped(displayId: String, buttonId: String, action: NottiInAppButtonAction?) {
        calls.append("tap(\(displayId),\(buttonId))")
    }
    func userDismissed(displayId: String, reason: String) { calls.append("dismiss(\(displayId),\(reason))") }
    func displayFailed(displayId: String) { calls.append("failed(\(displayId))") }

    func count(_ prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }
}

/// Everything a presenter test injects: scenes, hosts, image loader, the 3 s wait, a synchronous main dispatcher,
/// the screen, Reduce Motion, the animator and the accessibility poster.
final class InAppPresenterHarness {
    let scenes = InAppFakeScenes()
    let events = InAppRecordingEvents()
    let center = NotificationCenter()
    var hostController: UIViewController?
    private(set) var hosts: [InAppFakeHost] = []
    var reduceMotion = false
    var screen = (bounds: CGRect(x: 0, y: 0, width: 390, height: 844), scale: CGFloat(3))
    /// `nil` holds every image request; otherwise answered at once with this value.
    var imageAnswer: UIImage?? = .some(nil)
    struct ImageRequest {
        let url: URL
        let maxSidePx: CGFloat
        let done: (UIImage?) -> Void
    }

    struct Wait {
        let delay: TimeInterval
        let task: () -> Void
        var cancelled = false
    }

    private(set) var imageRequests: [ImageRequest] = []
    private(set) var waits: [Wait] = []
    private(set) var animations: [TimeInterval] = []
    /// The card's transform when each animation started.
    private(set) var startTransforms: [CGAffineTransform] = []
    private(set) var posts: [(UIAccessibility.Notification, Any?)] = []
    private weak var lastCard: NottiInAppMessageView?

    lazy var presenter: NottiInAppPresenter = {
        let presenter = NottiInAppPresenter(
            scenes: scenes,
            makeHost: { [unowned self] target in
                let host = InAppFakeHost(target: target, sceneKey: self.scenes.key, hostController: self.hostController)
                self.hosts.append(host)
                return host
            },
            loadImage: { [unowned self] url, maxSide, done in
                self.imageRequests.append(ImageRequest(url: url, maxSidePx: maxSide, done: done))
                if let answer = self.imageAnswer { done(answer) }
            },
            schedule: { [unowned self] delay, task in
                let index = self.waits.count
                self.waits.append(Wait(delay: delay, task: task))
                return { [unowned self] in self.waits[index].cancelled = true }
            },
            mainDispatcher: { $0() },
            screen: { [unowned self] in self.screen },
            reduceMotion: { [unowned self] in self.reduceMotion },
            animate: { [unowned self] duration, changes, completion in
                self.animations.append(duration)
                self.startTransforms.append(self.hosts.last?.messageView?.transform ?? .identity)
                changes()
                completion()
            },
            post: { [unowned self] notification, argument in self.posts.append((notification, argument)) },
            center: center
        )
        presenter.events = events
        return presenter
    }()

    var host: InAppFakeHost? { hosts.last }

    func fireWait(_ index: Int = 0) {
        let wait = waits[index]
        if !wait.cancelled { wait.task() }
    }
}

/// A host view controller with fixed orientation and status bar values.
final class InAppPortraitHostController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { true }
}
