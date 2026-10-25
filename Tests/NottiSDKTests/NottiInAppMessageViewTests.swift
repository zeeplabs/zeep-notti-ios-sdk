import UIKit
import XCTest
@testable import NottiSDK

/// T14: the card shared by every layout (IAM-14, IAM-15 buttons, IAM-17, IAM-20..23, IAM-38 element side, IAM-39),
/// laid out offscreen at fixed sizes with injected traits and languages. RN 0.8.0 metrics are literals.
final class NottiInAppMessageViewTests: XCTestCase {

    private typealias Fix = InAppViewFixtures

    private let markup = "**bold** <b>x</b> [l](https://example.invalid)"

    // MARK: Plain text (IAM-23)

    func test_titleAndBodyAreVerbatimWithNoMarkupAttributes() throws {
        let body = "# fixture\nsecond &amp; line\n\nthird"
        let view = Fix.view(Fix.message(.center, title: markup, body: body))
        XCTAssertEqual(view.titleLabel.text, markup)
        XCTAssertEqual(view.bodyLabel.text, body)
        for label in [view.titleLabel, view.bodyLabel] {
            let text = try XCTUnwrap(label.attributedText)
            let whole = NSRange(location: 0, length: text.length)
            text.enumerateAttribute(.link, in: whole) { value, _, _ in XCTAssertNil(value) }
            // One run per attribute over the whole string: nothing bold, linked or re-paragraphed from markup.
            for key in [NSAttributedString.Key.font, .paragraphStyle, .foregroundColor] {
                var range = NSRange(location: 0, length: 0)
                _ = text.attribute(key, at: 0, effectiveRange: &range)
                XCTAssertEqual(range, whole, "\(key.rawValue)")
            }
            XCTAssertEqual(label.numberOfLines, 0)
            XCTAssertEqual(label.lineBreakMode, .byWordWrapping)
        }
        XCTAssertTrue(view.bodyLabel.text?.contains("\n") ?? false)
    }

    func test_aBlankTitleIsHiddenAndTheBodyMovesToTheTop() {
        let view = Fix.view(Fix.message(.center, title: " \n ", body: "fixture body"))
        Fix.layoutCard(view, width: 351, maxHeight: 700)
        XCTAssertTrue(view.titleLabel.isHidden)
        XCTAssertFalse(view.bodyLabel.isHidden)
        XCTAssertEqual(view.bodyLabel.frame.minY, 0)
        XCTAssertTrue(Fix.view(Fix.message(.top, title: "fixture title", body: "  ")).bodyLabel.isHidden)
    }

    // MARK: Style (IAM-20, IAM-22)

    func test_validTokensColorEveryPartAndStayFixedInBothThemes() {
        let style: [String: Any] = [
            "background_color": "#112233", "text_color": "#445566",
            "button_color": "#778899", "button_text_color": "#AABBCC"
        ]
        let view = Fix.view(Fix.message(.top, style: style, buttons: [Fix.button("a", "A"), Fix.button("b", "B")]))
        let expect = { (rgb: UInt32) in UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1
        ) }
        for theme in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertEqual(Fix.resolved(view.backgroundColor, theme), expect(0x112233))
            XCTAssertEqual(Fix.resolved(view.titleLabel.textColor, theme), expect(0x445566))
            XCTAssertEqual(Fix.resolved(view.bodyLabel.textColor, theme), expect(0x445566))
            XCTAssertEqual(Fix.resolved(view.closeButton.configuration?.baseForegroundColor, theme), expect(0x445566))
            for button in view.buttons {
                XCTAssertEqual(Fix.resolved(button.configuration?.background.backgroundColor, theme), expect(0x778899))
                XCTAssertEqual(Fix.resolved(button.configuration?.baseForegroundColor, theme), expect(0xAABBCC))
            }
        }
        XCTAssertEqual(view.appearance.buttons.map(\.kind), [.filled, .filled])
    }

    func test_anInvalidTokenFallsBackToItsOwnDefault() {
        let style: [String: Any] = [
            "background_color": "#12345", "text_color": "red", "button_color": 0x112233, "button_text_color": "#FFAABBCC"
        ]
        let view = Fix.view(Fix.message(.center, style: style, buttons: [Fix.button("a", "A"), Fix.button("b", "B")]))
        XCTAssertEqual(view.backgroundColor, .secondarySystemBackground)
        XCTAssertEqual(view.titleLabel.textColor, .label)
        XCTAssertEqual(view.buttons[0].configuration?.background.backgroundColor, .systemBlue)
        XCTAssertEqual(view.buttons[1].configuration?.background.backgroundColor, .tertiarySystemFill)
        XCTAssertEqual(view.buttons[1].configuration?.baseForegroundColor, .label)
    }

    func test_oneButtonTokenFillsEveryButtonAndTheOtherKeepsItsDefault() {
        let view = Fix.view(Fix.message(
            .center, style: ["button_text_color": "#000000"], buttons: [Fix.button("a", "A"), Fix.button("b", "B")]
        ))
        for button in view.buttons {
            XCTAssertEqual(button.configuration?.background.backgroundColor, .systemBlue)
            XCTAssertEqual(Fix.resolved(button.configuration?.baseForegroundColor, .light),
                           UIColor(red: 0, green: 0, blue: 0, alpha: 1))
        }
        XCTAssertEqual(view.appearance.buttons.map(\.kind), [.filled, .filled])
    }

    func test_withoutTokensTheDefaultsAreSemanticAndTheSecondButtonIsTinted() {
        let view = Fix.view(Fix.message(.center, buttons: [Fix.button("a", "A"), Fix.button("b", "B")]))
        XCTAssertEqual(view.backgroundColor, .secondarySystemBackground)
        XCTAssertEqual(view.titleLabel.textColor, .label)
        XCTAssertEqual(view.closeButton.configuration?.baseForegroundColor, .label)
        XCTAssertEqual(view.buttons[0].configuration?.background.backgroundColor, .systemBlue)
        XCTAssertEqual(view.buttons[0].configuration?.baseForegroundColor, .white)
        XCTAssertEqual(view.buttons[1].configuration?.background.backgroundColor, .tertiarySystemFill)
        XCTAssertEqual(view.buttons[1].configuration?.baseForegroundColor, .label)
        XCTAssertEqual(view.appearance.buttons.map(\.kind), [.filled, .tinted])
        XCTAssertNotEqual(Fix.resolved(view.backgroundColor, .light), Fix.resolved(view.backgroundColor, .dark))
        XCTAssertEqual(view.layer.cornerRadius, 12)
    }

    func test_fontsAreHeadlineSubheadlineAndBoldSubheadline() throws {
        let view = Fix.view(Fix.message(.center, buttons: [Fix.button("a", "A")]))
        let traits = Fix.regular
        XCTAssertEqual(view.titleLabel.font, UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits))
        XCTAssertEqual(view.bodyLabel.font, UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits))
        let transformer = try XCTUnwrap(view.buttons[0].configuration?.titleTextAttributesTransformer)
        let font = try XCTUnwrap(transformer(AttributeContainer()).uiKit.font)
        let subheadline = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        XCTAssertEqual(font.pointSize, subheadline.pointSize)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertTrue(view.titleLabel.adjustsFontForContentSizeCategory)
        XCTAssertTrue(view.bodyLabel.adjustsFontForContentSizeCategory)
    }

    func test_theLargestContentSizeGivesLargerFonts() {
        let regular = Fix.view(Fix.message(.center), traits: Fix.regular)
        let largest = Fix.view(Fix.message(.center), traits: Fix.largest)
        XCTAssertGreaterThan(largest.bodyLabel.font.pointSize, regular.bodyLabel.font.pointSize)
        XCTAssertGreaterThan(largest.titleLabel.font.pointSize, regular.titleLabel.font.pointSize)
    }

    // MARK: Alignment (IAM-21)

    func test_alignmentIsAbsoluteUnderRightToLeft() {
        for (raw, expected) in [("right", NSTextAlignment.right), ("left", .left), ("center", .center), ("start", .left)] {
            let view = Fix.view(Fix.message(.center, style: ["text_align": raw]))
            view.semanticContentAttribute = .forceRightToLeft
            for label in [view.titleLabel, view.bodyLabel] {
                label.semanticContentAttribute = .forceRightToLeft
                XCTAssertEqual(label.textAlignment, expected, raw)
                XCTAssertNotEqual(label.textAlignment, .natural, raw)
            }
        }
    }

    // MARK: Close control (IAM-14)

    func test_closeIs44At8FromTheTopTrailingCornerOutsideTheScroll() {
        for format in [NottiInAppFormat.top, .bottom, .center, .full] {
            let view = Fix.view(Fix.message(format, body: Fix.body500))
            Fix.layoutCard(view, width: 351, maxHeight: 300)
            let close = view.closeButton.frame
            XCTAssertEqual(close.size, CGSize(width: 44, height: 44), "\(format)")
            XCTAssertEqual(close.minY, 8, "\(format)")
            XCTAssertEqual(view.bounds.width - close.maxX, 8, "\(format)")
            XCTAssertTrue(view.closeButton.superview === view, "\(format)")
            XCTAssertFalse(view.closeButton.isDescendant(of: view.scroll), "\(format)")
            XCTAssertTrue(view.subviews.last === view.closeButton, "\(format)")
        }
    }

    func test_closeIsTopLeadingUnderRightToLeftAndTheTextKeepsClear() {
        let view = Fix.view(Fix.message(.center, title: String(repeating: "fixture title ", count: 10)))
        view.semanticContentAttribute = .forceRightToLeft
        Fix.layoutCard(view, width: 351, maxHeight: 700)
        XCTAssertEqual(view.closeButton.frame.minX, 8)
        XCTAssertEqual(view.closeButton.frame.minY, 8)
        let text = view.scroll.convert(view.textBlock.frame, to: view)
        XCTAssertGreaterThanOrEqual(text.minX, view.closeButton.frame.maxX - 0.5)
    }

    func test_overAnImageOnCenterTheGlyphIsWhiteOnABlack40PercentCapsule() throws {
        let view = Fix.view(Fix.message(.center), image: Fix.picture())
        let config = try XCTUnwrap(view.closeButton.configuration)
        XCTAssertEqual(config.baseForegroundColor, .white)
        var white: CGFloat = 1
        var alpha: CGFloat = 0
        XCTAssertTrue(try XCTUnwrap(config.background.backgroundColor).getWhite(&white, alpha: &alpha))
        XCTAssertEqual(white, 0)
        XCTAssertEqual(alpha, 0.4, accuracy: 0.001)
        XCTAssertEqual(config.cornerStyle, .capsule)
        // A bar thumbnail is not under the close control: no chip, tinted from the text color.
        let bar = Fix.view(Fix.message(.top, style: ["text_color": "#445566"]), image: Fix.picture())
        var barAlpha: CGFloat = 0
        bar.closeButton.configuration?.background.backgroundColor?.getWhite(nil, alpha: &barAlpha)
        XCTAssertEqual(barAlpha, 0, "no chip on a bar")
        XCTAssertEqual(bar.closeButton.configuration?.baseForegroundColor, bar.titleLabel.textColor)
    }

    // MARK: Buttons (IAM-15, IAM-17)

    func test_twoShortLabelsSitSideBySideAndALongOneStacksBoth() {
        let short = Fix.view(Fix.message(.bottom, buttons: [Fix.button("a", "Yes"), Fix.button("b", "No")]))
        Fix.layoutCard(short, width: 358, maxHeight: 337)
        let row = short.buttonRow
        XCTAssertEqual(row?.stacked, false)
        XCTAssertEqual(short.buttons[0].frame.minY, short.buttons[1].frame.minY)
        XCTAssertLessThanOrEqual(short.buttons[0].frame.maxX, short.buttons[1].frame.minX)
        XCTAssertEqual(short.buttons[0].frame.width, short.buttons[1].frame.width)

        let long = String(repeating: "fixture ", count: 6)
        let stacked = Fix.view(Fix.message(.bottom, buttons: [Fix.button("a", long), Fix.button("b", "No")]))
        Fix.layoutCard(stacked, width: 358, maxHeight: 337)
        XCTAssertEqual(stacked.buttonRow?.stacked, true)
        XCTAssertGreaterThanOrEqual(stacked.buttons[1].frame.minY, stacked.buttons[0].frame.maxY)
        XCTAssertEqual(stacked.buttons[0].frame.width, stacked.buttonRow?.bounds.width)
        for button in short.buttons + stacked.buttons {
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    func test_sideBySideButtonsAreReversedUnderRightToLeft() {
        let view = Fix.view(Fix.message(.center, buttons: [Fix.button("a", "Yes"), Fix.button("b", "No")]))
        view.semanticContentAttribute = .forceRightToLeft
        Fix.layoutCard(view, width: 351, maxHeight: 700)
        XCTAssertEqual(view.buttonRow?.stacked, false)
        XCTAssertGreaterThan(view.buttons[0].frame.minX, view.buttons[1].frame.minX)
    }

    func test_aLongBodyAtTheLargestSizeScrollsAndKeepsCloseAndButtonsVisible() {
        let view = Fix.view(
            Fix.message(.center, body: Fix.body500, buttons: [Fix.button("a", "Yes"), Fix.button("b", "No")]),
            traits: Fix.largest
        )
        Fix.layoutCard(view, width: 351, maxHeight: 600)
        XCTAssertEqual(view.bounds.height, 600)
        XCTAssertGreaterThan(view.scroll.contentSize.height, view.scroll.bounds.height)
        XCTAssertFalse(view.buttonsScroll)
        XCTAssertTrue(view.bounds.contains(view.closeButton.frame))
        for button in view.buttons {
            let inCard = button.convert(button.bounds, to: view)
            XCTAssertTrue(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(inCard))
            XCTAssertFalse(button.isHidden)
        }
        XCTAssertEqual(view.buttonRow?.frame.maxY ?? 0, 600 - 16, accuracy: 0.5)
    }

    func test_buttonsTallerThanTheRoomMoveIntoTheScrollAndBackOut() throws {
        let labels = [Fix.button("a", "fixture turn on notifications now"), Fix.button("b", "fixture remind me later")]
        let view = Fix.view(Fix.message(.top, buttons: labels), traits: Fix.largest)
        Fix.layoutCard(view, width: 600, maxHeight: 157)
        let row = try XCTUnwrap(view.buttonRow)
        XCTAssertTrue(view.buttonsScroll)
        XCTAssertTrue(row.superview === view.scroll)
        XCTAssertGreaterThanOrEqual(row.frame.minY, view.textBlock.frame.maxY)
        XCTAssertLessThanOrEqual(row.frame.maxY, view.scroll.contentSize.height + 0.5)
        XCTAssertEqual(view.scroll.frame.maxY, view.bounds.height - 16, accuracy: 0.5)
        XCTAssertTrue(view.closeButton.superview === view)

        view.scroll.contentOffset = CGPoint(x: 0, y: 40)
        Fix.layoutCard(view, width: 600, maxHeight: 900)
        XCTAssertFalse(view.buttonsScroll)
        XCTAssertTrue(row.superview === view)
        XCTAssertEqual(view.scroll.contentOffset, .zero)
        XCTAssertEqual(row.frame.maxY, view.bounds.height - 16, accuracy: 0.5)
        let subviews = view.subviews
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: row)), try XCTUnwrap(subviews.firstIndex(of: view.closeButton)))
    }

    // MARK: Accessibility (IAM-38, element side)

    func test_titleIsAHeaderApartFromTheBodyAndButtonsCarryTheirLabel() {
        let view = Fix.view(Fix.message(.center, buttons: [Fix.button("a", "fixture yes"), Fix.button("b", "fixture no")]))
        XCTAssertTrue(view.titleLabel.isAccessibilityElement)
        XCTAssertTrue(view.bodyLabel.isAccessibilityElement)
        XCTAssertTrue(view.titleLabel.accessibilityTraits.contains(.header))
        XCTAssertFalse(view.bodyLabel.accessibilityTraits.contains(.header))
        XCTAssertFalse(view.textBlock.isAccessibilityElement)
        XCTAssertEqual(view.buttons.map(\.accessibilityLabel), ["fixture yes", "fixture no"])
        for button in view.buttons { XCTAssertTrue(button.accessibilityTraits.contains(.button)) }
        XCTAssertEqual(view.closeButton.accessibilityLabel, "Close")
        XCTAssertTrue(view.closeButton.accessibilityTraits.contains(.button))
        let portuguese = NottiInAppMessageView(message: Fix.message(.top), traits: Fix.regular, languages: ["pt-BR"])
        XCTAssertEqual(portuguese.closeButton.accessibilityLabel, "Fechar")
    }

    func test_theImageIsAnElementOnlyWhenTappableAndThenLabeledWithTheTitle() {
        let decorative = Fix.view(Fix.message(.center), image: Fix.picture())
        XCTAssertEqual(decorative.imageView?.isAccessibilityElement, false)
        XCTAssertFalse(decorative.imageTappable)
        XCTAssertNil(decorative.imageTap)

        let action = NottiInAppLinkAction(type: .deeplink, value: "fixture://promo")
        let tappable = Fix.view(Fix.message(.center, title: "fixture title", imageAction: action), image: Fix.picture())
        XCTAssertEqual(tappable.imageView?.isAccessibilityElement, true)
        XCTAssertEqual(tappable.imageView?.accessibilityTraits, [.button, .image])
        XCTAssertEqual(tappable.imageView?.accessibilityLabel, "fixture title")

        let untitled = Fix.view(Fix.message(.center, title: "  ", imageAction: action), image: Fix.picture())
        XCTAssertNil(untitled.imageView?.accessibilityLabel)
        // No image loaded: no image view, so no image action either.
        XCTAssertNil(Fix.view(Fix.message(.center, imageAction: action)).imageView)
        XCTAssertFalse(Fix.view(Fix.message(.center, imageAction: action)).imageTappable)
    }

    func test_everyPartHasItsAccessibilityIdentifier() {
        let view = Fix.view(Fix.message(.center, buttons: [Fix.button("a", "A"), Fix.button("b", "B")]), image: Fix.picture())
        XCTAssertEqual(view.accessibilityIdentifier, "notti.inapp.card")
        XCTAssertEqual(view.titleLabel.accessibilityIdentifier, "notti.inapp.title")
        XCTAssertEqual(view.bodyLabel.accessibilityIdentifier, "notti.inapp.body")
        XCTAssertEqual(view.closeButton.accessibilityIdentifier, "notti.inapp.close")
        XCTAssertEqual(view.imageView?.accessibilityIdentifier, "notti.inapp.image")
        XCTAssertEqual(view.scroll.accessibilityIdentifier, "notti.inapp.scroll")
        XCTAssertEqual(view.buttons.map(\.accessibilityIdentifier), ["notti.inapp.button.0", "notti.inapp.button.1"])
    }

    // MARK: Outcomes

    func test_controlsReportTheirOutcomeAndOnlyTheFirstCounts() {
        let link = NottiInAppLinkAction(type: .url, value: "https://example.invalid/a?b=1")
        let buttons = [Fix.button("yes", "Yes", .link(link)), Fix.button("perm", "Allow", .pushPermission)]
        var outcomes: [NottiInAppViewOutcome] = []
        let view = Fix.view(Fix.message(.center, buttons: buttons))
        view.onOutcome = { outcomes.append($0) }
        view.buttons[1].sendActions(for: .touchUpInside)
        view.buttons[0].sendActions(for: .touchUpInside)
        view.closeButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(outcomes, [.tap(buttonId: "perm", action: .pushPermission)])
        XCTAssertTrue(view.isFinished)

        var closes: [NottiInAppViewOutcome] = []
        let closing = Fix.view(Fix.message(.full, buttons: buttons))
        closing.onOutcome = { closes.append($0) }
        closing.closeButton.sendActions(for: .touchUpInside)
        closing.buttons[0].sendActions(for: .touchUpInside)
        XCTAssertEqual(closes, [.dismiss(reason: "close_button")])

        var taps: [NottiInAppViewOutcome] = []
        let first = Fix.view(Fix.message(.top, buttons: buttons))
        first.onOutcome = { taps.append($0) }
        first.buttons[0].sendActions(for: .touchUpInside)
        XCTAssertEqual(taps, [.tap(buttonId: "yes", action: .link(link))])
    }

    func test_aTappableImageReportsTheImageIdWithItsLink() {
        let action = NottiInAppLinkAction(type: .deeplink, value: "fixture://promo")
        let view = Fix.view(Fix.message(.center, imageAction: action), image: Fix.picture())
        var outcomes: [NottiInAppViewOutcome] = []
        view.onOutcome = { outcomes.append($0) }
        XCTAssertTrue(view.imageTap?.view === view.imageView)
        view.handleImageTap()
        view.handleImageTap()
        XCTAssertEqual(outcomes, [.tap(buttonId: "image", action: .link(action))])
    }

    // MARK: Pure bounds (RN computeFrame)

    func test_layoutFramesUseTheRNMetrics() {
        let notch = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let size = CGSize(width: 390, height: 844)
        let top = NottiInAppLayout.frame(format: .top, margin: true, container: size, safe: notch)
        XCTAssertEqual(top, NottiInAppFrame(
            gravity: .top, marginLeft: 16, marginTop: 75, marginRight: 16, marginBottom: 50, width: 358,
            maxHeight: min(844 * 0.4, 844 - 59 - 34 - 32)
        ))
        let bare = NottiInAppLayout.frame(format: .bottom, margin: false, container: size, safe: notch)
        XCTAssertEqual(bare.gravity, .bottom)
        XCTAssertEqual([bare.marginLeft, bare.marginBottom, bare.width], [0, 34, 390])
        let center = NottiInAppLayout.frame(format: .center, margin: true, container: size, safe: notch)
        XCTAssertEqual(center.width, 351)
        XCTAssertEqual(center.maxHeight, (844 - 93) * 0.9, accuracy: 0.001)
        XCTAssertEqual(NottiInAppLayout.frame(format: .center, margin: false, container: size, safe: notch), center)
        let iPad = NottiInAppLayout.frame(format: .center, margin: true, container: CGSize(width: 1024, height: 1366), safe: .zero)
        XCTAssertEqual(iPad.width, 560)
        let full = NottiInAppLayout.frame(format: .full, margin: true, container: size, safe: notch)
        XCTAssertEqual(NottiInAppLayout.cardRect(full, height: full.maxHeight, container: size),
                       CGRect(x: 16, y: 75, width: 358, height: 844 - 93 - 32))
    }

    func test_aCenterCardIsCenteredInAnAsymmetricSafeArea() {
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
        let size = CGSize(width: 844, height: 390)
        let frame = NottiInAppLayout.frame(format: .center, margin: true, container: size, safe: safe)
        XCTAssertEqual(frame.width, 560)
        let rect = NottiInAppLayout.cardRect(frame, height: 200, container: size)
        XCTAssertEqual(rect.midX, 59 + 785 / 2, accuracy: 0.001)
        XCTAssertEqual(rect.midY, (390 - 21) / 2, accuracy: 0.001)
    }

    // MARK: Banned APIs (IAM-23, IAM-24)

    func test_theUISourcesUseNoMarkupWebViewOrURLOpening() throws {
        let directory = Fix.repoRoot.appendingPathComponent("Sources/NottiSDK/InApp/UI")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertTrue(files.contains { $0.lastPathComponent == "NottiInAppMessageView.swift" })
        let banned = ["attributed" + "Text", "Attributed" + "String", "WK" + "WebView", "LocalizedString" + "Key", "open" + "URL"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) contains \(token)")
            }
        }
    }
}
