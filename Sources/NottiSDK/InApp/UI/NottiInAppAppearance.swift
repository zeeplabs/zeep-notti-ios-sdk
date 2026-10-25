import UIKit

/// How one button is drawn: filled with an accent or author color, or tinted (the default second button).
@available(iOSApplicationExtension, unavailable)
struct NottiInAppButtonLook: Equatable {
    enum Kind: Equatable {
        case filled
        case tinted
    }

    let kind: Kind
    let background: UIColor
    let text: UIColor
}

/// `NottiInAppStyle` resolved to what the views apply (IAM-20..22, IAM-39), a port of RN `resolveStyle`
/// (`NottiInAppStyle.swift:66-94`) and of the fonts of `NottiInAppViewFactory.build` (`NottiInAppViews.swift:614-635`).
/// Each token falls back on its own to a semantic system color (light and dark follow the system); no color is
/// derived from another; author colors are opaque and fixed in both themes. A button token applies to every button.
@available(iOSApplicationExtension, unavailable)
struct NottiInAppAppearance {
    let background: UIColor
    let text: UIColor
    let textAlign: NottiInAppTextAlign
    let margin: Bool
    /// One entry per button, in order.
    let buttons: [NottiInAppButtonLook]
    let titleFont: UIFont
    let bodyFont: UIFont
    let buttonFont: UIFont

    /// `traits` picks the Dynamic Type size of the fonts; the labels then follow later changes on their own.
    init(style: NottiInAppStyle, buttonCount: Int, traits: UITraitCollection) {
        let authorButtons = style.buttonColor != nil || style.buttonTextColor != nil
        buttons = (0..<max(0, buttonCount)).map { index in
            if authorButtons {
                return NottiInAppButtonLook(
                    kind: .filled,
                    background: style.buttonColor.map(Self.color) ?? .systemBlue,
                    text: style.buttonTextColor.map(Self.color) ?? .white
                )
            }
            if index == 0 {
                return NottiInAppButtonLook(kind: .filled, background: .systemBlue, text: .white)
            }
            return NottiInAppButtonLook(kind: .tinted, background: .tertiarySystemFill, text: .label)
        }
        background = style.backgroundColor.map(Self.color) ?? .secondarySystemBackground
        text = style.textColor.map(Self.color) ?? .label
        textAlign = style.textAlign
        margin = style.margin
        titleFont = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
        bodyFont = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        buttonFont = Self.boldFont(.subheadline, traits)
    }

    /// Absolute sides: the author picked left or right, not leading or trailing (never `.natural`).
    var textAlignment: NSTextAlignment {
        switch textAlign {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    /// An opaque `0xFFRRGGBB` token.
    static func color(_ argb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func boldFont(_ style: UIFont.TextStyle, _ traits: UITraitCollection) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        guard let bold = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: bold, size: 0)
    }
}
