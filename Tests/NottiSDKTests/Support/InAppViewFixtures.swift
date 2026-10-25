import UIKit
@testable import NottiSDK

/// Builders for the In-App view tests: synthetic messages (`fixture` text), solid images, trait collections.
enum InAppViewFixtures {

    static let regular = UITraitCollection(preferredContentSizeCategory: .large)
    static let largest = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
    static let english = ["en"]

    /// 500 characters, the server's body limit.
    static let body500 = String(repeating: "fixture body text ", count: 28).prefix(500).description

    static func message(
        _ format: NottiInAppFormat,
        title: String = "fixture title",
        body: String = "fixture body",
        style: [String: Any] = [:],
        buttons: [NottiInAppButton] = [],
        imageAction: NottiInAppLinkAction? = nil
    ) -> NottiInAppMessage {
        NottiInAppMessage(
            id: "fixture-message",
            format: format,
            title: title,
            body: body,
            imageUrl: URL(string: "https://example.invalid/fixture.png"),
            imageAction: imageAction,
            rawStyle: style,
            dismissAfterSeconds: nil,
            trigger: .sessionStart,
            buttons: buttons,
            renderable: true
        )
    }

    static func button(_ id: String, _ label: String, _ action: NottiInAppButtonAction? = nil) -> NottiInAppButton {
        NottiInAppButton(id: id, label: label, action: action)
    }

    static func picture(width: CGFloat = 120, height: CGFloat = 80) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func view(
        _ message: NottiInAppMessage,
        image: UIImage? = nil,
        traits: UITraitCollection = regular
    ) -> NottiInAppMessageView {
        hosted(NottiInAppMessageView(message: message, image: image, traits: traits, languages: english))
    }

    /// Windows kept alive for the hosted views. A plain `UIWindow(frame:)`, never shown nor made key and never
    /// from `UIApplication.shared`: outside a window a label ignores the injected content size category.
    private static var hosts: [UIWindow] = []

    /// Puts `view` in its own offscreen window so the injected traits (`traitOverrides`, iOS 17+) reach its labels.
    static func hosted<View: UIView>(_ view: View) -> View {
        if hosts.count > 64 { hosts.removeFirst(32) }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 2000, height: 2000))
        window.addSubview(view)
        hosts.append(window)
        return view
    }

    /// Sizes the card to its fitting height (capped) at `width` and lays it out.
    @discardableResult
    static func layoutCard(_ view: NottiInAppMessageView, width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let height = view.fittingHeight(width: width, maxHeight: maxHeight)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.layoutIfNeeded()
        view.buttonRow?.layoutIfNeeded()
        return height
    }

    static func resolved(_ color: UIColor?, _ style: UIUserInterfaceStyle) -> UIColor? {
        color?.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    /// The repo root, from this file's path.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
