import UIKit

/// Layout metrics of an In-App message, ported from RN 0.8.0: `InAppMetrics` (`NottiInAppStyle.swift:126-134`)
/// and the card metrics of `NottiInAppViews.swift:4-18`.
@available(iOSApplicationExtension, unavailable)
enum NottiInAppMetrics {
    /// The `margin: true` inset, measured from the safe-area edge.
    static let margin: CGFloat = 16
    static let barMaxHeightFraction: CGFloat = 0.4
    static let cardMaxWidthFraction: CGFloat = 0.9
    static let cardMaxWidth: CGFloat = 560
    static let cardMaxHeightFraction: CGFloat = 0.9
    /// The close control's hit area and the minimum button height.
    static let closeTarget: CGFloat = 44
    static let thumbnail: CGFloat = 56
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 8
    static let imageGap: CGFloat = 12
    static let titleBodyGap: CGFloat = 4
    static let buttonTopGap: CGFloat = 12
    static let imageMaxHeight: CGFloat = 180
    static let cornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 8
    /// Keeps the close target (and its scrim chip) fully inside the rounded card corner.
    static let closeInset: CGFloat = 8
    /// Room kept clear for the close control beside the text.
    static let closeReserve: CGFloat = closeTarget - padding + closeInset
    static let scrimAlpha: CGFloat = 0.4
    static let backdropAlpha: CGFloat = 0.5
}

@available(iOSApplicationExtension, unavailable)
enum NottiInAppGravity: Equatable {
    case top
    case bottom
    case center
    case fill
}

/// Where the message goes in a container, in points (RN `InAppFrame`). The margins are distances from the
/// container edges, safe area included; a `.center` card is centered inside them. The height grows with the
/// content up to `maxHeight` (`.fill` always takes `maxHeight`).
@available(iOSApplicationExtension, unavailable)
struct NottiInAppFrame: Equatable {
    let gravity: NottiInAppGravity
    let marginLeft: CGFloat
    let marginTop: CGFloat
    let marginRight: CGFloat
    let marginBottom: CGFloat
    let width: CGFloat
    let maxHeight: CGFloat
}

/// Pure bounds per layout (IAM-13, IAM-21), a port of RN `computeFrame` (`NottiInAppStyle.swift:140-182`) and of
/// the placement in `InAppOverlayView.layoutSubviews` (`NottiInAppViews.swift:63-92`).
@available(iOSApplicationExtension, unavailable)
enum NottiInAppLayout {

    /// The 16 pt margin is measured from the safe-area edge; without it the message touches the safe-area
    /// edges on every side and never goes under the notch, Dynamic Island or home indicator. `center` ignores it.
    static func frame(format: NottiInAppFormat, margin: Bool, container: CGSize, safe: UIEdgeInsets) -> NottiInAppFrame {
        let inset: CGFloat = margin ? NottiInAppMetrics.margin : 0
        let safeWidth = max(container.width - safe.left - safe.right, 0)
        let safeHeight = max(container.height - safe.top - safe.bottom, 0)
        switch format {
        case .top, .bottom:
            return NottiInAppFrame(
                gravity: format == .top ? .top : .bottom,
                marginLeft: safe.left + inset,
                marginTop: safe.top + inset,
                marginRight: safe.right + inset,
                marginBottom: safe.bottom + inset,
                width: max(safeWidth - 2 * inset, 0),
                maxHeight: min(container.height * NottiInAppMetrics.barMaxHeightFraction, max(safeHeight - 2 * inset, 0))
            )
        case .center:
            return NottiInAppFrame(
                gravity: .center,
                marginLeft: safe.left,
                marginTop: safe.top,
                marginRight: safe.right,
                marginBottom: safe.bottom,
                width: min(
                    container.width * NottiInAppMetrics.cardMaxWidthFraction, NottiInAppMetrics.cardMaxWidth, safeWidth
                ),
                maxHeight: safeHeight * NottiInAppMetrics.cardMaxHeightFraction
            )
        case .full:
            return NottiInAppFrame(
                gravity: .fill,
                marginLeft: safe.left + inset,
                marginTop: safe.top + inset,
                marginRight: safe.right + inset,
                marginBottom: safe.bottom + inset,
                width: max(safeWidth - 2 * inset, 0),
                maxHeight: max(safeHeight - 2 * inset, 0)
            )
        }
    }

    /// The card's rectangle in a container of `container` size, for a card `height` (already capped).
    /// A `.center` card is centered in the safe area, not in the screen: the insets can be asymmetric.
    static func cardRect(_ frame: NottiInAppFrame, height: CGFloat, container: CGSize) -> CGRect {
        var originX = frame.marginLeft
        let originY: CGFloat
        switch frame.gravity {
        case .top, .fill:
            originY = frame.marginTop
        case .bottom:
            originY = container.height - frame.marginBottom - height
        case .center:
            let safeWidth = max(container.width - frame.marginLeft - frame.marginRight, 0)
            let safeHeight = max(container.height - frame.marginTop - frame.marginBottom, 0)
            originX += max((safeWidth - frame.width) / 2, 0)
            originY = frame.marginTop + max((safeHeight - height) / 2, 0)
        }
        return CGRect(x: originX, y: originY, width: frame.width, height: height)
    }
}
