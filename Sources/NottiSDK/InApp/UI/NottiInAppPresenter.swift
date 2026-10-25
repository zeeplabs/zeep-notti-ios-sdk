import UIKit

/// What the presenter reports to the engine (design "Display state machine"). `NottiInAppEngine` implements it;
/// every method hops onto the engine queue and ignores an old display id.
protocol NottiInAppDisplayEvents: AnyObject {
    func displayAttached(displayId: String, attached: Bool)
    func becameVisible(displayId: String)
    func userTapped(displayId: String, buttonId: String, action: NottiInAppButtonAction?)
    func userDismissed(displayId: String, reason: String)
    func displayFailed(displayId: String)
}

extension NottiInAppEngine: NottiInAppDisplayEvents {}

/// Runs `animations` over `duration`, then `completion` (production: `UIView.animate`; tests run both at once).
typealias NottiInAppAnimator = (
    _ duration: TimeInterval, _ animations: @escaping () -> Void, _ completion: @escaping () -> Void
) -> Void

/// Entrance and exit timings (IAM-38). Under Reduce Motion both are a 0.15 s cross-fade with no movement.
enum NottiInAppMotion {
    static let crossFade: TimeInterval = 0.15
    static let entrance: TimeInterval = 0.25
    static let exit: TimeInterval = 0.2
    /// A bar slides this far in from (and back out to) its edge.
    static let barSlide: CGFloat = 24
}

/// The VoiceOver notifications of a shown display (RN `NottiInAppAccessibility.onShown`, `NottiInAppViews.swift:584-605`).
@available(iOSApplicationExtension, unavailable)
enum NottiInAppAccessibility {

    typealias Poster = (UIAccessibility.Notification, Any?) -> Void

    static let systemPoster: Poster = { UIAccessibility.post(notification: $0, argument: $1) }

    /// The visible title and body joined by ". ".
    static func announcement(_ view: NottiInAppMessageView) -> String {
        [view.titleLabel, view.bodyLabel]
            .filter { !$0.isHidden }
            .compactMap(\.text)
            .joined(separator: ". ")
    }

    /// A bar is announced; a `center` or `full` message moves the focus to its title (the card when the title is
    /// hidden).
    static func onShown(_ view: NottiInAppMessageView, post: Poster) {
        switch view.kind {
        case .bar:
            post(.announcement, announcement(view))
        case .card, .fill:
            post(.screenChanged, view.titleLabel.isHidden ? view : view.titleLabel)
        }
    }
}

/// Shows the engine's display in its own window (IAM-36, IAM-37, IAM-38, IAM-40), a port of RN
/// `NottiInAppWindowPresenter` (`NottiInAppPresenter.swift:149-359`). It waits at most 3 s for the image, builds the
/// views when a target is active, reports `displayAttached` both ways, reports `becameVisible` once per display after
/// a layout pass while the app is active, forwards taps and closes, and moves the same display to the next active
/// scene when its scene disconnects (no new impression, no dismiss). The views are disposable; the display is not.
/// Main thread only; the engine (`events`) is held weakly, it owns the presenter.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppPresenter: NottiInAppPresenting {

    /// Longest wait for the image before the message shows without it (D10).
    static let imageWait: TimeInterval = 3

    typealias ImageLoading = (_ url: URL, _ maxSidePx: CGFloat, _ done: @escaping (UIImage?) -> Void) -> Void
    /// Runs `task` after the delay on main and returns its cancel.
    typealias Scheduling = (_ delay: TimeInterval, _ task: @escaping () -> Void) -> () -> Void

    final class Attachment {
        let displayId: String
        let host: NottiInAppWindowHosting
        let overlay: UIView
        let messageView: NottiInAppMessageView
        var laidOut = false

        init(displayId: String, host: NottiInAppWindowHosting, overlay: UIView, messageView: NottiInAppMessageView) {
            self.displayId = displayId
            self.host = host
            self.overlay = overlay
            self.messageView = messageView
        }
    }

    weak var events: NottiInAppDisplayEvents?
    private let scenes: NottiInAppSceneProviding
    private let makeHost: (NottiInAppWindowTarget) -> NottiInAppWindowHosting
    private let loadImage: ImageLoading
    private let schedule: Scheduling
    private let mainDispatcher: NottiMainDispatcher
    private let screen: () -> (bounds: CGRect, scale: CGFloat)
    private let reduceMotion: () -> Bool
    private let animate: NottiInAppAnimator
    private let post: NottiInAppAccessibility.Poster
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    private var display: NottiInAppDisplay?
    private(set) var attachment: Attachment?
    /// False while the image of `display` is awaited; the window is built only once it is true.
    private var prepared = false
    /// Chosen once per display: every attach reuses it, a late image is never inserted.
    private var image: UIImage?
    private var cancelImageWait: (() -> Void)?
    /// Display id whose `becameVisible` (and accessibility notification) was already raised.
    private var visibleRaisedFor: String?

    init(
        scenes: NottiInAppSceneProviding = NottiInAppSceneProvider(),
        makeHost: @escaping (NottiInAppWindowTarget) -> NottiInAppWindowHosting = { NottiInAppWindowHost(target: $0) },
        loadImage: ImageLoading? = nil,
        schedule: @escaping Scheduling = NottiInAppPresenter.mainSchedule,
        mainDispatcher: @escaping NottiMainDispatcher = { DispatchQueue.main.async(execute: $0) },
        screen: @escaping () -> (bounds: CGRect, scale: CGFloat) = { (UIScreen.main.bounds, UIScreen.main.scale) },
        reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        animate: @escaping NottiInAppAnimator = NottiInAppPresenter.systemAnimator,
        post: @escaping NottiInAppAccessibility.Poster = NottiInAppAccessibility.systemPoster,
        center: NotificationCenter = .default
    ) {
        self.scenes = scenes
        self.makeHost = makeHost
        if let loadImage = loadImage {
            self.loadImage = loadImage
        } else {
            let loader = NottiInAppImageLoader()
            self.loadImage = { loader.load(url: $0, maxSidePx: $1, done: $2) }
        }
        self.schedule = schedule
        self.mainDispatcher = mainDispatcher
        self.screen = screen
        self.reduceMotion = reduceMotion
        self.animate = animate
        self.post = post
        self.center = center
        // Posted on the main thread by UIKit; handled where posted.
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                self?.onActive()
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { [weak self] _ in
                self?.onActive()
            },
            center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: nil) { [weak self] note in
                self?.onSceneGone(note.object as AnyObject?)
            }
        ]
    }

    deinit {
        observers.forEach(center.removeObserver)
    }

    static let mainSchedule: Scheduling = { delay, task in
        let item = DispatchWorkItem(block: task)
        // A wall-clock deadline (no uptime clock, D8).
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    static let systemAnimator: NottiInAppAnimator = { duration, animations, completion in
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: animations,
            completion: { _ in completion() }
        )
    }

    // MARK: NottiInAppPresenting

    func present(_ display: NottiInAppDisplay) {
        if self.display === display { return }
        if self.display != nil { teardownSilently() }
        self.display = display
        prepare(display)
    }

    /// After the display's terminal event: the window fades out (slides too for a bar), then hides.
    func close(displayId: String) {
        guard display?.id == displayId else { return }
        if let current = attachment {
            attachment = nil
            exit(current)
        }
        forget()
    }

    func teardown(_ display: NottiInAppDisplay) {
        if self.display === display { teardownSilently() }
    }

    /// Hides and releases the window at once and reports nothing.
    private func teardownSilently() {
        detach(report: false)
        forget()
    }

    // MARK: Image

    /// Waits at most `imageWait` for the image, then attaches with or without it (IAM-40, D10).
    private func prepare(_ target: NottiInAppDisplay) {
        guard let url = target.message.imageUrl else {
            ready(target, nil)
            return
        }
        cancelImageWait = schedule(Self.imageWait) { [weak self] in self?.ready(target, nil) }
        let size = screen()
        let maxSidePx = max(size.bounds.width, size.bounds.height) * size.scale
        let dispatcher = mainDispatcher
        loadImage(url, maxSidePx) { [weak self] loaded in
            dispatcher { self?.ready(target, loaded) }
        }
    }

    /// First outcome wins: the image, its failure or the wait; anything later is ignored.
    private func ready(_ target: NottiInAppDisplay, _ loaded: UIImage?) {
        guard display === target, !prepared else { return }
        cancelImageWait?()
        cancelImageWait = nil
        prepared = true
        image = loaded
        attachIfPossible()
    }

    private func forget() {
        cancelImageWait?()
        cancelImageWait = nil
        display = nil
        prepared = false
        image = nil
    }

    // MARK: Lifecycle

    /// The app or a scene became active: attach a waiting display, or raise the `becameVisible` that a layout
    /// while inactive could not.
    func onActive() {
        if let current = attachment {
            if current.laidOut { raiseVisible(current) }
            return
        }
        attachIfPossible()
    }

    /// The display's scene went away: drop the window, keep the display for the next active scene (IAM-37).
    func onSceneGone(_ scene: AnyObject?) {
        guard let current = attachment, let scene = scene, current.host.sceneKey === scene else { return }
        detach(report: true)
        attachIfPossible()
    }

    private func attachIfPossible() {
        guard let target = display, events != nil, prepared, attachment == nil else { return }
        // Nothing active (cold start before activation): the display stays preparing.
        guard let windowTarget = scenes.activeTarget() else { return }
        let displayId = target.id
        let messageView = NottiInAppMessageView(message: target.message, image: image)
        let overlay = makeOverlay(messageView)
        messageView.onOutcome = { [weak self] outcome in self?.forward(outcome, displayId: displayId) }
        let created = Attachment(displayId: displayId, host: makeHost(windowTarget), overlay: overlay, messageView: messageView)
        attachment = created
        let handlesEscape = messageView.kind != .bar
        events?.displayAttached(displayId: displayId, attached: true)
        created.host.show(NottiInAppWindowContent(
            overlay: overlay,
            onLayout: { [weak self, weak created] in
                guard let self = self, let created = created, self.attachment === created else { return }
                created.laidOut = true
                self.raiseVisible(created)
            },
            onEscape: { [weak self, weak created] in
                // Handled for `center` and `full` even once the display is closing (the window is fading out).
                guard handlesEscape else { return false }
                self?.escape(created)
                return true
            }
        ))
        enter(created)
    }

    private func makeOverlay(_ messageView: NottiInAppMessageView) -> UIView {
        if messageView.kind == .bar {
            let bar = NottiInAppBarLayout(messageView: messageView)
            let animate = self.animate
            bar.interaction.reduceMotion = reduceMotion
            bar.interaction.animate = { duration, changes in animate(duration, changes, {}) }
            return bar
        }
        let card = NottiInAppCardLayout(messageView: messageView)
        // VoiceOver stays inside the message (IAM-38).
        card.accessibilityViewIsModal = true
        return card
    }

    /// Once per display, after a layout pass while the app is active (D9).
    private func raiseVisible(_ current: Attachment) {
        guard scenes.isAppActive, visibleRaisedFor != current.displayId else { return }
        visibleRaisedFor = current.displayId
        events?.becameVisible(displayId: current.displayId)
        NottiInAppAccessibility.onShown(current.messageView, post: post)
    }

    private func detach(report: Bool) {
        guard let current = attachment else { return }
        attachment = nil
        current.host.hide()
        if report { events?.displayAttached(displayId: current.displayId, attached: false) }
    }

    private func forward(_ outcome: NottiInAppViewOutcome, displayId: String) {
        switch outcome {
        case let .tap(buttonId, action):
            events?.userTapped(displayId: displayId, buttonId: buttonId, action: action)
        case let .dismiss(reason):
            events?.userDismissed(displayId: displayId, reason: reason)
        }
    }

    /// The escape gesture on `center` and `full` acts as the close control (`close_button`). A closing display
    /// reports nothing more.
    private func escape(_ target: Attachment?) {
        guard let target = target, attachment === target else { return }
        target.messageView.report(.dismiss(reason: NottiInAppDismissReason.closeButton))
    }

    // MARK: Motion

    /// A bar slides in from its edge while fading in; `center` and `full` fade in. Reduce Motion: a cross-fade only.
    private func enter(_ target: Attachment) {
        let overlay = target.overlay
        let card = target.messageView
        overlay.alpha = 0
        if reduceMotion() {
            animate(NottiInAppMotion.crossFade, { overlay.alpha = 1 }, {})
            return
        }
        if card.kind == .bar { card.transform = CGAffineTransform(translationX: 0, y: barSlideOffset(card)) }
        animate(NottiInAppMotion.entrance, {
            overlay.alpha = 1
            card.transform = .identity
        }, {})
    }

    /// The reverse of `enter`; the window hides when it ends. Touches pass through meanwhile.
    private func exit(_ target: Attachment) {
        let overlay = target.overlay
        let card = target.messageView
        let host = target.host
        overlay.isUserInteractionEnabled = false
        if reduceMotion() {
            animate(NottiInAppMotion.crossFade, { overlay.alpha = 0 }, { host.hide() })
            return
        }
        let slide = card.kind == .bar ? card.transform.ty + barSlideOffset(card) : 0
        animate(NottiInAppMotion.exit, {
            overlay.alpha = 0
            if card.kind == .bar { card.transform = CGAffineTransform(translationX: 0, y: slide) }
        }, { host.hide() })
    }

    /// Toward the bar's own edge: up for `top`, down for `bottom`.
    private func barSlideOffset(_ card: NottiInAppMessageView) -> CGFloat {
        card.message.format == .top ? -NottiInAppMotion.barSlide : NottiInAppMotion.barSlide
    }
}
