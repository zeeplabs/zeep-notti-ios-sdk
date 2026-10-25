import UIKit

/// What a display's views report. The presenter forwards a tap to `engine.userTapped(displayId:buttonId:action:)`
/// and a dismiss to `engine.userDismissed(displayId:reason:)` (`NottiInAppDismissReason`).
@available(iOSApplicationExtension, unavailable)
enum NottiInAppViewOutcome: Equatable {
    /// `buttonId` is a button id, or `image` for the image; `action` is passed untouched.
    case tap(buttonId: String, action: NottiInAppButtonAction?)
    case dismiss(reason: String)
}

/// The message card shared by every layout (IAM-14, IAM-15, IAM-17, IAM-20..23, IAM-38, IAM-39), a port of RN
/// `InAppCardView` and `NottiInAppViewFactory` (`NottiInAppViews.swift:108-277, 607-747`): plain-text title and body
/// in a scroll view (with the image), the button row below it or, when the buttons alone are taller than the card's
/// room, inside the scroll view after the text, and the close control at the top-trailing corner, outside the
/// scroll view. The layouts (`NottiInAppBarLayout`, `NottiInAppCardLayout`) size and place it; it never reports an
/// impression. Only the first outcome is delivered: a second tap on a closing display is ignored.
@available(iOSApplicationExtension, unavailable)
final class NottiInAppMessageView: UIView {

    /// How the content is arranged: `bar` (`top`, `bottom`: leading thumbnail), `card` (`center`: image above
    /// the text, cropped), `fill` (`full`: the scroll view takes the free height, buttons pinned to the bottom).
    enum Kind: Equatable {
        case bar
        case card
        case fill

        init(_ format: NottiInAppFormat) {
            switch format {
            case .top, .bottom: self = .bar
            case .center: self = .card
            case .full: self = .fill
            }
        }
    }

    /// `button_id` of an image click (IAM-25).
    static let imageButtonId = "image"

    let message: NottiInAppMessage
    let kind: Kind
    let appearance: NottiInAppAppearance
    let scroll = UIScrollView()
    let textBlock = UIView()
    let titleLabel: UILabel
    let bodyLabel: UILabel
    /// Nil when the message has no image or it did not load (the image action is then dropped too).
    let imageView: UIImageView?
    let buttonRow: NottiInAppButtonRow?
    let closeButton: UIButton
    /// The image is tappable only when it loaded and the message has an `image_action`.
    let imageTappable: Bool

    var buttons: [UIButton] { buttonRow?.buttons ?? [] }

    /// Receives the first outcome of the display.
    var onOutcome: ((NottiInAppViewOutcome) -> Void)?

    /// The buttons do not fit below the scroll view: they scroll with the text.
    private(set) var buttonsScroll = false
    /// An outcome was reported; later ones are ignored.
    private(set) var isFinished = false
    private(set) var imageTap: UITapGestureRecognizer?

    /// `traits` pins the Dynamic Type size (tests; on iOS 17+ through `traitOverrides`, so the labels keep it); nil
    /// follows the environment, and the labels then track later size changes. `languages` picks the close label
    /// (`Locale.preferredLanguages` in production, injected by tests).
    init(
        message: NottiInAppMessage,
        image: UIImage? = nil,
        traits: UITraitCollection? = nil,
        languages: [String] = Locale.preferredLanguages
    ) {
        self.message = message
        let kind = Kind(message.format)
        self.kind = kind
        let appearance = NottiInAppAppearance(
            style: message.style, buttonCount: message.buttons.count, traits: traits ?? .current
        )
        self.appearance = appearance
        titleLabel = Self.plainLabel(message.title, font: appearance.titleFont, appearance: appearance)
        bodyLabel = Self.plainLabel(message.body, font: appearance.bodyFont, appearance: appearance)
        imageView = image.map { loaded in
            let view = UIImageView(image: loaded)
            // The card crops to its 180 pt cap; `full` shows the whole picture in the free area.
            view.contentMode = kind == .fill ? .scaleAspectFit : .scaleAspectFill
            view.clipsToBounds = true
            return view
        }
        let buttons = message.buttons.enumerated().map { index, button in
            Self.makeButton(button.label, look: appearance.buttons[index], font: appearance.buttonFont)
        }
        buttonRow = buttons.isEmpty ? nil : NottiInAppButtonRow(buttons: buttons, spacing: NottiInAppMetrics.spacing)
        closeButton = Self.makeClose(overImage: image != nil && kind != .bar, appearance: appearance)
        imageTappable = image != nil && message.imageAction != nil
        super.init(frame: .zero)
        textBlock.addSubview(titleLabel)
        textBlock.addSubview(bodyLabel)
        if let imageView = imageView { scroll.addSubview(imageView) }
        scroll.addSubview(textBlock)
        addSubview(scroll)
        if let row = buttonRow { addSubview(row) }
        addSubview(closeButton)
        if #available(iOS 17.0, *), let traits = traits {
            traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        }
        backgroundColor = appearance.background
        layer.cornerRadius = NottiInAppMetrics.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        wireControls()
        applyAccessibility(languages: languages)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Outcomes

    /// Delivers `outcome` unless one was already delivered.
    func report(_ outcome: NottiInAppViewOutcome) {
        if isFinished { return }
        isFinished = true
        onOutcome?(outcome)
    }

    @objc func handleImageTap() {
        report(.tap(buttonId: Self.imageButtonId, action: message.imageAction.map(NottiInAppButtonAction.link)))
    }

    private func wireControls() {
        closeButton.addAction(
            UIAction { [weak self] _ in self?.report(.dismiss(reason: NottiInAppDismissReason.closeButton)) },
            for: .touchUpInside
        )
        for (index, button) in buttons.enumerated() where index < message.buttons.count {
            let model = message.buttons[index]
            button.addAction(
                UIAction { [weak self] _ in self?.report(.tap(buttonId: model.id, action: model.action)) },
                for: .touchUpInside
            )
        }
        if imageTappable, let imageView = imageView {
            imageView.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleImageTap))
            imageView.addGestureRecognizer(tap)
            imageTap = tap
        }
    }

    // MARK: Accessibility

    /// Static semantics (RN `NottiInAppAccessibility.apply`, `NottiInAppViews.swift:563-581`). The close label is
    /// the only text the SDK owns; the tappable image is labeled with the author's title.
    private func applyAccessibility(languages: [String]) {
        accessibilityIdentifier = "notti.inapp.card"
        scroll.accessibilityIdentifier = "notti.inapp.scroll"
        titleLabel.accessibilityIdentifier = "notti.inapp.title"
        bodyLabel.accessibilityIdentifier = "notti.inapp.body"
        closeButton.accessibilityIdentifier = "notti.inapp.close"
        closeButton.accessibilityLabel = NottiInAppStrings.closeLabel(languages: languages)
        closeButton.accessibilityTraits = .button
        for (index, button) in buttons.enumerated() {
            button.accessibilityIdentifier = "notti.inapp.button.\(index)"
            button.accessibilityLabel = button.configuration?.title
            button.accessibilityTraits = .button
        }
        bodyLabel.isAccessibilityElement = !bodyLabel.isHidden
        titleLabel.isAccessibilityElement = !titleLabel.isHidden
        titleLabel.accessibilityTraits.insert(.header)
        if let imageView = imageView {
            imageView.accessibilityIdentifier = "notti.inapp.image"
            imageView.isAccessibilityElement = imageTappable
            if imageTappable {
                let title = message.title
                imageView.accessibilityLabel = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
                imageView.accessibilityTraits = [.button, .image]
            }
        }
    }

    // MARK: Layout

    private var rightToLeft: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    /// Height for `width`, capped at `maxHeight` (the text scrolls beyond it).
    func fittingHeight(width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let inner = max(width - 2 * NottiInAppMetrics.padding, 0)
        return min(2 * NottiInAppMetrics.padding + contentHeight(inner) + fixedHeight(inner), maxHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding = NottiInAppMetrics.padding
        let inner = max(bounds.width - 2 * padding, 0)
        let fixed = fixedHeight(inner)
        let content = contentHeight(inner)
        let room = max(bounds.height - 2 * padding, 0)
        placeButtons(inScroll: buttonRow != nil && fixed > room)
        let scrollHeight: CGFloat
        if buttonsScroll {
            scrollHeight = room
            scroll.contentSize = CGSize(width: inner, height: content + fixed)
        } else {
            let available = max(room - fixed, 0)
            scrollHeight = kind == .fill ? available : min(content, available)
            scroll.contentSize = CGSize(width: inner, height: kind == .fill ? max(content, scrollHeight) : content)
        }
        scroll.frame = CGRect(x: padding, y: padding, width: inner, height: scrollHeight)
        layoutContent(inner)
        if let row = buttonRow {
            // In the scroll view the row follows the content, in its coordinates.
            row.rightToLeft = rightToLeft
            row.frame = CGRect(
                x: buttonsScroll ? 0 : padding,
                y: (buttonsScroll ? content : padding + scrollHeight) + NottiInAppMetrics.buttonTopGap,
                width: inner,
                height: fixed - NottiInAppMetrics.buttonTopGap
            )
        }
        let size = NottiInAppMetrics.closeTarget
        let inset = NottiInAppMetrics.closeInset
        closeButton.frame = CGRect(
            x: rightToLeft ? inset : bounds.width - size - inset, y: inset, width: size, height: size
        )
    }

    /// Moves the button row between the card and the scroll view (rotation, text size change); the close
    /// control stays on top.
    private func placeButtons(inScroll: Bool) {
        guard let row = buttonRow else { return }
        let changed = inScroll != buttonsScroll
        buttonsScroll = inScroll
        if inScroll, row.superview !== scroll {
            scroll.addSubview(row)
        } else if !inScroll, row.superview !== self {
            insertSubview(row, belowSubview: closeButton)
        }
        // The content just got shorter or taller: start again from its top.
        if changed { scroll.contentOffset = .zero }
    }

    private func layoutContent(_ inner: CGFloat) {
        let width = textWidth(inner)
        let height = textHeight(width)
        if kind == .bar {
            var leading: CGFloat = 0
            if let imageView = imageView {
                let size = NottiInAppMetrics.thumbnail
                imageView.frame = CGRect(x: rightToLeft ? inner - size : 0, y: 0, width: size, height: size)
                leading = size + NottiInAppMetrics.imageGap
            }
            let originX = rightToLeft ? inner - leading - width : leading
            textBlock.frame = CGRect(x: originX, y: 0, width: width, height: height)
        } else {
            var originY: CGFloat = 0
            var imageHeight = imageHeight(inner)
            // `full`: the image also takes the room the text leaves free (contained, never cropped).
            // Not when the buttons scroll: they follow the content.
            if kind == .fill, !buttonsScroll, imageView != nil, imageHeight > 0 {
                let free = scroll.bounds.height - NottiInAppMetrics.imageGap - height
                imageHeight = max(imageHeight, free)
            }
            if let imageView = imageView, imageHeight > 0 {
                imageView.frame = CGRect(x: 0, y: 0, width: inner, height: imageHeight)
                originY = imageHeight + NottiInAppMetrics.imageGap
            }
            // Without an image the title sits next to the close control: keep it clear.
            let originX = rightToLeft && imageView == nil ? NottiInAppMetrics.closeReserve : 0
            textBlock.frame = CGRect(x: originX, y: originY, width: width, height: height)
        }
        let titleHeight = labelHeight(titleLabel, width)
        titleLabel.frame = CGRect(x: 0, y: 0, width: width, height: titleHeight)
        let bodyY = titleHeight > 0 && !bodyLabel.isHidden ? titleHeight + NottiInAppMetrics.titleBodyGap : titleHeight
        bodyLabel.frame = CGRect(x: 0, y: bodyY, width: width, height: labelHeight(bodyLabel, width))
    }

    private func textWidth(_ inner: CGFloat) -> CGFloat {
        var width = inner
        if kind == .bar, imageView != nil { width -= NottiInAppMetrics.thumbnail + NottiInAppMetrics.imageGap }
        if kind == .bar || imageView == nil { width -= NottiInAppMetrics.closeReserve }
        return max(width, 0)
    }

    private func labelHeight(_ label: UILabel, _ width: CGFloat) -> CGFloat {
        if label.isHidden { return 0 }
        return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    private func textHeight(_ width: CGFloat) -> CGFloat {
        let titleHeight = labelHeight(titleLabel, width)
        let bodyHeight = labelHeight(bodyLabel, width)
        let gap = titleHeight > 0 && bodyHeight > 0 ? NottiInAppMetrics.titleBodyGap : 0
        return titleHeight + gap + bodyHeight
    }

    private func imageHeight(_ inner: CGFloat) -> CGFloat {
        guard kind != .bar, let size = imageView?.image?.size, size.width > 0 else { return 0 }
        return min(NottiInAppMetrics.imageMaxHeight, inner * size.height / size.width)
    }

    private func contentHeight(_ inner: CGFloat) -> CGFloat {
        let text = textHeight(textWidth(inner))
        if kind == .bar { return imageView != nil ? max(NottiInAppMetrics.thumbnail, text) : text }
        let imageHeight = imageHeight(inner)
        return imageHeight > 0 ? imageHeight + NottiInAppMetrics.imageGap + text : text
    }

    private func fixedHeight(_ inner: CGFloat) -> CGFloat {
        guard let row = buttonRow else { return 0 }
        return NottiInAppMetrics.buttonTopGap + row.height(forWidth: inner)
    }

    // MARK: Building

    /// A `String`, rendered verbatim with newlines kept: no markup, no link detection (IAM-23).
    private static func plainLabel(_ value: String, font: UIFont, appearance: NottiInAppAppearance) -> UILabel {
        let label = UILabel()
        label.text = value
        label.adjustsFontForContentSizeCategory = true
        label.font = font
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textColor = appearance.text
        label.textAlignment = appearance.textAlignment
        label.isHidden = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return label
    }

    private static func makeButton(_ label: String, look: NottiInAppButtonLook, font: UIFont) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = label
        config.titleAlignment = .center
        config.titleLineBreakMode = .byWordWrapping
        config.baseForegroundColor = look.text
        config.background.backgroundColor = look.background
        config.background.cornerRadius = NottiInAppMetrics.buttonCornerRadius
        config.cornerStyle = .fixed
        config.contentInsets = NSDirectionalEdgeInsets(
            top: NottiInAppMetrics.spacing,
            leading: NottiInAppMetrics.padding,
            bottom: NottiInAppMetrics.spacing,
            trailing: NottiInAppMetrics.padding
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = font
            return updated
        }
        return UIButton(configuration: config)
    }

    /// Over an image (`center`, `full`) a white glyph on a black 40% capsule; else tinted from the text color.
    private static func makeClose(overImage: Bool, appearance: NottiInAppAppearance) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline)
        )
        config.baseForegroundColor = overImage ? .white : appearance.text
        if overImage {
            config.background.backgroundColor = UIColor.black.withAlphaComponent(NottiInAppMetrics.scrimAlpha)
            config.cornerStyle = .capsule
        }
        return UIButton(configuration: config)
    }
}

/// Buttons side by side (equal width, reversed under right-to-left) when each label fits half the width on one
/// line, else one per row; each at least 44 pt tall. Measured, never guessed (RN `InAppButtonRow`,
/// `NottiInAppViews.swift:279-341`).
@available(iOSApplicationExtension, unavailable)
final class NottiInAppButtonRow: UIView {

    let buttons: [UIButton]
    private let spacing: CGFloat

    /// Set by the card on each layout pass.
    var rightToLeft = false
    private(set) var stacked = false

    init(buttons: [UIButton], spacing: CGFloat) {
        self.buttons = buttons
        self.spacing = spacing
        super.init(frame: .zero)
        buttons.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func half(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(buttons.count - 1)) / CGFloat(max(1, buttons.count))
    }

    private func isStacked(_ width: CGFloat) -> Bool {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return buttons.count > 1 && buttons.contains { $0.sizeThatFits(unbounded).width > half(width) }
    }

    private func buttonHeight(_ button: UIButton, _ width: CGFloat) -> CGFloat {
        let fitted = button.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return max(NottiInAppMetrics.closeTarget, ceil(fitted))
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        if buttons.count <= 1 || isStacked(width) {
            let heights = buttons.map { buttonHeight($0, width) }
            return heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
        }
        // Same height for both, so the row reads as one control group.
        return buttons.map { buttonHeight($0, half(width)) }.max() ?? 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        stacked = isStacked(width)
        if buttons.count <= 1 || stacked {
            var originY: CGFloat = 0
            for button in buttons {
                let height = buttonHeight(button, width)
                button.frame = CGRect(x: 0, y: originY, width: width, height: height)
                originY += height + spacing
            }
        } else {
            let itemWidth = half(width)
            let height = bounds.height
            let ordered = rightToLeft ? buttons.reversed() : buttons
            for (index, button) in ordered.enumerated() {
                button.frame = CGRect(
                    x: CGFloat(index) * (itemWidth + spacing), y: 0, width: itemWidth, height: height
                )
            }
        }
    }
}
