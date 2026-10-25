import UIKit

/// The full-size overlay of a `top` or `bottom` message (IAM-13, IAM-15, IAM-18, IAM-19, IAM-21), a port of RN
/// `InAppOverlayView` and the bar part of `InAppInteraction` (`NottiInAppViews.swift:20-106, 363-545`). It places
/// the card under the top or above the bottom safe area with the `margin` inset measured from the safe-area edge,
/// recomputes the frame on every layout pass (rotation, resize), and lets every touch outside the card reach the
/// app. The swipe and the body tap are set up by `NottiInAppBarInteraction`, whose handlers tests call directly.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppBarLayout: UIView {

    let messageView: NottiInAppMessageView
    let interaction: NottiInAppBarInteraction

    /// Replaces the view's own `safeAreaInsets`. Tests set it: a view outside a window has no safe area.
    var safeAreaOverride: UIEdgeInsets? {
        didSet { setNeedsLayout() }
    }

    private(set) var messageFrame: NottiInAppFrame?

    /// `messageView` must be built for a `top` or `bottom` message.
    init(messageView: NottiInAppMessageView) {
        precondition(messageView.kind == .bar, "NottiInAppBarLayout hosts top and bottom messages only")
        self.messageView = messageView
        interaction = NottiInAppBarInteraction(messageView: messageView)
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(messageView)
        interaction.install(in: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var safeArea: UIEdgeInsets { safeAreaOverride ?? safeAreaInsets }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = NottiInAppLayout.frame(
            format: messageView.message.format, margin: messageView.appearance.margin, container: bounds.size, safe: safeArea
        )
        messageFrame = frame
        let height = messageView.fittingHeight(width: frame.width, maxHeight: frame.maxHeight)
        messageView.bounds = CGRect(x: 0, y: 0, width: frame.width, height: height)
        // Bounds and center, not `frame`: the card may carry a swipe transform.
        let rect = NottiInAppLayout.cardRect(frame, height: height, container: bounds.size)
        messageView.center = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// A touch outside the bar reaches the app (IAM-36).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// The swipe and the body tap of a bar. Only the first outcome counts (the card's gate): a swipe or tap on a
/// closing display is ignored.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppBarInteraction: NSObject, UIGestureRecognizerDelegate {

    private unowned let messageView: NottiInAppMessageView
    private weak var root: UIView?
    /// -1 dismisses upward (`top`), 1 downward (`bottom`).
    let dismissDirection: CGFloat

    /// Read on each snap-back; injected by tests.
    var reduceMotion: () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    var animate: (TimeInterval, @escaping () -> Void) -> Void = { duration, changes in
        UIView.animate(withDuration: duration, animations: changes)
    }

    private(set) var pan: UIPanGestureRecognizer?
    private(set) var bodyTap: UITapGestureRecognizer?

    init(messageView: NottiInAppMessageView) {
        self.messageView = messageView
        dismissDirection = messageView.message.format == .top ? -1 : 1
        super.init()
    }

    func install(in root: UIView) {
        self.root = root
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        messageView.addGestureRecognizer(pan)
        // The text scrolls only once the drag is known not to be a swipe.
        messageView.scroll.panGestureRecognizer.require(toFail: pan)
        self.pan = pan
        // A bar without buttons is not tappable (IAM-19).
        if !messageView.message.buttons.isEmpty {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBodyTap))
            tap.delegate = self
            messageView.addGestureRecognizer(tap)
            bodyTap = tap
        }
    }

    // MARK: Body tap

    /// A bar body tap acts as the first button, `push_permission` included (IAM-19).
    @objc func handleBodyTap() {
        guard let first = messageView.message.buttons.first else { return }
        messageView.report(.tap(buttonId: first.id, action: first.action))
    }

    /// `point` in card coordinates: a body tap outside the close control, the buttons and a tappable image.
    func bodyTapAccepts(_ point: CGPoint) -> Bool {
        var excluded: [UIView] = [messageView.closeButton] + messageView.buttons
        if messageView.imageTappable, let image = messageView.imageView { excluded.append(image) }
        return !excluded.contains { view in
            !view.isHidden && view.superview != nil && view.convert(view.bounds, to: messageView).contains(point)
        }
    }

    // MARK: Swipe

    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let distance = recognizer.translation(in: root).y
        switch recognizer.state {
        case .changed: panChanged(distance)
        case .ended: panEnded(distance)
        case .cancelled, .failed: settle()
        default: break
        }
    }

    /// A third of the bar height, at most the close target (IAM-13).
    var swipeThreshold: CGFloat {
        min(messageView.bounds.height / 3, NottiInAppMetrics.closeTarget)
    }

    /// The card follows the finger in the dismiss direction only.
    func panChanged(_ distance: CGFloat) {
        guard !messageView.isFinished else { return }
        let offset = dismissDirection < 0 ? min(0, distance) : max(0, distance)
        messageView.transform = CGAffineTransform(translationX: 0, y: offset)
    }

    /// At or past the threshold in the dismiss direction: `swipe`; otherwise the card snaps back.
    func panEnded(_ distance: CGFloat) {
        if !messageView.isFinished && distance * dismissDirection >= swipeThreshold {
            messageView.report(.dismiss(reason: NottiInAppDismissReason.swipe))
        } else {
            settle()
        }
    }

    /// Snaps the card back, without animation under Reduce Motion.
    func settle() {
        let card = messageView
        let changes = { card.transform = .identity }
        if reduceMotion() { changes() } else { animate(0.2, changes) }
    }

    /// A drag becomes a swipe when it is mostly vertical, in the dismiss direction, and the text cannot scroll
    /// that way first.
    func startsSwipe(horizontal: CGFloat, vertical: CGFloat) -> Bool {
        guard !messageView.isFinished, abs(vertical) > abs(horizontal), vertical * dismissDirection > 0 else {
            return false
        }
        let scroll = messageView.scroll
        let maxOffset = max(scroll.contentSize.height - scroll.bounds.height, 0)
        // A finger moving up scrolls the content down, and the other way round.
        let canScroll = dismissDirection < 0 ? scroll.contentOffset.y < maxOffset - 0.5 : scroll.contentOffset.y > 0.5
        return !canScroll
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === pan, let pan = pan else { return true }
        let velocity = pan.velocity(in: root)
        return startsSwipe(horizontal: velocity.x, vertical: velocity.y)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if recognizer === bodyTap { return bodyTapAccepts(touch.location(in: messageView)) }
        return true
    }
}
