import UIKit

/// The full-size overlay of a `center` or `full` message (IAM-13, IAM-15, IAM-17, IAM-18, IAM-21), a port of RN
/// `InAppOverlayView` and the `center` part of `InAppInteraction` (`NottiInAppViews.swift:20-106, 363-545, 649-654`).
/// `center`: a card centered in the safe area over a 50% black backdrop, width min(90% of the container, 560 pt, safe
/// width), height capped at 90% of the safe height, `margin` ignored, a tap outside the card closes it with
/// `outside_tap`. `full`: inside the safe areas with the `margin` inset, the whole height, no backdrop color and no
/// dismiss gesture (the close control is the only way out), corner radius 0 with `margin: false`. Both block the
/// touches to the app (IAM-36). The frame is recomputed on every layout pass.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppCardLayout: UIView, UIGestureRecognizerDelegate {

    let messageView: NottiInAppMessageView

    /// Replaces the view's own `safeAreaInsets`. Tests set it: a view outside a window has no safe area.
    var safeAreaOverride: UIEdgeInsets? {
        didSet { setNeedsLayout() }
    }

    private(set) var messageFrame: NottiInAppFrame?
    /// `center` only: a tap on the backdrop, outside the card.
    private(set) var backdropTap: UITapGestureRecognizer?

    /// `messageView` must be built for a `center` or `full` message.
    init(messageView: NottiInAppMessageView) {
        precondition(messageView.kind != .bar, "NottiInAppCardLayout hosts center and full messages only")
        self.messageView = messageView
        super.init(frame: .zero)
        accessibilityIdentifier = "notti.inapp.backdrop"
        addSubview(messageView)
        if messageView.kind == .card {
            backgroundColor = UIColor.black.withAlphaComponent(NottiInAppMetrics.backdropAlpha)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
            tap.delegate = self
            addGestureRecognizer(tap)
            backdropTap = tap
        } else {
            backgroundColor = .clear
            if !messageView.appearance.margin { messageView.layer.cornerRadius = 0 }
        }
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
        let height = frame.gravity == .fill
            ? frame.maxHeight
            : messageView.fittingHeight(width: frame.width, maxHeight: frame.maxHeight)
        messageView.frame = NottiInAppLayout.cardRect(frame, height: height, container: bounds.size)
    }

    // MARK: Outside tap

    @objc func handleBackdropTap() {
        messageView.report(.dismiss(reason: NottiInAppDismissReason.outsideTap))
    }

    /// `point` in overlay coordinates: outside the card.
    func backdropAccepts(_ point: CGPoint) -> Bool {
        !messageView.frame.contains(point)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if recognizer === backdropTap { return backdropAccepts(touch.location(in: self)) }
        return true
    }
}
